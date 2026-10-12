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
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Per-task pause / resume / retry / cancel buttons for the state [task] is in.
class DownloadTaskControls extends StatelessWidget {
  const DownloadTaskControls({
    super.key,
    required this.task,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
  });

  final DownloadTask task;
  final ValueChanged<String> onPause;
  final ValueChanged<String> onResume;
  final ValueChanged<String> onCancel;

  @override
  Widget build(BuildContext context) {
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
              onPressed: () => onPause(task.id),
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
            ),
            IconButton(
              icon: Icon(
                Icons.close_rounded,
                color: AppColors.iconSecondary(context),
                size: 16,
              ),
              onPressed: () => onCancel(task.id),
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
              onPressed: () => onResume(task.id),
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
            ),
            IconButton(
              icon: Icon(
                Icons.close_rounded,
                color: AppColors.iconSecondary(context),
                size: 16,
              ),
              onPressed: () => onCancel(task.id),
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
          onPressed: () => onCancel(task.id),
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
              onPressed: () => onResume(task.id),
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
              onPressed: () => onCancel(task.id),
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
