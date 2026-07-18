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

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:front_porch_ai/app_version.dart';

// Note: app_version.dart was already imported — UpdateService already used
// appVersion for _currentVersion. The isPreRelease getter now also guards
// the update channel so stable builds can never be offered a beta update.

/// Cross-platform self-update service.
/// Checks GitHub Releases for new versions and downloads/runs the update.
/// Supports Windows (Inno Setup), Linux (AppImage), and macOS (.pkg primary
/// with last unsigned/un-notarized DMG shim for seamless transition from
/// .app/.dmg installs to .pkg). Old clients continue to find a recognizable
/// asset; new clients prefer .pkg but fall back to legacy DMG names during
/// the transition. The shim DMGs are produced only as a bridge (one last time).
class UpdateService extends ChangeNotifier {
  static const String _repoOwner = 'linux4life1';
  static const String _repoName = 'front-porch-AI';
  static const String _windowsAssetStable = 'Front_Porch_AI_Setup.exe';
  static const String _windowsAssetBeta = 'Front_Porch_AI_Beta_Setup.exe';
  static const String _windowsAssetNightly = 'Front_Porch_AI_Nightly_Setup.exe';
  static const String _linuxAsset = 'Front_Porch_AI-Linux.AppImage';
  static const String _linuxAssetNightly =
      'Front_Porch_AI_Nightly-Linux.AppImage';
  // Primary (new canonical) asset names for macOS .pkg releases (signed+notarized).
  static const String _macosAssetPkg = 'Front_Porch_AI.pkg';
  static const String _macosAssetBetaPkg = 'Front_Porch_AI_MacOS.pkg';
  static const String _macosAssetNightlyPkg = 'Front_Porch_AI_Nightly.pkg';
  // Legacy DMG names — still published as unsigned shims for this transition
  // release (and at least one more cycle) so the in-app updater works for all
  // users (pre-pkg .dmg/.app drag installs + new .pkg installs) without forcing
  // a manual download+double-click. Client code prefers the .pkg but probes
  // these as fallback.
  static const String _macosAsset = 'Front_Porch_AI.dmg';
  static const String _macosAssetBeta = 'Front_Porch_AI_MacOS.dmg';
  static const String _macosAssetNightly = 'Front_Porch_AI_Nightly.dmg';
  static const String _prefsKeyAutoCheck = 'update_auto_check';

  String _currentVersion = '';
  String _latestVersion = '';
  String _latestReleaseTag = '';
  String _downloadUrl = '';
  String _releaseNotes = '';
  bool _updateAvailable = false;
  bool _checking = false;
  bool _downloading = false;
  bool _downloadComplete = false;
  double _downloadProgress = 0.0;
  bool _autoCheckEnabled = true;
  String? _pendingInstallerPath;
  // The actual asset filename chosen (e.g. the .pkg or the fallback legacy .dmg shim).
  // Used so download names the temp file after the real remote asset (extension
  // then drives pkg vs dmg path in the install script). Sniffing the extension
  // of _pendingInstallerPath at install time is the robust dispatch.
  String _selectedAssetName = '';

  String get currentVersion => _currentVersion;
  String get latestVersion => _latestVersion;
  String get releaseNotes => _releaseNotes;

  /// URL to the GitHub release page for the latest version found by checkForUpdate().
  /// Used by the update dialog for the "View on GitHub" fallback and for links inside
  /// rendered release notes.
  /// Uses the actual tag (e.g. "nightly-rawhide.20250519.xxx" or "v0.9.8") so links
  /// are always correct for nightly, beta, and stable channels.
  String get releaseUrl => _latestReleaseTag.isNotEmpty
      ? 'https://github.com/$_repoOwner/$_repoName/releases/tag/$_latestReleaseTag'
      : 'https://github.com/$_repoOwner/$_repoName/releases';
  bool get updateAvailable => _updateAvailable;
  bool get checking => _checking;
  bool get downloading => _downloading;
  bool get downloadComplete => _downloadComplete;
  double get downloadProgress => _downloadProgress;
  bool get autoCheckEnabled => _autoCheckEnabled;
  bool get hasPendingInstaller => _pendingInstallerPath != null;

  /// User-friendly version for UI display (avoids "vrawhide.2025..." for nightlies).
  String get displayCurrentVersion => _formatVersionForDisplay(_currentVersion);
  String get displayLatestVersion => _formatVersionForDisplay(_latestVersion);

  String _formatVersionForDisplay(String v) {
    if (v.isEmpty) return v;
    final lower = v.toLowerCase();
    if (lower.startsWith('rawhide') || lower.startsWith('nightly')) {
      return v;
    }
    return 'v$v';
  }

  /// Callback invoked before the update installer runs.
  /// Gives the host app a chance to stop child processes (e.g. KoboldCPP)
  /// because exit(0) in installNow() bypasses the window close handler.
  Future<void> Function()? _shutdownCallback;
  void setShutdownCallback(Future<void> Function() callback) {
    _shutdownCallback = callback;
  }

  /// Whether this platform supports self-update.
  /// Windows: true when installed via the Inno Setup installer (.installed marker).
  /// Linux: true when running as an AppImage ($APPIMAGE env var is set).
  static bool get isSupported {
    if (Platform.isWindows) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      return File('$exeDir\\.installed').existsSync();
    }
    if (Platform.isLinux) {
      return Platform.environment.containsKey('APPIMAGE');
    }
    if (Platform.isMacOS) {
      // Supported when running as an .app bundle (not flutter run debug).
      // Check that the executable is inside a .app/Contents/MacOS/ structure.
      final exe = Platform.resolvedExecutable;
      return exe.contains('.app/Contents/MacOS/');
    }
    return false;
  }

  /// The correct asset name for this platform's update package.
  /// Nightly (Rawhide), Beta, and Stable each use distinct filenames so the
  /// three update channels never cross-pollinate (prevents data dir disasters).
  static String get _platformAsset {
    if (Platform.isWindows) {
      if (isNightlyBuild) return _windowsAssetNightly;
      return isPreRelease ? _windowsAssetBeta : _windowsAssetStable;
    }
    if (Platform.isLinux) {
      if (isNightlyBuild) return _linuxAssetNightly;
      return _linuxAsset;
    }
    if (Platform.isMacOS) {
      // New clients use .pkg names (primary artifacts). The fallback to legacy
      // DMG names happens in checkForUpdate (see _getLegacyMacDmgAsset) so that
      // this binary (and old binaries still carrying the .dmg strings) can find
      // an asset in transition releases that publish both.
      if (isNightlyBuild) return _macosAssetNightlyPkg;
      if (isPreRelease) return _macosAssetBetaPkg;
      return _macosAssetPkg;
    }
    return '';
  }

  Future<void> initialize() async {
    // Always set version so the sidebar displays it on every platform.
    _currentVersion = appVersion;

    if (!isSupported) {
      notifyListeners();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    _autoCheckEnabled = prefs.getBool(_prefsKeyAutoCheck) ?? true;
    notifyListeners();
  }

  Future<void> setAutoCheckEnabled(bool enabled) async {
    _autoCheckEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyAutoCheck, enabled);
    notifyListeners();
  }

  /// Check GitHub Releases API for a newer version.
  /// Returns true if an update is available.
  Future<bool> checkForUpdate() async {
    if (!isSupported || _checking) return false;

    _checking = true;
    notifyListeners();

    try {
      // Use the general /releases endpoint to find both stable and pre-releases.
      // GitHub's /releases/latest endpoint ignores everything marked as pre-release.
      final response = await http.get(
        Uri.parse(
          'https://api.github.com/repos/$_repoOwner/$_repoName/releases',
        ),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode != 200) {
        debugPrint('Update check failed: ${response.statusCode}');
        return false;
      }

      final List<dynamic> allReleases = jsonDecode(response.body);
      if (allReleases.isEmpty) return false;

      final targetRelease = selectTargetRelease(allReleases, isPreRelease);
      if (targetRelease == null) return false;

      final originalTag = (targetRelease['tag_name'] as String? ?? '');
      final tagNameStripped = originalTag.replaceFirst(RegExp(r'^[vV]'), '');
      final normalizedVersion = _normalizeForCompare(tagNameStripped);
      final assets = targetRelease['assets'] as List<dynamic>? ?? [];

      // Find the platform-specific update asset (now correctly picks Nightly/Beta/Stable)
      final targetAsset = _platformAsset;
      String? installerUrl;
      String? resolvedAssetName;
      for (final asset in assets) {
        if (asset['name'] == targetAsset) {
          installerUrl = asset['browser_download_url'] as String?;
          resolvedAssetName = targetAsset;
          break;
        }
      }

      // macOS transition support (critical): prefer the new .pkg name (canonical
      // for post-switch releases), but if not present in the release's asset list
      // fall back to the exact legacy DMG name for that channel. This lets:
      // - old client binaries (still compiled against the .dmg consts) find an
      //   asset they recognize and successfully self-update;
      // - new binaries (this code) also succeed on a "shim only" or mixed release
      //   during the cutover, then after update they run the fixed logic.
      // The shim DMGs are unsigned/un-notarized on purpose (see build/CI) so
      // Gatekeeper does not interfere with the temp hdiutil attach used by the
      // legacy replace path.
      if (Platform.isMacOS && installerUrl == null) {
        final legacyDmg = _getLegacyMacDmgAsset();
        for (final asset in assets) {
          if (asset['name'] == legacyDmg) {
            installerUrl = asset['browser_download_url'] as String?;
            resolvedAssetName = legacyDmg;
            debugPrint(
              'macOS update: preferred pkg "$targetAsset" not found in $originalTag; '
              'falling back to legacy unsigned shim DMG "$legacyDmg" (smooth transition)',
            );
            break;
          }
        }
      }

      if (installerUrl == null) {
        final probed = Platform.isMacOS
            ? '$targetAsset (or legacy ${_getLegacyMacDmgAsset()})'
            : targetAsset;
        debugPrint('No update asset ($probed) found in release $originalTag');
        return false;
      }

      _latestReleaseTag = originalTag;
      _latestVersion = normalizedVersion;
      _downloadUrl = installerUrl;
      _selectedAssetName = resolvedAssetName ?? targetAsset;
      _releaseNotes = targetRelease['body'] as String? ?? '';
      // The friendly "What's New" (including the macOS .pkg+shim transition note)
      // comes from docs/<Branch>.md (e.g. docs/Rawhide.md) via the CI release_notes
      // step; it is rendered in the in-app Update Available dialog.
      _updateAvailable = _isNewerVersion(normalizedVersion, _currentVersion);

      return _updateAvailable;
    } catch (e) {
      debugPrint('Update check error: $e');
      return false;
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  /// Download the installer to a temp directory.
  /// Does NOT run it — call installNow() or let installOnClose() handle it.
  /// On macOS the downloaded filename (and thus its extension) may be the .pkg
  /// or a legacy .dmg shim depending on what the release actually contained.
  Future<void> downloadUpdate() async {
    if (!isSupported || _downloadUrl.isEmpty || _downloading) return;

    _downloading = true;
    _downloadComplete = false;
    _downloadProgress = 0.0;
    notifyListeners();

    try {
      final tempDir = Directory.systemTemp;
      // Use the resolved asset name (may be the fallback shim .dmg) so the
      // temp file has the correct extension for the later install dispatch.
      final assetName = _selectedAssetName.isNotEmpty
          ? _selectedAssetName
          : _platformAsset;
      final sep = Platform.isWindows ? '\\' : '/';
      final installerPath = '${tempDir.path}$sep$assetName';
      final file = File(installerPath);

      final request = http.Request('GET', Uri.parse(_downloadUrl));
      final response = await http.Client().send(request);

      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;
      final sink = file.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          _downloadProgress = receivedBytes / totalBytes;
          notifyListeners();
        }
      }
      await sink.close();

      _pendingInstallerPath = installerPath;
      _downloadComplete = true;
      _downloading = false;
      notifyListeners();
    } catch (e) {
      debugPrint('Download error: $e');
      _downloading = false;
      _downloadProgress = 0.0;
      notifyListeners();
    }
  }

  /// Run the update immediately and exit (or relaunch on Linux/macOS).
  Future<void> installNow() async {
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
      exit(0);
    } catch (e) {
      debugPrint('Install now failed: $e');
      rethrow;
    }
  }

  /// Run the pending update on app close.
  /// Call this from the window close handler.
  Future<void> installOnClose() async {
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

    // Delete the old AppImage first (Linux allows unlinking running executables)
    final rmResult = await Process.run('rm', ['-f', currentAppImage]);
    if (rmResult.exitCode != 0) {
      debugPrint('rm failed: ${rmResult.stderr}');
    }

    // Copy the new AppImage to the original location
    final cpResult = await Process.run('cp', [downloadedPath, currentAppImage]);
    if (cpResult.exitCode != 0) {
      debugPrint('cp failed: ${cpResult.stderr}');
      throw Exception('Failed to copy new AppImage: ${cpResult.stderr}');
    }

    // Make executable
    await Process.run('chmod', ['+x', currentAppImage]);
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

  /// Returns the legacy DMG asset name for the current channel.
  /// Used only as fallback probe during the .dmg -> .pkg transition.
  static String _getLegacyMacDmgAsset() {
    if (isNightlyBuild) return _macosAssetNightly;
    if (isPreRelease) return _macosAssetBeta;
    return _macosAsset;
  }

  /// Install the macOS update (primary .pkg path or legacy DMG shim path).
  /// Spawns a detached shell script that:
  ///   1. Waits for this process to exit (by PID)
  ///   2. For .pkg (new primary): simply `open`s the .pkg so the user gets the
  ///      standard Installer.app flow (one auth prompt, official Apple path,
  ///      signed+notarized+stapled package installs the new .app to /Applications).
  ///   3. For legacy .dmg shim (unsigned/un-notarized bridge): does the old
  ///      hdiutil attach + find *.app + rm -rf + cp -R + xattr -cr + detach +
  ///      relaunch. This path exists only to let pre-.pkg users (old .dmg drag
  ///      installs) keep using the in-app updater during the transition.
  ///      (Note: if a .pkg-installed bundle ever falls back to a shim DMG the
  ///      rm/cp may fail due to ownership in /Applications; shims primarily
  ///      serve the old .app users.)
  /// The single script + extension sniff keeps the pending-installer path
  /// unified and avoids method proliferation.
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

    final lower = installerPath.toLowerCase();
    final isPkg = lower.endsWith('.pkg');
    final kind = isPkg ? 'PKG' : 'DMG shim';

    debugPrint(
      'macOS update: will handle $kind $installerPath after PID $currentPid exits (replacing $currentApp)',
    );

    // Compute the output script filename first (it is independent).
    // Robust wait + cleanup + error to stderr (bash sidecar spirit).
    final scriptPath =
        '${Directory.systemTemp.path}/fp_update_${DateTime.now().millisecondsSinceEpoch}.sh';

    // Defense-in-depth escaping for paths embedded into the generated shell
    // script (issue #12). Pid is numeric and safe. We use single-quote + ' -> '\''
    // escaping for the three path values so that even if (theoretically) a path
    // contained a single quote, the generated bash remains correct. Current
    // values (asset names from GH, dest from resolvedExecutable walk) are
    // controlled and safe, but this satisfies the nit without changing quoting
    // style in the templates.
    String _shellEscape(String p) => p.replaceAll("'", r"'\''");
    final escInstaller = _shellEscape(installerPath);
    final escDest = _shellEscape(destPath);
    final escScript = _shellEscape(scriptPath);

    String script;
    if (isPkg) {
      script =
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
    } else {
      script =
          '''#!/bin/bash
# Wait for the current app process to exit (max 30s)
for i in {1..60}; do
  if ! kill -0 $currentPid 2>/dev/null; then
    break
  fi
  sleep 0.5
done

# Mount the DMG (legacy shim path — unsigned/un-notarized on purpose)
# NOTE (per Issue C): the legacy shim path (critical for .dmg->.pkg transition
# for old clients/pre-pkg users) relies on CI/gates/manual verification for
# generated script invariants per NEVER-create + smallest-change rules.
# Pure parts (name resolution, extension dispatch, template content) verified
# via fix-round gates/re-reads/greps (no test file created).
# All external-command path embeddings (hdiutil, rm, cp, open, etc.) now go
# through the esc* forms for defense-in-depth (see _shellEscape above).
MOUNT_OUTPUT=\$(hdiutil attach '$escInstaller' -nobrowse -noverify -mountrandom /tmp 2>&1)
if [ \$? -ne 0 ]; then
  echo "Failed to mount DMG" >&2
  exit 1
fi

# Debug the raw output (helps diagnose mount issues on CI/user machines)
echo "hdiutil attach output (for debugging shim path):" >&2
echo "\$MOUNT_OUTPUT" >&2

# Extract mount point robustly (cut -f uses tab by default; avoids any
# literal-backslash-t parsing bugs from awk -F in generated script).
# This is the critical fix for the legacy unsigned shim DMG path that allows
# pre-pkg .app users and old clients to continue seamless in-app updates.
MOUNT_POINT=\$(echo "\$MOUNT_OUTPUT" | tail -1 | cut -f 2- | xargs)

# Find the .app inside the mounted volume (top level, per our shim layout)
NEW_APP=\$(find "\$MOUNT_POINT" -maxdepth 1 -name "*.app" -type d | head -1)
if [ -z "\$NEW_APP" ] || [ ! -d "\$NEW_APP" ]; then
  hdiutil detach "\$MOUNT_POINT" -quiet 2>/dev/null || true
  echo "No .app found in DMG (mount point was: \$MOUNT_POINT)" >&2
  exit 1
fi

# Replace the old app (works for user-owned drag installs from old DMGs)
rm -rf '$escDest'
cp -R "\$NEW_APP" '$escDest'

# Strip quarantine
xattr -cr '$escDest' 2>/dev/null || true

# Unmount DMG
hdiutil detach "\$MOUNT_POINT" -quiet 2>/dev/null || true

# Clean up the DMG and this script (best effort; rm of the dmg payload happens
# after detach so the mount consumer has released it; still racy on very slow
# disks but acceptable for the legacy shim path).
rm -f '$escInstaller' || true
rm -f '$escScript' || true

# Relaunch
open -n '$escDest'
''';
    }

    await File(scriptPath).writeAsString(script);
    await Process.run('chmod', ['+x', scriptPath]);

    // Launch the script detached — it will outlive this process
    await Process.start('/bin/bash', [
      scriptPath,
    ], mode: ProcessStartMode.detached);
    debugPrint('macOS update script launched: $scriptPath');
  }

  /// Relaunch the macOS app after replacing it.
  /// (Now handled by the update script for both paths; kept for API symmetry
  /// and installOnClose fallback.)
  Future<void> _relaunchMacApp() async {
    // Relaunch (for DMG path) or user/Installer action (for PKG path) is handled
    // by the update shell script. Nothing to do here.
  }

  /// Picks the release this build's channel should be offered, out of the
  /// full GitHub `/releases` list.
  ///
  /// Two invariants, both learned from field bugs:
  ///  * **Channel isolation.** Stable and Beta/Nightly install to different
  ///    paths and data dirs, so a stable build must never be handed a
  ///    pre-release and vice-versa (`wantPrerelease` is this build's channel).
  ///  * **"Newest" cannot depend on GitHub's list order OR on the Rawhide
  ///    version string.** GitHub's `/releases` ordering is not reliably
  ///    newest-published-first, and `rawhide.YYYYMMDD.<sha>` has no orderable
  ///    field below the day — the trailing short SHA is a commit hash, not a
  ///    monotonic build counter. The old code took the FIRST channel match and
  ///    stopped, so a newer same-day manual build that GitHub listed *below* an
  ///    older release was invisible (you couldn't distinguish or rank them by
  ///    the tag, and index 0 was never revisited). We instead scan every
  ///    channel match and keep the one with the newest publish timestamp, which
  ///    is a true monotonic recency signal the version string can't provide.
  @visibleForTesting
  static Map<String, dynamic>? selectTargetRelease(
    List<dynamic> releases,
    bool wantPrerelease,
  ) {
    Map<String, dynamic>? best;
    DateTime? bestStamp;
    for (final release in releases) {
      if (release is! Map<String, dynamic>) continue;

      final tagLower = (release['tag_name'] as String? ?? '')
          .replaceFirst(RegExp(r'^[vV]'), '')
          .toLowerCase();
      final isPrerelease = release['prerelease'] as bool? ?? false;
      // Manual string check catches pre-releases whose `prerelease` flag was
      // never set. contains('rawhide') (no leading -) matches both
      // "nightly-rawhide..." tags and raw "rawhide.YYYY..." versions.
      final hasBetaString =
          tagLower.contains('beta') ||
          tagLower.contains('alpha') ||
          tagLower.contains('-rc') ||
          tagLower.contains('-dev') ||
          tagLower.contains('nightly') ||
          tagLower.contains('rawhide');
      final effectivelyBeta = isPrerelease || hasBetaString;
      if (wantPrerelease != effectivelyBeta) continue;

      // published_at is the real publication time; created_at (the tag's
      // commit date) is the fallback for the rare release with a null
      // published_at. An unparseable/missing pair sinks to the epoch so a
      // dated release always outranks it.
      final stamp =
          DateTime.tryParse(
            (release['published_at'] ?? release['created_at'] ?? '') as String,
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      if (best == null || stamp.isAfter(bestStamp!)) {
        best = release;
        bestStamp = stamp;
      }
    }
    return best;
  }

  /// Normalizes a version/tag string for comparison and display:
  /// strips leading v/V, and the "nightly-" wrapper used on GitHub tags for Rawhide
  /// so that "nightly-rawhide.20250519.abc" becomes "rawhide.20250519.abc" (matching
  /// the appVersion string baked into the binary by the nightly CI).
  String _normalizeForCompare(String v) {
    v = v.toLowerCase().replaceFirst(RegExp(r'^[vV]'), '');
    if (v.startsWith('nightly-')) {
      v = v.substring(8);
    }
    return v;
  }

  /// Compare version strings (e.g. "0.9.8-Beta6" vs "0.9.8-Beta5", or rawhide dates).
  /// Returns true if remote is newer than local.
  bool _isNewerVersion(String remote, String local) {
    final rClean = _normalizeForCompare(remote);
    final lClean = _normalizeForCompare(local);

    if (rClean == lClean) return false;

    // Special handling for Rawhide nightlies: the version format is
    // "rawhide.YYYYMMDD.SHA". We compare the date numeric first (correctly
    // orders 20250519 > 20250517), then fall back for same-day builds.
    if (rClean.startsWith('rawhide.') && lClean.startsWith('rawhide.')) {
      final rParts = rClean.split('.');
      final lParts = lClean.split('.');
      if (rParts.length >= 2 && lParts.length >= 2) {
        final rDate = int.tryParse(rParts[1]) ?? 0;
        final lDate = int.tryParse(lParts[1]) ?? 0;
        if (rDate > lDate) return true;
        if (rDate < lDate) return false;
        // Same calendar day: any distinct build from the latest published
        // release should be offered (the GH list order is authoritative).
        return true;
      }
    }

    // Standard semver path for stable / beta / etc.
    // Split at the first hyphen (e.g. "0.9.8-beta6" -> ["0.9.8", "beta6"])
    final rSplit = rClean.split('-');
    final lSplit = lClean.split('-');

    final rBase = rSplit[0]
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    final lBase = lSplit[0]
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();

    // Normalize lengths for the numeric base
    while (rBase.length < lBase.length) {
      rBase.add(0);
    }
    while (lBase.length < rBase.length) {
      lBase.add(0);
    }

    // 1. Compare numeric base parts
    for (int i = 0; i < rBase.length; i++) {
      if (rBase[i] > lBase[i]) return true;
      if (rBase[i] < lBase[i]) return false;
    }

    // 2. Base version is identical, compare suffixes (e.g. "-beta6" vs "-beta5")
    final rSuffix = rSplit.length > 1 ? rSplit[1] : '';
    final lSuffix = lSplit.length > 1 ? lSplit[1] : '';

    if (rSuffix.isEmpty && lSuffix.isNotEmpty) {
      return true; // Stable is newer than beta
    }
    if (rSuffix.isNotEmpty && lSuffix.isEmpty) {
      return false; // Beta is older than stable
    }

    // Both have suffixes, do a natural comparison
    return _compareAlphanumeric(rSuffix, lSuffix) > 0;
  }

  /// Helper for natural string comparison (handles "beta10" > "beta9")
  int _compareAlphanumeric(String a, String b) {
    final re = RegExp(r'(\d+)|(\D+)');
    final aMatches = re.allMatches(a).toList();
    final bMatches = re.allMatches(b).toList();

    for (int i = 0; i < min(aMatches.length, bMatches.length); i++) {
      final aVal = aMatches[i].group(0)!;
      final bVal = bMatches[i].group(0)!;

      final aNum = int.tryParse(aVal);
      final bNum = int.tryParse(bVal);

      if (aNum != null && bNum != null) {
        if (aNum != bNum) return aNum.compareTo(bNum);
      } else {
        if (aVal != bVal) return aVal.compareTo(bVal);
      }
    }
    return aMatches.length.compareTo(bMatches.length);
  }
}
