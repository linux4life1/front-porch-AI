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

part of 'group_objectives_dialog.dart';

extension _GroupObjectivesPrompts on _GroupObjectivesDialogState {
  /// The ONE text-prompt dialog here: adding an objective and renaming a task
  /// were two copies of the same AlertDialog differing only in their labels.
  /// Returns the TRIMMED text, or null when cancelled or left blank, so no
  /// caller re-checks for empty. Disposes its controller; neither copy did.
  Future<String?> _promptForText({
    required String title,
    required String confirmLabel,
    String? hint,
    String? initial,
  }) async {
    final ctrl = TextEditingController(text: initial);
    try {
      final text = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: hint == null ? null : InputDecoration(hintText: hint),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(confirmLabel),
            ),
          ],
        ),
      );
      final trimmed = text?.trim() ?? '';
      return trimmed.isEmpty ? null : trimmed;
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _showAddDialog({required bool isPrimary}) async {
    final goal = await _promptForText(
      title: isPrimary ? 'New Primary Objective' : 'New Secondary Objective',
      confirmLabel: 'Add',
      hint: 'Goal description',
    );
    if (goal == null || !mounted) return;
    await widget.chatService.setObjective(
      goal,
      isPrimary: isPrimary,
      targetCharacter: _focused,
    );
    await _loadForCurrent();
  }

  void _showGenerateDialog() {
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
                    value: _taskCount,
                    items: const [3, 5, 7, 9]
                        .map(
                          (n) => DropdownMenuItem(value: n, child: Text('$n')),
                        )
                        .toList(),
                    onChanged: (v) => setDlg(() => _taskCount = v ?? 5),
                  ),
                ],
              ),
              SwitchListTile(
                title: const Text('Allow NSFW tasks'),
                value: _nsfw,
                onChanged: (v) => setDlg(() => _nsfw = v),
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
                // Generate one primary if none exists, plus one secondary
                if (_primary == null) {
                  await widget.chatService.setObjective(
                    'A meaningful personal goal for this scene',
                    isPrimary: true,
                    targetCharacter: _focused,
                  );
                }
                if (_secondaries.length < kMaxSecondaryObjectives) {
                  await widget.chatService.setObjective(
                    'A secondary supporting goal',
                    isPrimary: false,
                    targetCharacter: _focused,
                  );
                }
                await _loadForCurrent();
                // Optionally auto-generate tasks for the new ones
                for (final o in _objectives.take(2)) {
                  await widget.chatService.generateObjectiveTasks(
                    o,
                    taskCount: _taskCount,
                    nsfw: _nsfw,
                  );
                }
                await _loadForCurrent();
              },
              child: const Text('Generate'),
            ),
          ],
        ),
      ),
    );
  }
}
