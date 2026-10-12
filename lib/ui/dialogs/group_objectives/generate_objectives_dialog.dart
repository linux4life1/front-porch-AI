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

/// Task-generation knobs that outlive one "Generate Objectives" dialog: the
/// dialog edits them in place (even when cancelled) and "Regenerate tasks"
/// reads them.
class ObjectiveGenerationSettings {
  int taskCount = 5;
  bool nsfw = false;
}

/// Opens the "Generate Objectives" dialog over [settings]. [onGenerate] runs
/// after the dialog pops when the user confirms.
void showGenerateObjectivesDialog(
  BuildContext context, {
  required ObjectiveGenerationSettings settings,
  required Future<void> Function() onGenerate,
}) {
  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlg) => AlertDialog(
        title: const Text('Generate Objectives'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text('Tasks per objective'),
                const Spacer(),
                DropdownButton<int>(
                  value: settings.taskCount,
                  items: const [3, 5, 7, 9]
                      .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                      .toList(),
                  onChanged: (v) => setDlg(() => settings.taskCount = v ?? 5),
                ),
              ],
            ),
            SwitchListTile(
              title: const Text('Allow NSFW tasks'),
              value: settings.nsfw,
              onChanged: (v) => setDlg(() => settings.nsfw = v),
              dense: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await onGenerate();
            },
            child: const Text('Generate'),
          ),
        ],
      ),
    ),
  );
}
