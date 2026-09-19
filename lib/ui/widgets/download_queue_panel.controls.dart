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

part of 'download_queue_panel.dart';

extension _DownloadQueuePanelControls on _DownloadQueuePanelState {
  Widget _buildTaskControls(DownloadTask task) {
    switch (task.state) {
      case DownloadTaskState.downloading:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                Icons.pause_rounded,
                color: AppColors.iconSecondary(context),
                size: 16,
              ),
              onPressed: () => widget.onPause(task.id),
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
            ),
            IconButton(
              icon: Icon(
                Icons.close_rounded,
                color: AppColors.iconSecondary(context),
                size: 16,
              ),
              onPressed: () => widget.onCancel(task.id),
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
            ),
          ],
        );
      case DownloadTaskState.paused:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                Icons.play_arrow_rounded,
                color: AppColors.iconSecondary(context),
                size: 16,
              ),
              onPressed: () => widget.onResume(task.id),
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
            ),
            IconButton(
              icon: Icon(
                Icons.close_rounded,
                color: AppColors.iconSecondary(context),
                size: 16,
              ),
              onPressed: () => widget.onCancel(task.id),
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
            ),
          ],
        );
      case DownloadTaskState.pending:
        return IconButton(
          icon: Icon(
            Icons.close_rounded,
            color: AppColors.iconSecondary(context),
            size: 16,
          ),
          onPressed: () => widget.onCancel(task.id),
          constraints: const BoxConstraints(),
          padding: EdgeInsets.zero,
        );
      case DownloadTaskState.failed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                Icons.replay_rounded,
                color: AppColors.iconSecondary(context),
                size: 16,
              ),
              onPressed: () => widget.onResume(task.id),
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
              tooltip: 'Retry',
            ),
            IconButton(
              icon: Icon(
                Icons.close_rounded,
                color: AppColors.iconSecondary(context),
                size: 16,
              ),
              onPressed: () => widget.onCancel(task.id),
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  IconData _getStatusIcon(DownloadTaskState state) {
    switch (state) {
      case DownloadTaskState.downloading:
        return Icons.download_rounded;
      case DownloadTaskState.paused:
        return Icons.pause_circle_rounded;
      case DownloadTaskState.pending:
        return Icons.schedule_rounded;
      case DownloadTaskState.completed:
        return Icons.check_circle_rounded;
      case DownloadTaskState.failed:
        return Icons.error_rounded;
      case DownloadTaskState.verifying:
        return Icons.security_rounded;
      case DownloadTaskState.cancelled:
        return Icons.cancel_rounded;
    }
  }

  Color _getStatusColor(DownloadTaskState state) {
    switch (state) {
      case DownloadTaskState.downloading:
        return const Color(0xFF40C4FF);
      case DownloadTaskState.paused:
        return const Color(0xFFFFD54F);
      case DownloadTaskState.pending:
        return const Color(0xFF9CA3AF);
      case DownloadTaskState.completed:
        return const Color(0xFF69F0AE);
      case DownloadTaskState.failed:
        return const Color(0xFFFF5252);
      case DownloadTaskState.verifying:
        return const Color(0xFFB388FF);
      case DownloadTaskState.cancelled:
        return const Color(0xFF6B7280);
    }
  }

  String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec < 1024) {
      return '${bytesPerSec.toStringAsFixed(0)} B/s';
    } else if (bytesPerSec < 1024 * 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
}
