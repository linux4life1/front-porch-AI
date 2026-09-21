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

part of 'backend_manager.dart';

/// Stream-to-.part then swap. Version check and availability stay on
/// [BackendManager]. [BackendManager.swapStagedBinary] stays on the class
/// — backend_binary_staging_test calls it.
extension BackendManagerDownload on BackendManager {
  Future<void> _downloadBackendImpl() async {
    if (_isDownloading) return;
    if (_storageService.rootPath == null) return;

    // Intel Macs cannot run KoboldCpp (no Metal GPU acceleration)
    if (isIntelMac) {
      _error =
          'Local inference is not supported on Intel Macs. Please use Remote API mode.';
      _statusMessage = 'Unsupported';
      notify();
      return;
    }

    _isDownloading = true;
    _error = null;
    _downloadProgress = 0.0;
    _statusMessage = 'Initializing download...';
    notify();

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
      // Stage into a sibling `.part` and swap it onto the live path only after
      // the size checks pass. Writing straight onto `savePath` meant a stream
      // that died mid-download (app quit, power loss, dropped link) left a
      // TRUNCATED binary where the engine lives — and
      // checkBackendAvailability() only tests existence, so the app reported
      // "Ready" and Start spawned a corrupt executable. Matches the staging
      // every other downloader in the app already does (model_fetch,
      // download_task, caption, thumbnails).
      final partPath = '$savePath.part';
      print('AG_DEBUG: Download target: $savePath (staging at $partPath)');
      print('AG_DEBUG: Download URL: $downloadUrl');

      _statusMessage = 'Connecting to GitHub...';
      notify();

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
      final file = File(partPath);
      final sink = file.openWrite();
      bool streamFailed = false;

      _statusMessage = 'Downloading...';
      notify();

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

            notify();
            lastUpdateTime = now;
            lastWebBytes = received;
          }
        }
        print('AG_DEBUG: Stream verified complete. Received: $received bytes.');
      } catch (e) {
        print('AG_DEBUG: Stream error: $e');
        streamFailed = true;
        rethrow;
      } finally {
        print('AG_DEBUG: Closing file sink...');
        await sink.flush();
        await sink.close();
        client.close();
        print('AG_DEBUG: File sink closed.');
        // Delete AFTER the handle is closed: Dart runs `finally` after the
        // catch body, so deleting there raced the still-open sink and failed
        // outright on Windows (sharing violation).
        if (streamFailed) {
          try {
            await file.delete();
          } catch (_) {}
        }
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
      final fileSize = await file.length();
      print('AG_DEBUG: Final file size on disk: $fileSize bytes');
      if (fileSize < 1024 * 1024) {
        // Sanity check: backend should be > 1MB
        print('AG_DEBUG: File suspiciously small ($fileSize bytes), deleting.');
        try {
          await file.delete();
        } catch (_) {}
        throw Exception(
          'Downloaded file is too small ($fileSize bytes). The download may have failed.',
        );
      }

      // Only now does the complete binary become the live executable.
      await BackendManager.swapStagedBinary(file, savePath);

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
      notify();

      print('AG_DEBUG: Checking backend availability...');
      await Future.delayed(const Duration(milliseconds: 500)); // Brief pause
      await checkBackendAvailability();
      if (UpdateService.isSupported) {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool('update_auto_check') ?? true) {
          checkForUpdates();
        }
      }
      // Portable builds: auto-check skipped (manual button still works)
      print('AG_DEBUG: Backend check complete. Status: $_statusMessage');
    } catch (e, stack) {
      _isDownloading = false;
      _error = 'Error: $e';
      _statusMessage = 'Failed';
      notify();
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
    if (Platform.isWindows) {
      // No AVX2 → the oldpc build is the only one that will run.
      return _hasAvx2 ? 'koboldcpp.exe' : 'koboldcpp-oldpc.exe';
    }
    if (Platform.isLinux) {
      // AVX2 absence is fatal for every AVX2 build (cuda/rocm/nocuda alike), so
      // it takes priority over the GPU-acceleration choice. oldpc = Cuda11+AVX1
      // (CUDA offload kept for older NVIDIA; no ROCm — AMD falls back to CPU).
      if (!_hasAvx2) return 'koboldcpp-linux-x64-oldpc';
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
    const base =
        'https://github.com/LostRuins/koboldcpp/releases/latest/download';
    if (Platform.isWindows) {
      // No AVX2 → the oldpc build is the only one that will run.
      return _hasAvx2 ? '$base/koboldcpp.exe' : '$base/koboldcpp-oldpc.exe';
    }
    if (Platform.isLinux) {
      // AVX2 absence is fatal for every AVX2 build, so it wins over GPU choice.
      if (!_hasAvx2) return '$base/koboldcpp-linux-x64-oldpc';
      if (_useRocm) return 'https://koboldai.org/cpplinuxrocm';
      if (_hasCuda) return '$base/koboldcpp-linux-x64';
      return '$base/koboldcpp-linux-x64-nocuda';
    }
    if (Platform.isMacOS) {
      return _arch == 'arm64'
          ? 'https://github.com/LostRuins/koboldcpp/releases/latest/download/koboldcpp-mac-arm64'
          : 'https://github.com/LostRuins/koboldcpp/releases/latest/download/koboldcpp-mac-x64';
    }
    throw Exception('Unsupported platform');
  }
}
