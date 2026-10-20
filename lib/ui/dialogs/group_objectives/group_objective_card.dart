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

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/story_tools/story_tools.dart'
    show AmbitionServedChip, ObjectiveSetAsideTag;
import 'package:front_porch_ai/ui/theme/theme.dart';

import 'objective_text_prompt.dart';

/// One objective (primary or secondary) in the group objectives dialog: its
/// text, served ambition, task checklist and per-objective actions.
class GroupObjectiveCard extends StatelessWidget {
  final Objective objective;
  final bool isPrimary;
  final bool generatingTasks;
  final VoidCallback onDelete;
  final ValueChanged<int> onToggleTask;
  final Future<void> Function(int index, String newText) onEditTask;
  final VoidCallback onRegenerateTasks;
  final VoidCallback onPromote;

  const GroupObjectiveCard({
    super.key,
    required this.objective,
    required this.isPrimary,
    required this.generatingTasks,
    required this.onDelete,
    required this.onToggleTask,
    required this.onEditTask,
    required this.onRegenerateTasks,
    required this.onPromote,
  });

  static List<Map<String, dynamic>> _tasksFor(Objective obj) {
    try {
      return (jsonDecode(obj.tasks) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final obj = objective;
    final tasks = _tasksFor(obj);
    final completedCount = completedQuestTaskCount(tasks);
    final countable = countableQuestTaskCount(tasks);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isPrimary
              ? AccentColors.goldEdgeOf(context)
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
                icon: Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: StatusColors.dangerOf(context),
                ),
                onPressed: onDelete,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
          // Same chip the 1:1 sidebar shows (v46) — a group member's quest
          // names the ambition it climbs exactly as a 1:1 partner's does.
          AmbitionServedChip(servedAmbition: obj.servedAmbition),
          ObjectiveSetAsideTag(dormant: objectiveIsDormant(obj)),
          if (tasks.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '$completedCount / $countable tasks complete',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary(context),
              ),
            ),
            const SizedBox(height: 4),
            ...tasks.asMap().entries.map((entry) {
              final i = entry.key;
              final t = entry.value;
              final stale = objectiveTaskIsStale(t);
              final done = objectiveTaskIsCompleted(t);
              return CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  stale
                      ? '${t['description'] ?? ''}  · stale-skipped'
                      : t['description'] ?? '',
                  style: TextStyle(
                    decoration: done ? TextDecoration.lineThrough : null,
                    fontStyle: stale ? FontStyle.italic : FontStyle.normal,
                    fontSize: 12,
                    color: stale ? AppColors.textTertiary(context) : null,
                  ),
                ),
                value: done,
                onChanged: stale ? null : (_) => onToggleTask(i),
                secondary: IconButton(
                  icon: const Icon(Icons.edit, size: 14),
                  onPressed: () async {
                    final newText = await promptForObjectiveText(
                      context,
                      title: 'Edit task',
                      confirmLabel: 'Save',
                      initial: t['description']?.toString(),
                    );
                    if (newText != null) {
                      await onEditTask(i, newText);
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
                onPressed: generatingTasks ? null : onRegenerateTasks,
                icon: const Icon(Icons.auto_awesome, size: 14),
                label: const Text(
                  'Regenerate tasks',
                  style: TextStyle(fontSize: 11),
                ),
              ),
              const Spacer(),
              if (!isPrimary)
                TextButton(
                  onPressed: onPromote,
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
