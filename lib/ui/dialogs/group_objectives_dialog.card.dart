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

extension _GroupObjectivesCard on _GroupObjectivesDialogState {
  Widget _buildObjectiveCard(Objective obj, {required bool isPrimary}) {
    final tasks = _tasksFor(obj);
    final completedCount = tasks.where((t) => t['completed'] == true).length;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isPrimary
              ? Colors.amber.withValues(alpha: 0.4)
              : AppColors.borderOf(context).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  obj.objective,
                  style: TextStyle(
                    fontWeight: isPrimary ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: Colors.redAccent,
                ),
                onPressed: () => _clearObjective(obj),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
          // Same chip the 1:1 sidebar shows (v46) — a group member's quest
          // names the ambition it climbs exactly as a 1:1 partner's does.
          AmbitionServedChip(servedAmbition: obj.servedAmbition),
          if (tasks.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '$completedCount / ${tasks.length} tasks complete',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
            const SizedBox(height: 4),
            ...tasks.asMap().entries.map((entry) {
              final i = entry.key;
              final t = entry.value;
              final done = t['completed'] == true;
              return CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  t['description'] ?? '',
                  style: TextStyle(
                    decoration: done ? TextDecoration.lineThrough : null,
                    fontSize: 12,
                  ),
                ),
                value: done,
                onChanged: (_) => _toggleTask(obj, i),
                secondary: IconButton(
                  icon: const Icon(Icons.edit, size: 14),
                  onPressed: () async {
                    final newText = await _promptForText(
                      title: 'Edit task',
                      confirmLabel: 'Save',
                      initial: t['description']?.toString(),
                    );
                    if (newText != null) {
                      await _updateTask(obj, i, newText);
                    }
                  },
                ),
              );
            }),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton.icon(
                onPressed: _generatingTasks ? null : () => _generateTasks(obj),
                icon: const Icon(Icons.auto_awesome, size: 14),
                label: const Text(
                  'Regenerate tasks',
                  style: TextStyle(fontSize: 11),
                ),
              ),
              const Spacer(),
              if (!isPrimary)
                TextButton(
                  onPressed: () async {
                    // Promote IN PLACE (keeps id + task progress; the old
                    // setObjective-with-same-text pattern inserted a duplicate
                    // primary and left this side quest active).
                    await widget.chatService.promoteObjective(obj);
                    await _loadForCurrent();
                  },
                  child: const Text(
                    'Make primary',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
