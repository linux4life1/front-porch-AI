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

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/opencode/opencode_paths.dart';
import 'package:front_porch_ai/services/opencode/opencode_pin.dart';
import 'package:front_porch_ai/services/opencode/opencode_process.dart';
import 'package:front_porch_ai/services/opencode/opencode_version.dart';

typedef OpenCodeDownloader =
    Future<List<int>> Function(
      Uri url, {
      void Function(int received, int? total)? onProgress,
    });

typedef OpenCodeUnpack = Future<File> Function(List<int> bytes, Directory dest);

typedef OpenCodePortPick = Future<int> Function();

typedef OpenCodeHealthGet =
    Future<({bool healthy, String version})> Function(Uri base);

typedef OpenCodeRemoteLookup =
    Future<({String tag, int? assetBytes})?> Function();

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
       _remoteLookup = remoteLookup ?? openCodeFetchRemoteLatest;

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
  String get pinnedVersion => kOpenCodePinnedVersion;
  String? get remoteVersion => _remoteVersion;
  bool get isCheckingVersion => _isCheckingVersion;
  String? get versionError => _versionError;
  bool get needsPinDownload => _installedVersion != kOpenCodePinnedVersion;
  int get pinDownloadMegabytes {
    final b = _remoteAssetBytes;
    if (b != null && b > 0) {
      return (b / (1024 * 1024)).round().clamp(1, 999);
    }
    return kOpenCodePinMegabytes;
  }

  Uri get baseUri =>
      _baseUri ?? (throw StateError('OpenCode serve is not running'));
  int? get pid => _handle?.pid;

  Future<bool> get isPinnedInstalled async {
    if (!await File(closet.binaryPath).exists()) return false;
    final v = await OpenCodeBinaryVersion.read(closet.binDir);
    return v.version == kOpenCodePinnedVersion;
  }

  Future<void> ensureInstalled({void Function(double p)? onProgress}) async {
    await closet.ensureLayout();
    if (openCodeLooksLikeBrewPath(closet.binaryPath)) {
      throw StateError('OpenCode closet resolved to a brew path');
    }
    if (await isPinnedInstalled) {
      _installedVersion = kOpenCodePinnedVersion;
      notifyListeners();
      return;
    }

    _isDownloading = true;
    _downloadProgress = 0;
    _statusMessage = 'Downloading OpenCode $kOpenCodePinnedVersion…';
    _error = null;
    notifyListeners();
    try {
      final bytes = await _downloader(
        openCodePinnedDownloadUri(),
        onProgress: (received, total) {
          if (total != null && total > 0) {
            _downloadProgress = received / total;
            onProgress?.call(_downloadProgress);
            notifyListeners();
          }
        },
      );
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
      await OpenCodeBinaryVersion.write(
        closet.binDir,
        version: kOpenCodePinnedVersion,
        size: await File(closet.binaryPath).length(),
      );
      try {
        await unpack.delete(recursive: true);
      } catch (_) {}
      _installedVersion = kOpenCodePinnedVersion;
      _downloadProgress = 1;
      _statusMessage = 'OpenCode $kOpenCodePinnedVersion ready';
    } catch (e) {
      _error = '$e';
      _statusMessage = 'OpenCode download failed';
      rethrow;
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
  }

  Future<void> refreshInstalled() async {
    final v = await OpenCodeBinaryVersion.read(closet.binDir);
    _installedVersion = v.version;
    notifyListeners();
  }

  /// Looks up GitHub latest for honesty only. Never downloads it.
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
    } catch (_) {
      _versionError = 'Could not check GitHub';
    } finally {
      _isCheckingVersion = false;
      notifyListeners();
    }
  }

  /// Tap-to-swap: stop our PID if running, then install the pin. Never
  /// Homebrew, never `~/.config/opencode`, never auto-latest.
  Future<void> upgradeToPin({void Function(double p)? onProgress}) async {
    if (_isRunning) await stop();
    await ensureInstalled(onProgress: onProgress);
  }

  Future<void> start({String? workingDirectory}) async {
    if (_isRunning && _baseUri != null) {
      final health = await _healthGet(_baseUri!);
      if (health.healthy) return;
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
    final req = OpenCodeSpawnRequest(
      executable: closet.binaryPath,
      arguments: openCodeServeArgs(port),
      environment: openCodeIsolatedEnvironment(closet),
      workingDirectory: workingDirectory ?? closet.binDir,
    );
    if (openCodeLooksLikeBrewPath(req.executable)) {
      throw StateError('Refusing to spawn a brew OpenCode');
    }
    _handle = await _spawn(req);
    _baseUri = Uri(scheme: 'http', host: '127.0.0.1', port: port);
    final ok = await _waitHealthy(_baseUri!);
    if (!ok) {
      await stop();
      throw StateError('OpenCode serve did not become healthy');
    }
    _isRunning = true;
    _statusMessage = 'OpenCode listening on 127.0.0.1:$port';
    notifyListeners();
  }

  Future<void> stop() async {
    final handle = _handle;
    _handle = null;
    _isRunning = false;
    _baseUri = null;
    if (handle != null) {
      handle.kill(ProcessSignal.sigterm);
      try {
        await handle.exitCode.timeout(const Duration(seconds: 2));
      } catch (_) {
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

  Future<bool> _waitHealthy(Uri base) async {
    for (var i = 0; i < 40; i++) {
      try {
        final h = await _healthGet(base);
        if (h.healthy) return true;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
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

Future<List<int>> openCodeHttpDownload(
  Uri url, {
  void Function(int received, int? total)? onProgress,
}) async {
  final client = http.Client();
  try {
    final request = http.Request('GET', url);
    final response = await client.send(request);
    if (response.statusCode != 200) {
      throw Exception('OpenCode download failed: HTTP ${response.statusCode}');
    }
    final chunks = <int>[];
    var received = 0;
    await for (final chunk in response.stream) {
      chunks.addAll(chunk);
      received += chunk.length;
      onProgress?.call(received, response.contentLength);
    }
    return chunks;
  } finally {
    client.close();
  }
}

Future<File> openCodeUnpackZip(List<int> bytes, Directory dest) async {
  await dest.create(recursive: true);
  final zip = File('${dest.path}.zip');
  await zip.writeAsBytes(bytes, flush: true);
  try {
    if (Platform.isWindows) {
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Expand-Archive -Force -Path "${zip.path}" '
            '-DestinationPath "${dest.path}"',
      ]);
      if (r.exitCode != 0) {
        throw Exception('Unpack failed: ${r.stderr}');
      }
    } else {
      final r = await Process.run('unzip', ['-o', zip.path, '-d', dest.path]);
      if (r.exitCode != 0) {
        throw Exception('Unpack failed: ${r.stderr}');
      }
    }
    return openCodeFindUnpackedBinary(dest);
  } finally {
    try {
      await zip.delete();
    } catch (_) {}
  }
}

File openCodeFindUnpackedBinary(Directory dest) {
  final want = Platform.isWindows ? 'opencode.exe' : 'opencode';
  final direct = File(p.join(dest.path, want));
  if (direct.existsSync()) return direct;
  for (final entity in dest.listSync(recursive: true, followLinks: false)) {
    if (entity is File && p.basename(entity.path) == want) {
      return entity;
    }
  }
  throw Exception('OpenCode zip did not contain $want');
}

Future<int> openCodePickFreePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<({String tag, int? assetBytes})?> openCodeFetchRemoteLatest() async {
  final client = http.Client();
  try {
    final resp = await client
        .get(
          Uri.parse(kOpenCodeGitHubLatestUrl),
          headers: {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'FrontPorchAI',
          },
        )
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return null;
    final json = jsonDecode(resp.body);
    if (json is! Map) return null;
    final tag =
        (json['tag_name'] as String?)?.replaceFirst(RegExp(r'^[vV]'), '') ?? '';
    if (tag.isEmpty) return null;
    int? size;
    final want = openCodeReleaseAssetName(
      os: openCodeCurrentOs(),
      arch: openCodeCurrentArch(),
    );
    for (final a in json['assets'] as List? ?? []) {
      if (a is Map && a['name'] == want) {
        size = a['size'] as int?;
        break;
      }
    }
    return (tag: tag, assetBytes: size);
  } finally {
    client.close();
  }
}

Future<({bool healthy, String version})> openCodeGetHealth(Uri base) async {
  final uri = base.replace(path: '/global/health');
  final resp = await http.get(uri).timeout(const Duration(seconds: 2));
  if (resp.statusCode != 200) {
    return (healthy: false, version: '');
  }
  final json = jsonDecode(resp.body);
  if (json is! Map) return (healthy: false, version: '');
  return (
    healthy: json['healthy'] == true,
    version: (json['version'] as String?) ?? '',
  );
}
