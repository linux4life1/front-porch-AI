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

import 'package:flutter/material.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

IconData downloadStatusIcon(DownloadTaskState state) {
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

Color downloadStatusColor(BuildContext context, DownloadTaskState state) {
  final (dark, light) = switch (state) {
    DownloadTaskState.downloading => (
      DownloadStatusColors.downloading,
      DownloadStatusColors.downloadingLight,
    ),
    DownloadTaskState.paused => (
      DownloadStatusColors.paused,
      DownloadStatusColors.pausedLight,
    ),
    DownloadTaskState.pending => (
      DownloadStatusColors.pending,
      DownloadStatusColors.pendingLight,
    ),
    DownloadTaskState.completed => (
      DownloadStatusColors.completed,
      DownloadStatusColors.completedLight,
    ),
    DownloadTaskState.failed => (
      DownloadStatusColors.failed,
      DownloadStatusColors.failedLight,
    ),
    DownloadTaskState.verifying => (
      DownloadStatusColors.verifying,
      DownloadStatusColors.verifyingLight,
    ),
    DownloadTaskState.cancelled => (
      DownloadStatusColors.cancelled,
      DownloadStatusColors.cancelledLight,
    ),
  };
  return AppColors.resolve(context, dark, light);
}

/// The status line under a task's name. Dark mode softens the hue; light
/// mode keeps the deep tone whole so it reads on paper.
Color downloadStatusInk(BuildContext context, DownloadTaskState state) {
  final hue = downloadStatusColor(context, state);
  return AppColors.isLight(context) ? hue : hue.withValues(alpha: 0.7);
}

String formatDownloadSpeed(double bytesPerSec) {
  if (bytesPerSec < 1024) {
    return '${bytesPerSec.toStringAsFixed(0)} B/s';
  } else if (bytesPerSec < 1024 * 1024) {
    return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
  }
  return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
}
