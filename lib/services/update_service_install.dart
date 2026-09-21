// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

part of 'update_service.dart';

/// Platform install / replace / relaunch after a completed download.
extension UpdateServiceInstall on UpdateService {
  /// Run the update immediately and exit (or relaunch on Linux/macOS).
  Future<void> _installNowImpl() async {
    if (_pendingInstallerPath == null) return;
    try {
      // Stop child processes (KoboldCPP, etc.) before exit(0) which
      // bypasses the window close handler entirely.
      if (_shutdownCallback != null) {
        await _shutdownCallback!();
      }
      if (Platform.isLinux) {
        await _replaceAppImage(_pendingInstallerPath!);
        await _relaunchAppImage();
      } else if (Platform.isMacOS) {
        await _replaceMacApp(_pendingInstallerPath!);
        await _relaunchMacApp();
      } else {
        await _launchWindowsInstaller(_pendingInstallerPath!);
      }
      // macOS must skip C++ finalizers or the install-and-relaunch gets
      // logged as an "Abort trap: 6" crash (see exitWithoutNativeFinalizers).
      Platform.isMacOS ? exitWithoutNativeFinalizers(0) : exit(0);
    } catch (e) {
      debugPrint('Install now failed: $e');
      rethrow;
    }
  }

  /// Run the pending update on app close.
  /// Call this from the window close handler.
  Future<void> _installOnCloseImpl() async {
    if (_pendingInstallerPath == null) return;
    try {
      // Ensure child processes are stopped even if onWindowClose didn't
      // reach stopKobold() (e.g. crash or early return).
      if (_shutdownCallback != null) {
        await _shutdownCallback!();
      }
      if (Platform.isLinux) {
        await _replaceAppImage(_pendingInstallerPath!);
      } else if (Platform.isMacOS) {
        await _replaceMacApp(_pendingInstallerPath!);
      } else {
        await _launchWindowsInstaller(_pendingInstallerPath!);
      }
    } catch (e) {
      debugPrint('Install on close failed: $e');
    }
  }

  Future<void> _launchWindowsInstaller(String path) async {
    // Use /SILENT (shows license page) for 0.8→0.9 upgrades (GPL→AGPL change)
    // Use /VERYSILENT (fully silent) for same-license upgrades
    final needsLicenseAcceptance = _currentVersion.startsWith('0.8');
    final silentFlag = needsLicenseAcceptance ? '/SILENT' : '/VERYSILENT';

    // Install in place, on top of the build that is actually running, by telling
    // the installer the current install directory via /DIR. This is the reliable
    // way to find AND honor a custom install location: resolvedExecutable is
    // "<installDir>\front_porch_ai.exe", so its parent is exactly the folder the
    // user originally chose — default OR a custom drive/path — and the running app
    // is the only component that authoritatively knows it. The installer can't
    // safely rediscover a custom Nightly folder from the registry (the pre-split
    // AppId was shared with Stable/Beta, so guessing risks installing over a
    // Stable install), so we source the truth here instead.
    //
    // Without /DIR, a /VERYSILENT update falls back to the installer's default
    // directory. After the channel AppId split that is how a Nightly update forked
    // a second copy into {localappdata} and left the running build (in the user's
    // chosen folder) untouched — the update loop. /DIR makes every channel update
    // exactly where it already lives, ending that whole class of bug.
    var installDir = File(Platform.resolvedExecutable).parent.path;
    // Defensive: a trailing backslash would escape the closing quote in the
    // generated command line. Install dirs never end in a separator in practice,
    // but strip it so the quoted /DIR value can never be malformed.
    while (installDir.endsWith('\\')) {
      installDir = installDir.substring(0, installDir.length - 1);
    }

    await Process.start(path, [
      silentFlag,
      '/DIR=$installDir',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      '/CLOSEAPPLICATIONS',
    ]);
  }

  /// Replace the currently running AppImage with the downloaded update.
  /// Uses rm + cp instead of Dart's File.copy() because the destination
  /// may be a running executable — deleting first avoids write conflicts.
  Future<void> _replaceAppImage(String downloadedPath) async {
    final currentAppImage = Platform.environment['APPIMAGE'];
    if (currentAppImage == null || currentAppImage.isEmpty) {
      debugPrint('APPIMAGE env var not set — cannot replace');
      return;
    }
    debugPrint('Replacing AppImage: $currentAppImage with $downloadedPath');

    // Copy beside the target FIRST, then atomically rename over it. The old
    // order (rm the running AppImage, then cp) left the user with NO app at
    // all when the copy failed — a full disk or a bad download uninstalled
    // Front Porch. rename(2) on the same filesystem atomically replaces the
    // path while the running process keeps its unlinked inode.
    final staging = '$currentAppImage.new';
    final cpResult = await Process.run('cp', [downloadedPath, staging]);
    if (cpResult.exitCode != 0) {
      await Process.run('rm', ['-f', staging]);
      throw Exception('Failed to copy new AppImage: ${cpResult.stderr}');
    }
    await Process.run('chmod', ['+x', staging]);
    final mvResult = await Process.run('mv', ['-f', staging, currentAppImage]);
    if (mvResult.exitCode != 0) {
      await Process.run('rm', ['-f', staging]);
      throw Exception('Failed to swap new AppImage in: ${mvResult.stderr}');
    }
    debugPrint('AppImage replaced successfully');
  }

  /// Relaunch the AppImage after replacing it.
  Future<void> _relaunchAppImage() async {
    final currentAppImage = Platform.environment['APPIMAGE'];
    if (currentAppImage == null || currentAppImage.isEmpty) return;
    debugPrint('Relaunching AppImage: $currentAppImage');
    await Process.start(currentAppImage, [], mode: ProcessStartMode.detached);
  }

  /// Get the current .app bundle path from the resolved executable.
  /// e.g. /Applications/FrontPorchAI.app/Contents/MacOS/front_porch_ai
  ///   → /Applications/FrontPorchAI.app
  String get _currentMacAppPath {
    final exe = Platform.resolvedExecutable;
    // Walk up from MacOS/binary → Contents → .app
    return File(exe).parent.parent.parent.path;
  }

  /// Install the macOS update (.pkg — the only macOS asset since the legacy
  /// DMG shim path was deleted 2026-07-27 along with the shim builds).
  /// Spawns a detached shell script that:
  ///   1. Waits for this process to exit (by PID)
  ///   2. `open`s the .pkg so the user gets the standard Installer.app flow
  ///      (one auth prompt, official Apple path, signed+notarized+stapled
  ///      package installs the new .app to /Applications).
  ///
  /// Cleanup (rm of downloaded installer + script) is best-effort after launch
  /// of the consumer (Installer.app or the new app). This can race on slow disks
  /// or with detached exit(0) in the parent (errors only visible in system logs
  /// after the app has exited). For .pkg we deliberately omit payload rm so the
  /// Installer can manage its temp. Documented limitation per review feedback.
  Future<void> _replaceMacApp(String installerPath) async {
    final currentApp = _currentMacAppPath;
    final appParent = File(currentApp).parent.path;
    final appName = currentApp.split('/').last;
    final destPath = '$appParent/$appName';
    final currentPid = pid; // Current process PID (dart:io top-level getter)

    debugPrint(
      'macOS update: will handle PKG $installerPath after PID $currentPid exits (replacing $currentApp)',
    );

    // Compute the output script filename first (it is independent).
    // Robust wait + cleanup + error to stderr (bash sidecar spirit).
    final scriptPath =
        '${Directory.systemTemp.path}/fp_update_${DateTime.now().millisecondsSinceEpoch}.sh';

    // Defense-in-depth escaping for paths embedded into the generated shell
    // script (issue #12). Pid is numeric and safe. We use single-quote + ' -> '\''
    // escaping for the path values so that even if (theoretically) a path
    // contained a single quote, the generated bash remains correct. Current
    // values (asset names from GH, dest from resolvedExecutable walk) are
    // controlled and safe, but this satisfies the nit without changing quoting
    // style in the templates.
    String _shellEscape(String p) => p.replaceAll("'", r"'\''");
    final escInstaller = _shellEscape(installerPath);
    final escScript = _shellEscape(scriptPath);

    final script =
        '''#!/bin/bash
# Wait for the current app process to exit (max 30s)
for i in {1..60}; do
  if ! kill -0 $currentPid 2>/dev/null; then
    break
  fi
  sleep 0.5
done

# Primary .pkg path (signed+notarized+stapled): just hand it to the system
# Installer. User authenticates in the standard UI; the installer places
# the new bundle (preserving sidecars etc.) and handles launch.
open '$escInstaller'

# Clean up the downloaded package and this script (best effort; see race note).
# For .pkg we omit rm of the payload itself (let Installer.app / system manage
# the temp file to avoid TOCTOU/race with the launched Installer process).
rm -f '$escScript' || true

# No explicit relaunch here — Installer.app or the user will start the new app.
# (The old bundle at $destPath may be replaced in-place by the package.)
''';

    await File(scriptPath).writeAsString(script);
    await Process.run('chmod', ['+x', scriptPath]);

    // Launch the script detached — it will outlive this process
    await Process.start('/bin/bash', [
      scriptPath,
    ], mode: ProcessStartMode.detached);
    debugPrint('macOS update script launched: $scriptPath');
  }

  /// Relaunch the macOS app after replacing it.
  /// (Handled by the Installer.app flow the update script launches; kept for
  /// API symmetry and installOnClose fallback.)
  Future<void> _relaunchMacApp() async {
    // The Installer.app flow (opened by the update shell script) handles
    // placement; the user relaunches from there. Nothing to do here.
  }
}
