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
/// Supports Windows (Inno Setup), Linux (AppImage), and macOS (DMG).
class UpdateService extends ChangeNotifier {
  static const String _repoOwner = 'linux4life1';
  static const String _repoName = 'front-porch-AI';
  static const String _windowsAssetStable = 'Front_Porch_AI_Setup.exe';
  static const String _windowsAssetBeta = 'Front_Porch_AI_Beta_Setup.exe';
  static const String _linuxAsset = 'Front_Porch_AI-Linux.AppImage';
  static const String _macosAsset = 'Front_Porch_AI.dmg';
  static const String _prefsKeyAutoCheck = 'update_auto_check';

  String _currentVersion = '';
  String _latestVersion = '';
  String _downloadUrl = '';
  String _releaseNotes = '';
  bool _updateAvailable = false;
  bool _checking = false;
  bool _downloading = false;
  bool _downloadComplete = false;
  double _downloadProgress = 0.0;
  bool _autoCheckEnabled = true;
  String? _pendingInstallerPath;

  String get currentVersion => _currentVersion;
  String get latestVersion => _latestVersion;
  String get releaseNotes => _releaseNotes;
  bool get updateAvailable => _updateAvailable;
  bool get checking => _checking;
  bool get downloading => _downloading;
  bool get downloadComplete => _downloadComplete;
  double get downloadProgress => _downloadProgress;
  bool get autoCheckEnabled => _autoCheckEnabled;
  bool get hasPendingInstaller => _pendingInstallerPath != null;

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
  /// Beta builds use a different asset filename so the stable and beta
  /// update streams are completely independent.
  static String get _platformAsset {
    if (Platform.isWindows) {
      return isPreRelease ? _windowsAssetBeta : _windowsAssetStable;
    }
    if (Platform.isLinux) return _linuxAsset;
    if (Platform.isMacOS) return _macosAsset;
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
        Uri.parse('https://api.github.com/repos/$_repoOwner/$_repoName/releases'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode != 200) {
        debugPrint('Update check failed: ${response.statusCode}');
        return false;
      }

      final List<dynamic> allReleases = jsonDecode(response.body);
      if (allReleases.isEmpty) return false;

      Map<String, dynamic>? targetRelease;

      for (final release in allReleases) {
        final tagName = (release['tag_name'] as String? ?? '').replaceFirst(RegExp(r'^[vV]'), '');
        final isPrerelease = release['prerelease'] as bool? ?? false;
        final tagLower = tagName.toLowerCase();
        
        // Manual check for beta strings if the flag isn't set
        final hasBetaString = tagLower.contains('beta') ||
            tagLower.contains('alpha') ||
            tagLower.contains('-rc') ||
            tagLower.contains('-dev');
        
        final effectivelyBeta = isPrerelease || hasBetaString;

        // Channel matching logic:
        // We enforce strict isolation because Stable and Beta use different
        // installation paths and database folders. Cross-updating would 
        // lead to data loss or duplicate "ghost" installations.
        if (isPreRelease != effectivelyBeta) {
          continue; 
        }

        // We found our candidate (the list is sorted by date by default)
        targetRelease = release;
        break;
      }

      if (targetRelease == null) return false;

      final tagName = (targetRelease['tag_name'] as String? ?? '').replaceFirst(RegExp(r'^[vV]'), '');
      final assets = targetRelease['assets'] as List<dynamic>? ?? [];

      // Find the platform-specific update asset
      final targetAsset = _platformAsset;
      String? installerUrl;
      for (final asset in assets) {
        if (asset['name'] == targetAsset) {
          installerUrl = asset['browser_download_url'] as String?;
          break;
        }
      }

      if (installerUrl == null) {
        debugPrint('No update asset ($targetAsset) found in release $tagName');
        return false;
      }

      _latestVersion = tagName;
      _downloadUrl = installerUrl;
      _releaseNotes = targetRelease['body'] as String? ?? '';
      _updateAvailable = _isNewerVersion(tagName, _currentVersion);

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
  Future<void> downloadUpdate() async {
    if (!isSupported || _downloadUrl.isEmpty || _downloading) return;

    _downloading = true;
    _downloadComplete = false;
    _downloadProgress = 0.0;
    notifyListeners();

    try {
      final tempDir = Directory.systemTemp;
      final assetName = _platformAsset;
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
    await Process.start(path, [
      silentFlag,
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
    await Process.start(
      currentAppImage, [],
      mode: ProcessStartMode.detached,
    );
  }

  /// Get the current .app bundle path from the resolved executable.
  /// e.g. /Applications/FrontPorchAI.app/Contents/MacOS/front_porch_ai
  ///   → /Applications/FrontPorchAI.app
  String get _currentMacAppPath {
    final exe = Platform.resolvedExecutable;
    // Walk up from MacOS/binary → Contents → .app
    return File(exe).parent.parent.parent.path;
  }

  /// Replace the current .app bundle with the one inside the downloaded DMG.
  /// Spawns a detached shell script that:
  ///   1. Waits for this process to exit
  ///   2. Mounts the DMG
  ///   3. Replaces the .app bundle
  ///   4. Strips quarantine
  ///   5. Unmounts the DMG
  ///   6. Relaunches the app
  Future<void> _replaceMacApp(String dmgPath) async {
    final currentApp = _currentMacAppPath;
    final appParent = File(currentApp).parent.path;
    final appName = currentApp.split('/').last;
    final destPath = '$appParent/$appName';
    final currentPid = pid; // Current process PID (dart:io top-level getter)

    debugPrint('macOS update: will replace $currentApp from $dmgPath after PID $currentPid exits');

    // Write a shell script that performs the replacement after we exit
    final scriptPath = '${Directory.systemTemp.path}/fp_update_${DateTime.now().millisecondsSinceEpoch}.sh';
    final script = '''#!/bin/bash
# Wait for the current app process to exit (max 30s)
for i in {1..60}; do
  if ! kill -0 $currentPid 2>/dev/null; then
    break
  fi
  sleep 0.5
done

# Mount the DMG
MOUNT_OUTPUT=\$(hdiutil attach "$dmgPath" -nobrowse -noverify -mountrandom /tmp 2>&1)
if [ \$? -ne 0 ]; then
  echo "Failed to mount DMG" >&2
  exit 1
fi

# Extract mount point (last field of last line, tab-delimited)
MOUNT_POINT=\$(echo "\$MOUNT_OUTPUT" | tail -1 | awk -F'\\t' '{print \$NF}' | xargs)

# Find the .app inside the mounted volume
NEW_APP=\$(find "\$MOUNT_POINT" -maxdepth 1 -name "*.app" -type d | head -1)
if [ -z "\$NEW_APP" ]; then
  hdiutil detach "\$MOUNT_POINT" -quiet 2>/dev/null
  echo "No .app found in DMG" >&2
  exit 1
fi

# Replace the old app
rm -rf "$destPath"
cp -R "\$NEW_APP" "$destPath"

# Strip quarantine
xattr -cr "$destPath" 2>/dev/null

# Unmount DMG
hdiutil detach "\$MOUNT_POINT" -quiet 2>/dev/null

# Clean up the DMG and this script
rm -f "$dmgPath"
rm -f "$scriptPath"

# Relaunch
open -n "$destPath"
''';

    await File(scriptPath).writeAsString(script);
    await Process.run('chmod', ['+x', scriptPath]);

    // Launch the script detached — it will outlive this process
    await Process.start(
      '/bin/bash', [scriptPath],
      mode: ProcessStartMode.detached,
    );
    debugPrint('macOS update script launched: $scriptPath');
  }

  /// Relaunch the macOS app after replacing it.
  /// (Now handled by the update script, but kept for installOnClose fallback)
  Future<void> _relaunchMacApp() async {
    // Relaunch is handled by the update shell script
  }

  /// Compare version strings (e.g. "0.9.8-Beta6" vs "0.9.8-Beta5")
  /// Returns true if remote is newer than local.
  bool _isNewerVersion(String remote, String local) {
    // Standardize: remove 'v' prefix and split into numeric vs suffix parts
    String clean(String v) => v.toLowerCase().replaceFirst(RegExp(r'^[vV]'), '');
    final rClean = clean(remote);
    final lClean = clean(local);

    if (rClean == lClean) return false;

    // Split at the first hyphen (e.g. "0.9.8-beta6" -> ["0.9.8", "beta6"])
    final rSplit = rClean.split('-');
    final lSplit = lClean.split('-');

    final rBase = rSplit[0].split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final lBase = lSplit[0].split('.').map((e) => int.tryParse(e) ?? 0).toList();

    // Normalize lengths for the numeric base
    while (rBase.length < lBase.length) rBase.add(0);
    while (lBase.length < rBase.length) lBase.add(0);

    // 1. Compare numeric base parts
    for (int i = 0; i < rBase.length; i++) {
      if (rBase[i] > lBase[i]) return true;
      if (rBase[i] < lBase[i]) return false;
    }

    // 2. Base version is identical, compare suffixes (e.g. "-beta6" vs "-beta5")
    final rSuffix = rSplit.length > 1 ? rSplit[1] : '';
    final lSuffix = lSplit.length > 1 ? lSplit[1] : '';

    if (rSuffix.isEmpty && lSuffix.isNotEmpty) return true; // Stable is newer than beta
    if (rSuffix.isNotEmpty && lSuffix.isEmpty) return false; // Beta is older than stable

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
