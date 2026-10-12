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

// Streams a KoboldCpp build to a sibling `.part`, checks it is whole, and
// swaps it onto the live path. The version record and the manager's state
// stay with BackendManager.

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import 'engine_files.dart';

/// Reports a status line, with the fraction done when the size is known.
typedef EngineDownloadStatus = void Function(String status, {double? progress});

/// Downloads [url] to [savePath] and returns the size on disk. Throws with a
/// user-facing message when the request is refused, the stream dies, or the
/// file comes up short.
///
/// Staged into `$savePath.part` and swapped on only after the size checks
/// pass. Writing straight onto [savePath] meant a stream that died
/// mid-download (app quit, power loss, dropped link) left a TRUNCATED binary
/// where the engine lives — and the availability check only tests existence,
/// so the app reported "Ready" and Start spawned a corrupt executable.
/// Matches the staging every other downloader in the app already does
/// (model_fetch, download_task, caption, thumbnails).
Future<int> downloadEngineBinary({
  required String url,
  required String savePath,
  required EngineDownloadStatus onStatus,
  String label = 'Downloading',
}) async {
  final partPath = '$savePath.part';
  print('AG_DEBUG: Download target: $savePath (staging at $partPath)');
  print('AG_DEBUG: Download URL: $url');

  onStatus('Connecting to GitHub...');

  // Use a fresh client
  final client = http.Client();
  final request = http.Request('GET', Uri.parse(url));

  print('AG_DEBUG: Sending request...');
  final response = await client.send(request);
  print('AG_DEBUG: Response received. Status: ${response.statusCode}');

  if (response.statusCode != 200) {
    print('AG_DEBUG: Download failed with status ${response.statusCode}');
    // Closed here too: the finally below only covers the stream, so a
    // refused request left the client's idle connection open.
    client.close();
    throw Exception('Failed to download backend: HTTP ${response.statusCode}');
  }

  final contentLength = response.contentLength ?? 0;
  print('AG_DEBUG: Content length: $contentLength');

  int received = 0;
  final file = File(partPath);
  final sink = file.openWrite();
  bool streamFailed = false;

  onStatus('$label...');

  DateTime startTime = DateTime.now();
  DateTime lastUpdateTime = startTime;
  int lastWebBytes = 0;

  try {
    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;

      final now = DateTime.now();
      if (now.difference(lastUpdateTime).inMilliseconds >= 500) {
        final timeDiff = now.difference(lastUpdateTime).inMilliseconds / 1000.0;
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
          final progress = received / contentLength;
          onStatus(
            '$label: ${(progress * 100).toStringAsFixed(1)}% ($speedStr)$etaStr',
            progress: progress,
          );
        } else {
          onStatus(
            '$label: ${(received / 1024 / 1024).toStringAsFixed(1)} MB ($speedStr)',
          );
        }

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
  await swapStagedEngineBinary(file, savePath);
  return fileSize;
}

/// Downloads [exeName] from [url] into [binDir] (creating it), then writes
/// its version record from [version], read once the file is in place.
Future<void> installEngineBuild({
  required Directory binDir,
  required String exeName,
  required String url,
  required String label,
  required EngineDownloadStatus onStatus,
  required String? Function() version,
}) async {
  print('AG_DEBUG: Starting download process...');
  if (!await binDir.exists()) {
    print('AG_DEBUG: Creating directory ${binDir.path}');
    await binDir.create(recursive: true);
  }
  final fileSize = await downloadEngineBinary(
    url: url,
    savePath: path.join(binDir.path, exeName),
    label: label,
    onStatus: onStatus,
  );
  await recordEngineVersion(binDir.path, version(), fileSize);
}

/// Move a fully-downloaded staging file onto the live executable path. The
/// rename is atomic on all three desktop platforms, so [livePath] only ever
/// holds a whole binary — never the truncated remains of an interrupted
/// download. A locked target (Windows keeps a RUNNING .exe open; Linux
/// returns ETXTBSY) is retried once after unlinking and, failing that,
/// reported in words a non-technical user can act on instead of a raw
/// sharing-violation string. The staged file is left in place on failure so
/// the download is not thrown away.
Future<void> swapStagedEngineBinary(File staged, String livePath) async {
  try {
    await staged.rename(livePath);
    return;
  } on FileSystemException catch (e) {
    print('AG_DEBUG: Direct rename onto $livePath failed ($e) — retrying');
  }
  try {
    final live = File(livePath);
    if (await live.exists()) await live.delete();
    await staged.rename(livePath);
  } catch (e) {
    print('AG_DEBUG: Could not replace $livePath: $e');
    throw Exception(
      'Could not replace the engine file — it looks like KoboldCpp is still '
      'running. Press Stop on this page, then start the download again.',
    );
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
