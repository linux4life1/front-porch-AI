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

enum DeskNewSessionChoice { sameCharacter, pickNew }

/// After New session on a known folder: keep last coworker or pick another.
class DeskNewSessionDialog extends StatelessWidget {
  const DeskNewSessionDialog({super.key, required this.project});

  final DeskProject project;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    final honey = AppColors.porchHoneyOf(context);
    final terra = AppColors.porchTerracottaOf(context);
    final name = project.coworker.name;
    final folder = p.basename(project.folderRoot);
    final initial = name.isEmpty ? '?' : name.substring(0, 1);
    return AlertDialog(
      backgroundColor: AppColors.surfaceOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: amber, width: 1.6),
      ),
      title: Text(
        'New session in $folder?',
        style: TextStyle(
          color: AppColors.textPrimary(context),
          fontWeight: FontWeight.w900,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [amber, honey, terra]),
              boxShadow: [
                BoxShadow(color: amber.withValues(alpha: 0.5), blurRadius: 16),
              ],
            ),
            child: Text(
              initial.toUpperCase(),
              style: TextStyle(
                color: AppColors.onChaosAccent,
                fontWeight: FontWeight.w900,
                fontSize: 28,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Last time you sat down with $name. Same coworker, or someone new?',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('desk-new-session-pick'),
          onPressed: () => Navigator.pop(context, DeskNewSessionChoice.pickNew),
          child: Text(
            'Pick a new character',
            style: TextStyle(color: honey, fontWeight: FontWeight.w700),
          ),
        ),
        FilledButton(
          key: const Key('desk-new-session-same'),
          style: FilledButton.styleFrom(
            backgroundColor: amber,
            foregroundColor: AppColors.onChaosAccent,
          ),
          onPressed: () =>
              Navigator.pop(context, DeskNewSessionChoice.sameCharacter),
          child: Text('Use $name again'),
        ),
      ],
    );
  }
}
