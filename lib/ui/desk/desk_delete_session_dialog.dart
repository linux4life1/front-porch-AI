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
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Confirm before dropping a parked Waifu Coder session. Disk is untouched.
class DeskDeleteSessionDialog extends StatelessWidget {
  const DeskDeleteSessionDialog({super.key, required this.project});

  final DeskProject project;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    final danger = AppColors.negativeAccentOf(context);
    final folder = p.basename(project.folderRoot);
    final name = project.coworker.name;
    return AlertDialog(
      backgroundColor: AppColors.surfaceOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: danger.withValues(alpha: 0.7), width: 1.6),
      ),
      title: Text(
        'Delete this session?',
        style: TextStyle(
          color: AppColors.textPrimary(context),
          fontWeight: FontWeight.w900,
        ),
      ),
      content: Text(
        'This removes the $folder porch with $name from Waifu Coder. '
        'The folder on disk stays. This can’t be undone.',
        style: TextStyle(color: AppColors.textSecondary(context)),
      ),
      actions: [
        TextButton(
          key: const Key('desk-delete-session-cancel'),
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            'Cancel',
            style: TextStyle(color: amber, fontWeight: FontWeight.w700),
          ),
        ),
        FilledButton(
          key: const Key('desk-delete-session-confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: danger,
            foregroundColor: AppColors.onChaosAccent,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
