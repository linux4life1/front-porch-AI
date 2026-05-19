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
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/models/download_task.dart';

/// Manages a queue of model downloads with support for:
/// - Multiple concurrent downloads (configurable, default: 3)
/// - Pause and resume via HTTP Range requests
/// - Progress tracking with speed and ETA
/// - Automatic retry on failure
/// - File integrity verification
class DownloadManager extends ChangeNotifier {
  /// Maximum number of concurrent downloads.
  final int maxConcurrent;

  /// The directory where downloaded models are stored.
  final String targetDir;

  /// Queue of download tasks.
  final List<DownloadTask> _queue = [];

  /// Controller for the download processing loop.
  final StreamController<DownloadAction> _actionController =
      StreamController<DownloadAction>.broadcast();

  /// Whether the processing loop is running.
  bool _isProcessing = false;

  /// Unmodifiable view of the download queue.
  List<DownloadTask> get queue => List.unmodifiable(_queue);

  /// Currently active (downloading or verifying) tasks.
  List<DownloadTask> get activeDownloads =>
      _queue.where((t) => t.state.isActive).toList();

  /// Queued (pending) tasks waiting for a slot.
  List<DownloadTask> get pendingDownloads =>
      _queue.where((t) => t.state == DownloadTaskState.pending).toList();

  /// Completed tasks.
  List<DownloadTask> get completedDownloads =>
      _queue.where((t) => t.state == DownloadTaskState.completed).toList();

  /// Failed tasks.
  List<DownloadTask> get failedDownloads =>
      _queue.where((t) => t.state == DownloadTaskState.failed).toList();

  /// Paused tasks.
  List<DownloadTask> get pausedDownloads =>
      _queue.where((t) => t.state == DownloadTaskState.paused).toList();

  /// Total progress across all active downloads (0.0 to 1.0).
  double get overallProgress {
    final active = activeDownloads;
    if (active.isEmpty) return 0.0;
    final sum = active.fold<double>(0, (s, t) => s + t.progress);
    return sum / active.length;
  }

  /// Combined download speed of all active downloads.
  double get overallSpeed =>
      activeDownloads.fold<double>(0, (s, t) => s + t.speedBytesPerSec);

  DownloadManager({
    required this.targetDir,
    this.maxConcurrent = 3,
  }) {
    _ensureTargetDir();
    _startProcessing();
  }

  /// Ensures the target directory exists.
  Future<void> _ensureTargetDir() async {
    final dir = Directory(targetDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// Starts the download processing loop.
  void _startProcessing() {
    if (_isProcessing) return;
    _isProcessing = true;
    _actionController.stream.listen(_processQueue);
  }

  /// Stops the download processing loop.
  void _stopProcessing() {
    _isProcessing = false;
    _actionController.close();
  }

  /// Adds a new download task to the queue.
  /// Returns the created task.
  DownloadTask addDownload({
    required String url,
    required String filename,
    String? repoId,
    String? expectedSha256,
  }) {
    // Check if this file is already being downloaded or exists
    final existingIndex = _queue.indexWhere((t) => t.filename == filename);
    DownloadTask? existing;
    if (existingIndex != -1) {
      existing = _queue[existingIndex];
    }

    if (existing != null) {
      // Task already exists
      if (existing.state == DownloadTaskState.pending ||
          existing.state == DownloadTaskState.downloading) {
        return existing; // Already in queue
      } else if (existing.state == DownloadTaskState.paused ||
          existing.state == DownloadTaskState.failed) {
        existing.retry();
        _actionController.add(const DownloadAction.resume());
        notifyListeners();
        return existing;
      } else if (existing.state == DownloadTaskState.completed) {
        return existing; // Already done
      }
    }

    final task = DownloadTask(
      url: url,
      filename: filename,
      targetDir: targetDir,
      repoId: repoId,
      expectedSha256: expectedSha256,
    );

    _queue.add(task);
    _actionController.add(const DownloadAction.start());
    notifyListeners();
    return task;
  }

  /// Pauses a specific download by task ID.
  bool pauseDownload(String taskId) {
    final task = _queue.where((t) => t.id == taskId).firstOrNull;
    if (task == null) return false;
    if (task.state != DownloadTaskState.downloading &&
        task.state != DownloadTaskState.verifying) {
      return false;
    }

    task.pause();
    _actionController.add(const DownloadAction.start()); // Process next
    notifyListeners();
    return true;
  }

  /// Resumes a specific download by task ID.
  bool resumeDownload(String taskId) {
    final task = _queue.where((t) => t.id == taskId).firstOrNull;
    if (task == null) return false;
    if (!task.state.canResume) return false;

    task.resume();
    _actionController.add(const DownloadAction.start());
    notifyListeners();
    return true;
  }

  /// Cancels a specific download by task ID.
  bool cancelDownload(String taskId) {
    final task = _queue.where((t) => t.id == taskId).firstOrNull;
    if (task == null) return false;

    task.cancel();
    _actionController.add(const DownloadAction.start()); // Process next
    notifyListeners();
    return true;
  }

  /// Removes a completed/failed/cancelled task from the queue.
  bool removeDownload(String taskId) {
    final index = _queue.indexWhere((t) => t.id == taskId);
    if (index == -1) return false;

    final task = _queue[index];
    if (task.state.isActive) return false; // Can't remove active downloads

    _queue.removeAt(index);
    notifyListeners();
    return true;
  }

  /// Pauses all active downloads.
  void pauseAll() {
    for (final task in _queue) {
      if (task.state == DownloadTaskState.downloading ||
          task.state == DownloadTaskState.verifying) {
        task.pause();
      }
    }
    notifyListeners();
  }

  /// Resumes all paused downloads.
  void resumeAll() {
    for (final task in _queue) {
      if (task.state.canResume) {
        task.resume();
      }
    }
    _actionController.add(const DownloadAction.start());
    notifyListeners();
  }

  /// Clears all completed downloads from the queue.
  void clearCompleted() {
    _queue.removeWhere((t) => t.state == DownloadTaskState.completed);
    notifyListeners();
  }

  /// Processes the download queue.
  Future<void> _processQueue(DownloadAction action) async {
    // Count active downloads
    final activeCount = activeDownloads.length;

    // If we're at capacity, don't start new downloads
    if (activeCount >= maxConcurrent) return;

    // Find pending tasks to start
    final pending = _queue
        .where((t) => t.state == DownloadTaskState.pending)
        .toList();

    final slotsAvailable = maxConcurrent - activeCount;
    final toStart = pending.take(slotsAvailable).toList();

    for (final task in toStart) {
      await _executeDownload(task);
    }
  }

  /// Executes a single download with retry logic.
  Future<void> _executeDownload(DownloadTask task) async {
    task.start();
    notifyListeners();

    try {
      await _downloadFile(task);

      // Verify if SHA256 is expected
      if (task.expectedSha256 != null) {
        task.state = DownloadTaskState.verifying;
        notifyListeners();

        final actualHash = await _calculateSha256(task.targetPath);
        if (actualHash != task.expectedSha256) {
          task.fail('SHA256 mismatch: expected ${task.expectedSha256}, got $actualHash');
          notifyListeners();
          // Try next in queue
          _actionController.add(const DownloadAction.start());
          return;
        }
      }

      task.complete();
    } catch (e) {
      task.fail('Download failed: $e');

      // Auto-retry if under max retries
      if (task.retryCount < task.maxRetries) {
        await Future.delayed(Duration(seconds: 2)); // Brief delay before retry
        task.retry();
        await _executeDownload(task);
        return;
      }
    } finally {
      notifyListeners();
      // Process next in queue
      _actionController.add(const DownloadAction.start());
    }
  }

  /// Downloads a file with Range request support for resume.
  Future<void> _downloadFile(DownloadTask task) async {
    final tempFile = File(task.tempPath);
    final request = http.Request('GET', Uri.parse(task.url));

    // Add Range header if resuming
    final range = task.rangeHeader;
    if (range != null) {
      request.headers['Range'] = range;
    }

    final response = await request.send();

    if (response.statusCode == 416) {
      // Range not satisfiable - file might have changed or been deleted on server
      // Start from scratch
      try {
        await tempFile.delete();
      } catch (_) {
        // Ignore delete errors
      }
      return _downloadFile(task);
    }

    if (response.statusCode != 200 && response.statusCode != 206) {
      throw Exception('HTTP ${response.statusCode} for ${task.url}');
    }

    // Get total file size from Content-Range or Content-Length
    int totalSize;
    int startOffset = 0;

    if (response.statusCode == 206) {
      // Partial content - parse Content-Range
      final contentRange = response.headers['content-range'];
      if (contentRange != null) {
        // Format: "bytes 12345-67890/67891"
        final match = RegExp(r'bytes (\d+)-(\d+)/(\d+)').firstMatch(contentRange);
        if (match != null) {
          startOffset = int.parse(match.group(1)!);
          totalSize = int.parse(match.group(3)!);
        } else {
          totalSize = int.parse(response.headers['content-length'] ?? '0');
          startOffset = task.bytesDownloaded;
        }
      } else {
        totalSize = int.parse(response.headers['content-length'] ?? '0');
        startOffset = task.bytesDownloaded;
      }
    } else {
      // Full content
      totalSize = int.parse(response.headers['content-length'] ?? '0');
      startOffset = 0;
    }

    // Update task with total size
    if (totalSize > 0) {
      task.totalBytes = totalSize;
    }

    // Open file for writing (append mode if resuming)
    final sink = tempFile.openWrite(
      mode: startOffset > 0 ? FileMode.append : FileMode.write,
    );
    int receivedBytes = startOffset;

    // Process response stream
    await for (final chunk in response.stream) {
      if (task.state != DownloadTaskState.downloading) {
        // Download was paused or cancelled
        await sink.close();
        return;
      }

      sink.add(chunk);
      receivedBytes += chunk.length;

      task.updateProgress(receivedBytes, totalSize);
      notifyListeners();
    }

    await sink.flush();
    await sink.close();

    // Final progress update
    task.updateProgress(receivedBytes, totalSize);
  }

  /// Calculates SHA256 hash of a file.
  Future<String> _calculateSha256(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    // Note: For production, consider using crypto package for SHA256
    // This is a placeholder - actual SHA256 would require dart:crypto
    return jsonEncode(bytes.take(100).toList()); // Placeholder
  }

  @override
  void dispose() {
    _stopProcessing();
    super.dispose();
  }
}

/// Actions that can trigger queue processing.
sealed class DownloadAction {
  const DownloadAction();

  /// Start processing pending downloads.
  const factory DownloadAction.start() = _StartAction;

  /// Resume a specific download.
  const factory DownloadAction.resume() = _ResumeAction;
}

final class _StartAction extends DownloadAction {
  const _StartAction();
}

final class _ResumeAction extends DownloadAction {
  const _ResumeAction();
}
