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
import 'package:path/path.dart' as path;
import 'package:front_porch_ai/services/kobold_binary_version.dart';
import 'package:front_porch_ai/services/storage_service.dart';

class BackendManager extends ChangeNotifier {
  final StorageService _storageService;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String? _backendPath;
  String? _error;

  String _statusMessage = '';
  String? _localVersion;
  int? _localSize;
  String? _remoteVersion;
  int? _remoteAssetSize;
  bool _isCheckingVersion = false;
  String? _versionError;
  String _arch = 'x64';
  bool _useRocm = false;
  bool _hasCuda = false;

  bool get useRocm => _useRocm;

  bool get isDownloading => _isDownloading;
  double get downloadProgress => _downloadProgress;
  String? get backendPath => _backendPath;
  String? get error => _error;
  String get statusMessage => _statusMessage;
  String? get localVersion => _localVersion;
  int? get localSize => _localSize;
  String? get remoteVersion => _remoteVersion;
  int? get remoteAssetSize => _remoteAssetSize;
  bool get isCheckingVersion => _isCheckingVersion;
  String? get versionError => _versionError;

  bool get isUpdateAvailable {
    if (_localVersion == null) return true;
    if (_remoteVersion == null) return false;
    if (_localVersion != _remoteVersion) return true;
    if (_remoteAssetSize != null &&
        _localSize != null &&
        _localSize != _remoteAssetSize) {
      return true;
    }
    return false;
  }

  String get localVersionDisplay {
    if (_localVersion == null) return '';
    if (_localSize == null) return 'v$_localVersion';
    return 'v$_localVersion, ${_formatFileSize(_localSize!)}';
  }

  bool get isIntelMac => Platform.isMacOS && _arch != 'arm64';

  BackendManager(this._storageService) {
    _init();
    _storageService.addListener(_init); // React to path changes
  }

  @override // IMPORTANT
  void dispose() {
    _storageService.removeListener(_init);
    super.dispose();
  }

  Future<void> _init() async {
    if (Platform.isMacOS) {
      try {
        final result = await Process.run('uname', ['-m']);
        if (result.exitCode == 0 &&
            result.stdout.toString().trim() == 'arm64') {
          _arch = 'arm64';
        }
      } catch (_) {}
    }
    // Detect GPU acceleration availability on Linux
    if (Platform.isLinux) {
      // Check for NVIDIA/CUDA
      try {
        final cudaRes = await Process.run('nvidia-smi', []);
        _hasCuda = cudaRes.exitCode == 0;
        print('AG_DEBUG: CUDA detected: $_hasCuda');
      } catch (_) {
        _hasCuda = false;
        print('AG_DEBUG: CUDA not found (nvidia-smi not available)');
      }
      // Check for AMD/ROCm — user preference overrides auto-detection
      final userRocmPref = _storageService.backendSettings.useRocm;
      if (userRocmPref != null) {
        _useRocm = userRocmPref;
        print('AG_DEBUG: ROCm set by user preference: $_useRocm');
      } else {
        try {
          final res = await Process.run('rocminfo', []);
          _useRocm = res.exitCode == 0;
          print('AG_DEBUG: ROCm auto-detected: $_useRocm');
        } catch (_) {
          _useRocm = false;
          print('AG_DEBUG: ROCm not found (rocminfo not available)');
        }
      }
    }
    await checkBackendAvailability();
    if (_storageService.rootPath != null) {
      final v = await KoboldBinaryVersion.read(_storageService.binDir.path);
      _localVersion = v.version;
      _localSize = v.size;
    }
    checkForUpdates();
  }

  Future<void> checkBackendAvailability() async {
    if (_storageService.rootPath == null) return;

    final binDir = _storageService.binDir;
    final executableName = _getExecutableName();
    final file = File(path.join(binDir.path, executableName));

    // Also check for other variants (user may have switched GPU acceleration)
    final altNames = <String>[];
    if (Platform.isLinux) {
      for (final name in [
        'koboldcpp-linux-x64',
        'koboldcpp-linux-x64-rocm',
        'koboldcpp-linux-x64-nocuda',
      ]) {
        if (name != executableName) altNames.add(name);
      }
    }

    File? foundFile;
    if (await file.exists()) {
      foundFile = file;
    } else {
      for (final altName in altNames) {
        final altFile = File(path.join(binDir.path, altName));
        if (await altFile.exists()) {
          foundFile = altFile;
          break;
        }
      }
    }

    if (foundFile != null) {
      _backendPath = foundFile.path;
      _statusMessage = 'Ready';
      final v = await KoboldBinaryVersion.read(_storageService.binDir.path);
      _localVersion = v.version;
      _localSize = v.size;
      // On Linux/Mac, ensure executable permission
      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', _backendPath!]);
      }
      // On macOS, clear quarantine attribute that sandbox sets on downloaded binaries
      if (Platform.isMacOS) {
        await Process.run('xattr', ['-cr', _backendPath!]);
        print('AG_DEBUG: Cleared quarantine on $_backendPath');
      }
    } else {
      _backendPath = null;
      _statusMessage = 'Not Installed';
    }
    notifyListeners();
  }

  Future<void> checkForUpdates() async {
    if (_isCheckingVersion) return;
    _isCheckingVersion = true;
    _versionError = null;
    notifyListeners();
    try {
      final client = http.Client();
      try {
        final response = await client
            .get(Uri.parse(
                'https://api.github.com/repos/LostRuins/koboldcpp/releases/latest'))
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final body = jsonDecode(response.body);
          final tag = (body['tag_name'] as String?) ?? '';
          _remoteVersion = tag.replaceFirst(RegExp(r'^[vV]'), '');
          final exeName = _getExecutableName();
          for (final a in (body['assets'] as List?) ?? []) {
            if (a['name'] == exeName) {
              _remoteAssetSize = a['size'] as int?;
              break;
            }
          }
        } else {
          _versionError = 'GitHub API: HTTP ${response.statusCode}';
        }
      } finally {
        client.close();
      }
    } catch (_) {
      _versionError = 'Could not check for updates';
    } finally {
      _isCheckingVersion = false;
      notifyListeners();
    }
  }

  Future<void> downloadBackend() async {
    if (_isDownloading) return;
    if (_storageService.rootPath == null) return;

    // Intel Macs cannot run KoboldCpp (no Metal GPU acceleration)
    if (isIntelMac) {
      _error =
          'Local inference is not supported on Intel Macs. Please use Remote API mode.';
      _statusMessage = 'Unsupported';
      notifyListeners();
      return;
    }

    _isDownloading = true;
    _error = null;
    _downloadProgress = 0.0;
    _statusMessage = 'Initializing download...';
    notifyListeners();

    // Ensure we have remote version info for accurate version file
    if (_remoteVersion == null) await checkForUpdates();

    try {
      print('AG_DEBUG: Starting download process...');
      final binDir = _storageService.binDir;
      if (!await binDir.exists()) {
        print('AG_DEBUG: Creating directory ${binDir.path}');
        await binDir.create(recursive: true);
      }

      final executableName = _getExecutableName();
      final downloadUrl = _getDownloadUrl();
      final savePath = path.join(binDir.path, executableName);
      print('AG_DEBUG: Download target: $savePath');
      print('AG_DEBUG: Download URL: $downloadUrl');

      _statusMessage = 'Connecting to GitHub...';
      notifyListeners();

      // Use a fresh client
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(downloadUrl));

      print('AG_DEBUG: Sending request...');
      final response = await client.send(request);
      print('AG_DEBUG: Response received. Status: ${response.statusCode}');

      if (response.statusCode != 200) {
        print('AG_DEBUG: Download failed with status ${response.statusCode}');
        throw Exception(
          'Failed to download backend: HTTP ${response.statusCode}',
        );
      }

      final contentLength = response.contentLength ?? 0;
      print('AG_DEBUG: Content length: $contentLength');

      int received = 0;
      final file = File(savePath);
      final sink = file.openWrite();

      _statusMessage = 'Downloading...';
      notifyListeners();

      DateTime startTime = DateTime.now();
      DateTime lastUpdateTime = startTime;
      int lastWebBytes = 0;

      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;

          final now = DateTime.now();
          if (now.difference(lastUpdateTime).inMilliseconds >= 500) {
            final timeDiff =
                now.difference(lastUpdateTime).inMilliseconds / 1000.0;
            final bytesDiff = received - lastWebBytes;
            final speed = bytesDiff / timeDiff; // bytes per second

            String speedStr = _formatSpeed(speed);
            String etaStr = '';

            if (contentLength > 0 && speed > 0) {
              final remainingBytes = contentLength - received;
              final remainingSeconds = remainingBytes / speed;
              etaStr =
                  ' - ETA: ${_formatDuration(Duration(seconds: remainingSeconds.round()))}';
            }

            if (contentLength > 0) {
              _downloadProgress = received / contentLength;
              _statusMessage =
                  'Downloading: ${(_downloadProgress * 100).toStringAsFixed(1)}% ($speedStr)$etaStr';
            } else {
              _statusMessage =
                  'Downloading: ${(received / 1024 / 1024).toStringAsFixed(1)} MB ($speedStr)';
            }

            notifyListeners();
            lastUpdateTime = now;
            lastWebBytes = received;
          }
        }
        print('AG_DEBUG: Stream verified complete. Received: $received bytes.');
      } catch (e) {
        print('AG_DEBUG: Stream error: $e');
        // Clean up partial download on error
        try {
          await file.delete();
        } catch (_) {}
        rethrow;
      } finally {
        print('AG_DEBUG: Closing file sink...');
        await sink.flush();
        await sink.close();
        client.close();
        print('AG_DEBUG: File sink closed.');
      }

      // Verify download integrity
      if (contentLength > 0 && received < contentLength) {
        print(
          'AG_DEBUG: Download incomplete! Expected $contentLength bytes but received $received bytes.',
        );
        try {
          await file.delete();
        } catch (_) {}
        throw Exception(
          'Download incomplete: received $received of $contentLength bytes. Please try again.',
        );
      }

      // Verify the file actually exists and has content
      final downloadedFile = File(savePath);
      final fileSize = await downloadedFile.length();
      print('AG_DEBUG: Final file size on disk: $fileSize bytes');
      if (fileSize < 1024 * 1024) {
        // Sanity check: backend should be > 1MB
        print('AG_DEBUG: File suspiciously small ($fileSize bytes), deleting.');
        try {
          await downloadedFile.delete();
        } catch (_) {}
        throw Exception(
          'Downloaded file is too small ($fileSize bytes). The download may have failed.',
        );
      }

      if (_remoteVersion != null) {
        await KoboldBinaryVersion.write(
          _storageService.binDir.path,
          version: _remoteVersion!,
          size: fileSize,
        );
      }

      _isDownloading = false;
      _downloadProgress = 1.0;
      _statusMessage = 'Finalizing...';
      notifyListeners();

      print('AG_DEBUG: Checking backend availability...');
      await Future.delayed(const Duration(milliseconds: 500)); // Brief pause
      await checkBackendAvailability();
      checkForUpdates();
      print('AG_DEBUG: Backend check complete. Status: $_statusMessage');
    } catch (e, stack) {
      _isDownloading = false;
      _error = 'Error: $e';
      _statusMessage = 'Failed';
      notifyListeners();
      print('AG_DEBUG: Download fatal error: $e');
      print('AG_DEBUG: Stack: $stack');
    }
  }

  String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec < 1024) return '${bytesPerSec.toStringAsFixed(1)} B/s';
    if (bytesPerSec < 1024 * 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    }
    if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    }
    return '${d.inSeconds}s';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _getExecutableName() {
    if (Platform.isWindows) return 'koboldcpp.exe';
    if (Platform.isLinux) {
      if (_useRocm) return 'koboldcpp-linux-x64-rocm';
      if (_hasCuda) return 'koboldcpp-linux-x64';
      return 'koboldcpp-linux-x64-nocuda';
    }
    if (Platform.isMacOS) {
      return _arch == 'arm64' ? 'koboldcpp-mac-arm64' : 'koboldcpp-mac-x64';
    }
    return 'koboldcpp';
  }

  String _getDownloadUrl() {
    if (Platform.isWindows) {
      return 'https://github.com/LostRuins/koboldcpp/releases/latest/download/koboldcpp.exe';
    }
    if (Platform.isLinux) {
      if (_useRocm) return 'https://koboldai.org/cpplinuxrocm';
      if (_hasCuda) {
        return 'https://github.com/LostRuins/koboldcpp/releases/latest/download/koboldcpp-linux-x64';
      }
      return 'https://github.com/LostRuins/koboldcpp/releases/latest/download/koboldcpp-linux-x64-nocuda';
    }
    if (Platform.isMacOS) {
      return _arch == 'arm64'
          ? 'https://github.com/LostRuins/koboldcpp/releases/latest/download/koboldcpp-mac-arm64'
          : 'https://github.com/LostRuins/koboldcpp/releases/latest/download/koboldcpp-mac-x64';
    }
    throw Exception('Unsupported platform');
  }
}
