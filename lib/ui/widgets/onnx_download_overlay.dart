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
// Front Porch AI is distributed on the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// Glassmorphic overlay widget showing ONNX model download progress.
///
/// Displays: download speed, total size, progress bar, and ETA.
class OnnxDownloadOverlay extends StatefulWidget {
  final ExpressionClassifierService classifierService;

  const OnnxDownloadOverlay({super.key, required this.classifierService});

  @override
  State<OnnxDownloadOverlay> createState() => _OnnxDownloadOverlayState();
}

class _OnnxDownloadOverlayState extends State<OnnxDownloadOverlay> {
  Timer? _speedTimer;
  int _lastDownloaded = 0;
  DateTime? _lastTimestamp;
  double _currentSpeed = 0;

  @override
  void initState() {
    super.initState();
    widget.classifierService.addListener(_onStateChanged);
    _speedTimer = Timer.periodic(const Duration(seconds: 1), _updateSpeed);
  }

  @override
  void dispose() {
    widget.classifierService.removeListener(_onStateChanged);
    _speedTimer?.cancel();
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  void _updateSpeed(Timer timer) {
    final progress = widget.classifierService.downloadProgress;
    if (progress == null) return;

    if (_lastTimestamp != null) {
      final elapsed = DateTime.now().difference(_lastTimestamp!).inSeconds;
      if (elapsed > 0) {
        final bytesDiff = progress.downloaded - _lastDownloaded;
        _currentSpeed = bytesDiff / elapsed;
      }
    }
    _lastDownloaded = progress.downloaded;
    _lastTimestamp = DateTime.now();
  }

  String _formatETA(OnnxDownloadProgress progress) {
    if (_currentSpeed <= 0) return '...';
    final remaining = progress.total - progress.downloaded;
    final seconds = remaining / _currentSpeed;
    if (seconds < 60) return '${seconds.toInt()}s';
    if (seconds < 3600) return '${(seconds / 60).toStringAsFixed(0)}m';
    return '${(seconds / 3600).toStringAsFixed(1)}h';
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.classifierService.isDownloading) {
      return const SizedBox.shrink();
    }

    final progress = widget.classifierService.downloadProgress;
    if (progress == null) return const SizedBox.shrink();

    return Positioned.fill(
      child: Container(
        color: InkColors.dim(0.3),
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 380,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: InkColors.glassOf(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: InkColors.glassEdgeOf(context),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 24,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Downloading Emotion Model',
                    style: TextStyle(
                      color: StatusColors.progressOf(context),
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    progress.file,
                    style: TextStyle(
                      color: InkColors.mutedTextOf(context, 0.6),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 20),
                  LinearProgressIndicator(
                    value: progress.fraction,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                    backgroundColor: InkColors.trackOf(context),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      StatusColors.progressOf(context),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${formatBytes(progress.downloaded)} / ${formatBytes(progress.total)}',
                        style: TextStyle(
                          color: StatusColors.progressOf(context),
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '${(progress.fraction * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          color: StatusColors.progressOf(context),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Speed: ${formatBytes(_currentSpeed.toInt())}/s',
                        style: TextStyle(
                          color: InkColors.mutedTextOf(context, 0.7),
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        'ETA: ${_formatETA(progress)}',
                        style: TextStyle(
                          color: InkColors.mutedTextOf(context, 0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
