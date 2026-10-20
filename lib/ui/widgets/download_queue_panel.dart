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

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/download_queue_panel/download_queue_panel.dart';

/// Collapsible panel showing active downloads with controls.
class DownloadQueuePanel extends StatefulWidget {
  /// List of active download tasks.
  final List<DownloadTask> activeDownloads;

  /// List of pending download tasks.
  final List<DownloadTask> pendingDownloads;

  /// Overall progress (0.0 to 1.0).
  final double overallProgress;

  /// Overall speed in bytes per second.
  final double overallSpeed;

  /// Callback to pause a specific download.
  final ValueChanged<String> onPause;

  /// Callback to resume a specific download.
  final ValueChanged<String> onResume;

  /// Callback to cancel a specific download.
  final ValueChanged<String> onCancel;

  /// Callback to pause all downloads.
  final VoidCallback onPauseAll;

  /// Callback to resume all downloads.
  final VoidCallback onResumeAll;

  /// Callback to clear completed downloads.
  final VoidCallback? onClearCompleted;

  const DownloadQueuePanel({
    super.key,
    required this.activeDownloads,
    required this.pendingDownloads,
    required this.overallProgress,
    required this.overallSpeed,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
    required this.onPauseAll,
    required this.onResumeAll,
    this.onClearCompleted,
  });

  @override
  State<DownloadQueuePanel> createState() => _DownloadQueuePanelState();
}

class _DownloadQueuePanelState extends State<DownloadQueuePanel>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = true;
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeInOut,
    );
    _expandController.forward();
  }

  @override
  void dispose() {
    _expandController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _expandController.forward();
      } else {
        _expandController.reverse();
      }
    });
  }

  bool get hasDownloads =>
      widget.activeDownloads.isNotEmpty || widget.pendingDownloads.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!hasDownloads) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(12),
        topRight: Radius.circular(12),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.isLight(context)
                ? AppColors.surfaceContainerOf(context)
                : AppColors.porchAmberOf(context).withValues(alpha: 0.1),
            border: Border(top: BorderSide(color: AppColors.borderOf(context))),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header bar
              InkWell(
                onTap: _toggleExpanded,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      // Download icon with animation
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.porchAmberOf(
                            context,
                          ).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.download_rounded,
                          color: DownloadStatusColors.downloadingOf(context),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Status text
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${widget.activeDownloads.length} downloading${widget.pendingDownloads.isNotEmpty ? ' • ${widget.pendingDownloads.length} queued' : ''}',
                              style: TextStyle(
                                color: AppColors.textPrimary(context),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${formatDownloadSpeed(widget.overallSpeed)} • ${(widget.overallProgress * 100).toStringAsFixed(1)}% complete',
                              style: TextStyle(
                                color: AppColors.textTertiary(context),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Global controls
                      if (widget.activeDownloads.isNotEmpty) ...[
                        IconButton(
                          icon: Icon(
                            Icons.pause_circle_rounded,
                            color: AppColors.iconSecondary(context),
                            size: 20,
                          ),
                          onPressed: widget.onPauseAll,
                          tooltip: 'Pause all',
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                        const SizedBox(width: 4),
                      ],

                      // Expand arrow
                      AnimatedRotation(
                        turns: _isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 300),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: AppColors.iconSecondary(context),
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Overall progress bar
              LinearProgressIndicator(
                value: widget.overallProgress,
                minHeight: 3,
                backgroundColor: InkColors.trackOf(context, dark: 0.05),
                valueColor: AlwaysStoppedAnimation<Color>(
                  DownloadStatusColors.downloadingOf(context),
                ),
              ),

              // Expanded content
              SizeTransition(
                sizeFactor: _expandAnimation,
                // Old axisAlignment: -1 (vertical) per the SDK migration formula.
                alignment: Alignment.topLeft,
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  padding: const EdgeInsets.all(12),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount:
                        widget.activeDownloads.length +
                        widget.pendingDownloads.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final task = index < widget.activeDownloads.length
                          ? widget.activeDownloads[index]
                          : widget.pendingDownloads[index -
                                widget.activeDownloads.length];
                      return _buildTaskRow(task);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskRow(DownloadTask task) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: InkColors.rowFillOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: InkColors.rowEdgeOf(context)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Status icon
              Icon(
                downloadStatusIcon(task.state),
                color:
                    (task.state == DownloadTaskState.pending ||
                        task.state == DownloadTaskState.cancelled)
                    ? AppColors.iconSecondary(context)
                    : downloadStatusColor(context, task.state),
                size: 16,
              ),
              const SizedBox(width: 8),

              // Task info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.filename,
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      task.statusString,
                      style: TextStyle(
                        color:
                            (task.state == DownloadTaskState.pending ||
                                task.state == DownloadTaskState.cancelled)
                            ? AppColors.textTertiary(context)
                            : downloadStatusInk(context, task.state),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),

              // Controls
              DownloadTaskControls(
                task: task,
                onPause: widget.onPause,
                onResume: widget.onResume,
                onCancel: widget.onCancel,
              ),
            ],
          ),

          // Progress bar for active tasks
          if (task.state.isActive ||
              task.state == DownloadTaskState.paused) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: task.progress,
              minHeight: 3,
              backgroundColor: InkColors.trackOf(context),
              valueColor: AlwaysStoppedAnimation<Color>(
                downloadStatusColor(context, task.state),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
