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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/opencode/opencode_fetch.dart';
import 'package:front_porch_ai/services/opencode/opencode_paths.dart';
import 'package:front_porch_ai/services/opencode/opencode_pin.dart';
import 'package:front_porch_ai/services/opencode/opencode_process.dart';
import 'package:front_porch_ai/services/opencode/opencode_version.dart';

/// Downloads, starts, and stops a private OpenCode the way Porch owns Kobold.
/// Never uses the Homebrew binary or `~/.config/opencode`.
class OpenCodeManager extends ChangeNotifier {
  OpenCodeManager({
    required String rootPath,
    OpenCodeDownloader? downloader,
    OpenCodeUnpack? unpack,
    OpenCodePortPick? pickPort,
    OpenCodeSpawn? spawn,
    OpenCodeHealthGet? healthGet,
    OpenCodeRemoteLookup? remoteLookup,
    this.writeConfig,
  }) : closet = OpenCodeCloset(rootPath),
       _downloader = downloader ?? openCodeHttpDownload,
       _unpack = unpack ?? openCodeUnpackZip,
       _pickPort = pickPort ?? openCodePickFreePort,
       _spawn = spawn ?? openCodeSpawnProcess,
       _healthGet = healthGet ?? openCodeGetHealth,
       _remoteLookup = remoteLookup ?? openCodePinnedLookup {
    if (rootPath.isNotEmpty) unawaited(refreshInstalled());
  }

  final OpenCodeCloset closet;
  final OpenCodeDownloader _downloader;
  final OpenCodeUnpack _unpack;
  final OpenCodePortPick _pickPort;
  final OpenCodeSpawn _spawn;
  final OpenCodeHealthGet _healthGet;
  final OpenCodeRemoteLookup _remoteLookup;
  final Future<void> Function(OpenCodeCloset closet)? writeConfig;

  bool _isDownloading = false;
  double _downloadProgress = 0;
  String _statusMessage = '';
  String? _error;
  bool _isRunning = false;
  Uri? _baseUri;
  OpenCodeProcessHandle? _handle;
  String? _workDir;
  String? _installedVersion;
  String? _remoteVersion;
  int? _remoteAssetBytes;
  bool _isCheckingVersion = false;
  String? _versionError;

  bool get isDownloading => _isDownloading;
  double get downloadProgress => _downloadProgress;
  String get statusMessage => _statusMessage;
  String? get error => _error;
  bool get isRunning => _isRunning;
  String? get installedVersion => _installedVersion;
  String? get remoteVersion => _remoteVersion;
  bool get isCheckingVersion => _isCheckingVersion;
  String? get versionError => _versionError;

  /// Same rule as managed Kobold: missing counts as an update; unknown
  /// remote does not. Zip size is not compared (GitHub asset is an archive).
  bool get isUpdateAvailable {
    if (_installedVersion == null) return true;
    if (_remoteVersion == null) return false;
    return _installedVersion != _remoteVersion;
  }

  int get downloadMegabytes {
    final b = _remoteAssetBytes;
    if (b != null && b > 0) {
      return (b / (1024 * 1024)).round().clamp(1, 999);
    }
    return kOpenCodeDownloadMegabytes;
  }

  Uri get baseUri =>
      _baseUri ?? (throw StateError('OpenCode serve is not running'));
  int? get pid => _handle?.pid;

  Future<bool> get isInstalled async => File(closet.binaryPath).exists();

  /// First-use grab. If a binary is already in the closet, leave it — upgrades
  /// are a tap, same as Kobold's ensureEngineInstalled.
  Future<void> ensureInstalled({void Function(double p)? onProgress}) async {
    await closet.ensureLayout();
    if (openCodeLooksLikeBrewPath(closet.binaryPath)) {
      throw StateError('OpenCode closet resolved to a brew path');
    }
    if (await isInstalled) {
      await refreshInstalled();
      return;
    }
    await _installLatest(onProgress: onProgress);
  }

  Future<void> refreshInstalled() async {
    final v = await OpenCodeBinaryVersion.read(closet.binDir);
    _installedVersion = v.version;
    notifyListeners();
  }

  /// Automatic GitHub check — same pref as the app updater and Kobold
  /// (`update_auto_check`). Manual [checkRemoteVersion] / [upgrade] stay
  /// unconditional so a tap still works when auto-check is off. A session
  /// that already has [_remoteVersion] keeps it; this does not wipe cache.
  Future<void> maybeAutoCheckRemoteVersion() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('update_auto_check') ?? true)) return;
    await checkRemoteVersion();
  }

  /// Looks up the version to install (the pinned release unless a test
  /// injects a lookup). Never downloads it.
  Future<void> checkRemoteVersion() async {
    if (_isCheckingVersion) return;
    _isCheckingVersion = true;
    _versionError = null;
    notifyListeners();
    try {
      final hit = await _remoteLookup();
      if (hit == null) {
        _versionError = 'Could not check GitHub';
      } else {
        _remoteVersion = hit.tag;
        _remoteAssetBytes = hit.assetBytes;
      }
    } catch (e) {
      debugPrint('[OpenCode] version check failed: $e');
      _versionError = 'Could not check GitHub';
    } finally {
      _isCheckingVersion = false;
      notifyListeners();
    }
  }

  /// Tap-to-swap: stop our PID if running, then install the pinned release.
  /// Never Homebrew, never `~/.config/opencode`, never auto-download on launch.
  Future<void> upgrade({void Function(double p)? onProgress}) async {
    if (_isRunning) await stop();
    await _installLatest(onProgress: onProgress);
  }

  Future<void> _installLatest({void Function(double p)? onProgress}) async {
    if (_isDownloading) return;
    await closet.ensureLayout();
    if (openCodeLooksLikeBrewPath(closet.binaryPath)) {
      throw StateError('OpenCode closet resolved to a brew path');
    }
    if (_remoteVersion == null) await checkRemoteVersion();
    final tag = _remoteVersion;
    _isDownloading = true;
    _downloadProgress = 0;
    _statusMessage = tag == null || tag.isEmpty
        ? 'Downloading OpenCode…'
        : 'Downloading OpenCode $tag…';
    _error = null;
    notifyListeners();
    try {
      final bytes = await _downloader(
        openCodeReleaseDownloadUri(tag),
        onProgress: (received, total) {
          if (total != null && total > 0) {
            _downloadProgress = received / total;
            onProgress?.call(_downloadProgress);
            notifyListeners();
          }
        },
      );
      openCodeVerifyDownload(version: tag, bytes: bytes);
      final unpack = Directory(closet.unpackDir);
      if (await unpack.exists()) {
        await unpack.delete(recursive: true);
      }
      await unpack.create(recursive: true);
      final unpacked = await _unpack(bytes, unpack);
      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', unpacked.path]);
      }
      final live = File(closet.binaryPath);
      if (unpacked.path != live.path) {
        if (await live.exists()) await live.delete();
        await unpacked.copy(live.path);
        if (!Platform.isWindows) {
          await Process.run('chmod', ['+x', live.path]);
        }
      }
      final size = await File(closet.binaryPath).length();
      if (tag != null && tag.isNotEmpty) {
        await OpenCodeBinaryVersion.write(
          closet.binDir,
          version: tag,
          size: size,
        );
        _installedVersion = tag;
      } else {
        await refreshInstalled();
      }
      try {
        await unpack.delete(recursive: true);
      } on FileSystemException catch (e) {
        debugPrint('[OpenCode] could not remove ${unpack.path}: $e');
      }
      _downloadProgress = 1;
      _statusMessage = tag == null || tag.isEmpty
          ? 'OpenCode ready'
          : 'OpenCode $tag ready';
    } catch (e) {
      _error = '$e';
      _statusMessage = 'OpenCode download failed';
      rethrow;
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
  }

  Future<void> start({String? workingDirectory}) async {
    final cwd = workingDirectory ?? closet.binDir;
    if (_isRunning && _baseUri != null) {
      final health = await _healthGet(_baseUri!);
      if (health.healthy && _workDir == cwd) return;
      await stop();
    }
    await ensureInstalled();
    await closet.ensureLayout();
    if (writeConfig != null) {
      await writeConfig!(closet);
    } else {
      await _writeStubConfig();
    }
    final port = await _pickPort();
    final logFile = File(closet.serveLogPath);
    await logFile.parent.create(recursive: true);
    await logFile.writeAsBytes(const []);
    final req = OpenCodeSpawnRequest(
      executable: closet.binaryPath,
      arguments: openCodeServeArgs(port),
      environment: openCodeIsolatedEnvironment(closet, pwd: cwd),
      workingDirectory: cwd,
      logPath: logFile.path,
    );
    if (openCodeLooksLikeBrewPath(req.executable)) {
      throw StateError('Refusing to spawn a brew OpenCode');
    }
    final handle = _handle = await _spawn(req);
    if (handle.tracksExit) {
      unawaited(handle.exitCode.then((code) => _onExit(handle, code)));
    }
    _baseUri = Uri(scheme: 'http', host: '127.0.0.1', port: port);
    final ok = await _waitHealthy(_baseUri!);
    if (!ok) {
      await stop();
      throw StateError('OpenCode serve did not become healthy');
    }
    _workDir = cwd;
    _isRunning = true;
    _statusMessage = 'OpenCode listening on 127.0.0.1:$port';
    notifyListeners();
  }

  /// A serve that dies on its own must not still read as running.
  void _onExit(OpenCodeProcessHandle handle, int code) {
    if (!identical(_handle, handle)) return;
    _handle = null;
    _isRunning = false;
    _baseUri = null;
    _statusMessage = 'OpenCode exited (code $code)';
    notifyListeners();
  }

  Future<void> stop() async {
    final handle = _handle;
    _handle = null;
    _isRunning = false;
    _baseUri = null;
    _workDir = null;
    if (handle != null) {
      handle.kill(ProcessSignal.sigterm);
      try {
        await handle.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        handle.kill(ProcessSignal.sigkill);
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    // Best-effort; callers also stop on app quit.
    final handle = _handle;
    _handle = null;
    handle?.kill(ProcessSignal.sigterm);
    super.dispose();
  }

  /// Refused connections are expected while the serve boots; only the
  /// last error is worth logging.
  Future<bool> _waitHealthy(Uri base) async {
    Object? last;
    for (var i = 0; i < 40; i++) {
      try {
        final h = await _healthGet(base);
        if (h.healthy) return true;
      } catch (e) {
        last = e;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    debugPrint('[OpenCode] serve never became healthy at $base: $last');
    return false;
  }

  Future<void> _writeStubConfig() async {
    final file = File(closet.configFilePath);
    if (await file.exists()) return;
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        '\$schema': 'https://opencode.ai/config.json',
        'autoupdate': false,
        'share': 'disabled',
        'plugin': <String>[],
        'default_agent': 'waifu',
      }),
    );
  }
}
