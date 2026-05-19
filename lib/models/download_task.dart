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

import 'dart:io';
import 'package:uuid/uuid.dart';

/// The current state of a download task in the queue.
enum DownloadTaskState {
  /// Task is queued and waiting for a download slot.
  pending,

  /// Task is actively downloading.
  downloading,

  /// Task has been paused by the user.
  paused,

  /// Task completed successfully.
  completed,

  /// Task failed with an error.
  failed,

  /// Task is verifying file integrity (SHA256 checksum).
  verifying,

  /// Task was cancelled by the user.
  cancelled;

  /// Whether this state is considered "active" (showing in active downloads).
  bool get isActive => this == downloading || this == verifying;

  /// Whether this state is terminal (cannot be resumed).
  bool get isTerminal => this == completed || this == failed || this == cancelled;

  /// Whether the task can be resumed from this state.
  bool get canResume => this == paused || this == failed;
}

/// Represents a single download task in the download queue.
/// Tracks progress, state, speed, and supports pause/resume via HTTP Range requests.
class DownloadTask {
  /// Unique identifier for this task.
  final String id;

  /// The URL to download from.
  final String url;

  /// The filename to save as (basename only).
  final String filename;

  /// The parent repository ID (for HuggingFace models).
  final String? repoId;

  /// The target directory to save the file.
  final String targetDir;

  /// Full path where the file will be saved.
  String get targetPath => '$targetDir/$filename';

  /// Full path to the temporary partial download file.
  String get tempPath => '$targetDir/.$filename.part';

  /// Current state of the download.
  DownloadTaskState state;

  /// Progress from 0.0 to 1.0.
  double progress;

  /// Bytes downloaded so far.
  int bytesDownloaded;

  /// Total file size in bytes (0 until headers are received).
  int totalBytes;

  /// Current download speed in bytes per second.
  double speedBytesPerSec;

  /// Estimated time remaining in seconds (0 if unknown).
  int etaSeconds;

  /// Timestamp when the task was paused (for resume tracking).
  DateTime? pausedAt;

  /// Error message if the task failed.
  String? errorMessage;

  /// Number of retry attempts made.
  int retryCount;

  /// Maximum retry attempts before marking as failed.
  final int maxRetries;

  /// SHA256 hash expected for this file (if known).
  final String? expectedSha256;

  /// The HTTP Range offset where we left off (for resume).
  int _resumeOffset;

  /// Previous bytes for speed calculation.
  int _previousBytes;

  /// Previous timestamp for speed calculation.
  DateTime? _previousTime;

  DownloadTask({
    String? id,
    required this.url,
    required this.filename,
    required this.targetDir,
    this.repoId,
    this.expectedSha256,
    this.maxRetries = 3,
  })  : id = id ?? const Uuid().v4(),
        state = DownloadTaskState.pending,
        progress = 0.0,
        bytesDownloaded = 0,
        totalBytes = 0,
        speedBytesPerSec = 0,
        etaSeconds = 0,
        retryCount = 0,
        _resumeOffset = 0,
        _previousBytes = 0;

  /// Creates a DownloadTask from an existing partial download.
  /// Used when restoring paused downloads on app restart.
  factory DownloadTask.fromPartial({
    required String id,
    required String url,
    required String filename,
    required String targetDir,
    required int bytesDownloaded,
    required int totalBytes,
    String? repoId,
    String? expectedSha256,
    int maxRetries = 3,
  }) {
    final task = DownloadTask(
      id: id,
      url: url,
      filename: filename,
      targetDir: targetDir,
      repoId: repoId,
      expectedSha256: expectedSha256,
      maxRetries: maxRetries,
    );
    task.bytesDownloaded = bytesDownloaded;
    task.totalBytes = totalBytes;
    task._resumeOffset = bytesDownloaded;
    task.state = DownloadTaskState.paused;
    task.progress = totalBytes > 0 ? bytesDownloaded / totalBytes : 0.0;
    task.pausedAt = DateTime.now();
    return task;
  }

  /// Human-readable progress string (e.g., "45.2%").
  String get progressDisplay => '${(progress * 100).toStringAsFixed(1)}%';

  /// Human-readable downloaded size.
  String get downloadedDisplay => _formatBytes(bytesDownloaded);

  /// Human-readable total size.
  String get totalDisplay => _formatBytes(totalBytes);

  /// Human-readable speed (e.g., "12.5 MB/s").
  String get speedDisplay {
    if (speedBytesPerSec < 1024) {
      return '${speedBytesPerSec.toStringAsFixed(0)} B/s';
    } else if (speedBytesPerSec < 1024 * 1024) {
      return '${(speedBytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(speedBytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  /// Human-readable ETA (e.g., "3m 22s").
  String get etaDisplay {
    if (etaSeconds <= 0) return '--:--';
    final minutes = etaSeconds ~/ 60;
    final seconds = etaSeconds % 60;
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final remainingMinutes = minutes % 60;
      return '${hours}h ${remainingMinutes}m';
    }
    return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }

  /// Full status string for display.
  String get statusString {
    switch (state) {
      case DownloadTaskState.pending:
        return 'Queued';
      case DownloadTaskState.downloading:
        return '$progressDisplay — $speedDisplay — ETA: $etaDisplay';
      case DownloadTaskState.paused:
        return 'Paused at $progressDisplay';
      case DownloadTaskState.completed:
        return 'Completed';
      case DownloadTaskState.failed:
        return 'Failed: ${errorMessage ?? "Unknown error"}';
      case DownloadTaskState.verifying:
        return 'Verifying integrity...';
      case DownloadTaskState.cancelled:
        return 'Cancelled';
    }
  }

  /// Updates progress and calculates speed/ETA.
  void updateProgress(int newBytesDownloaded, int newTotalBytes) {
    bytesDownloaded = newBytesDownloaded;
    totalBytes = newTotalBytes;
    progress = newTotalBytes > 0 ? newBytesDownloaded / newTotalBytes : 0.0;

    // Calculate speed using moving average
    final now = DateTime.now();
    if (_previousTime != null && _previousBytes > 0) {
      final elapsed = now.difference(_previousTime!).inMilliseconds / 1000;
      if (elapsed > 0) {
        final currentSpeed = (newBytesDownloaded - _previousBytes) / elapsed;
        // Smooth the speed with exponential moving average
        speedBytesPerSec = (speedBytesPerSec * 0.7) + (currentSpeed * 0.3);
      }
    }

    // Calculate ETA
    if (speedBytesPerSec > 0 && newTotalBytes > newBytesDownloaded) {
      final remaining = newTotalBytes - newBytesDownloaded;
      etaSeconds = (remaining / speedBytesPerSec).round();
    } else {
      etaSeconds = 0;
    }

    // Update tracking variables
    _previousBytes = newBytesDownloaded;
    _previousTime = now;
  }

  /// Starts the download timer.
  void start() {
    _previousBytes = bytesDownloaded;
    _previousTime = DateTime.now();
    state = DownloadTaskState.downloading;
    pausedAt = null;
  }

  /// Pauses the download.
  void pause() {
    state = DownloadTaskState.paused;
    pausedAt = DateTime.now();
    speedBytesPerSec = 0;
    etaSeconds = 0;
  }

  /// Resumes the download from where it left off.
  void resume() {
    // Check if partial file exists and get its size
    try {
      final tempFile = File(tempPath);
      if (tempFile.existsSync()) {
        final existingSize = tempFile.lengthSync();
        if (existingSize > 0) {
          _resumeOffset = existingSize;
          bytesDownloaded = existingSize;
          progress = totalBytes > 0 ? existingSize / totalBytes : 0.0;
        }
      }
    } catch (_) {
      // If we can't read the partial file, start from scratch
      _resumeOffset = 0;
      bytesDownloaded = 0;
      progress = 0.0;
    }

    state = DownloadTaskState.downloading;
    pausedAt = null;
    errorMessage = null;
  }

  /// Marks the task as completed.
  void complete() {
    state = DownloadTaskState.completed;
    progress = 1.0;
    speedBytesPerSec = 0;
    etaSeconds = 0;

    // Clean up partial file if it exists
    try {
      final tempFile = File(tempPath);
      if (tempFile.existsSync()) {
        tempFile.renameSync(targetPath);
      }
    } catch (_) {
      // File might already be in place
    }
  }

  /// Marks the task as failed with an error message.
  void fail(String error) {
    state = DownloadTaskState.failed;
    errorMessage = error;
    speedBytesPerSec = 0;
    etaSeconds = 0;
  }

  /// Cancels the download and cleans up partial files.
  void cancel() {
    state = DownloadTaskState.cancelled;
    speedBytesPerSec = 0;
    etaSeconds = 0;

    // Clean up partial file
    try {
      final tempFile = File(tempPath);
      if (tempFile.existsSync()) {
        tempFile.deleteSync();
      }
    } catch (_) {
      // Ignore cleanup errors
    }
  }

  /// Retries the download after a failure.
  void retry() {
    retryCount++;
    errorMessage = null;

    if (retryCount > maxRetries) {
      fail('Max retries ($maxRetries) exceeded');
      return;
    }

    // Try to resume from partial file
    resume();
  }

  /// Returns the HTTP Range header value for resuming downloads.
  /// Returns null if starting from scratch.
  String? get rangeHeader {
    if (_resumeOffset > 0) {
      return 'bytes=$_resumeOffset-';
    }
    return null;
  }

  /// Formats bytes into a human-readable string.
  static String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Serializes this task to a map for persistence.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'filename': filename,
      'repoId': repoId,
      'targetDir': targetDir,
      'state': state.name,
      'progress': progress,
      'bytesDownloaded': bytesDownloaded,
      'totalBytes': totalBytes,
      'pausedAt': pausedAt?.toIso8601String(),
      'errorMessage': errorMessage,
      'retryCount': retryCount,
      'maxRetries': maxRetries,
      'expectedSha256': expectedSha256,
    };
  }

  /// Deserializes a DownloadTask from a map.
  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    return DownloadTask.fromPartial(
      id: json['id'] as String,
      url: json['url'] as String,
      filename: json['filename'] as String,
      targetDir: json['targetDir'] as String,
      bytesDownloaded: json['bytesDownloaded'] as int,
      totalBytes: json['totalBytes'] as int,
      repoId: json['repoId'] as String?,
      expectedSha256: json['expectedSha256'] as String?,
      maxRetries: json['maxRetries'] as int? ?? 3,
    );
  }

  @override
  String toString() => 'DownloadTask($id, $filename, $state, $progressDisplay)';
}
