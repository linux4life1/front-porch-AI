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

import 'package:front_porch_ai/database/database.dart' show Objective;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// A single objective task row — checkbox, inline-editable description,
/// current-task marker, edit/save and delete buttons. Extracted from the old
/// ObjectiveSection so ObjectivePanel stays small.
class EditableTaskRow extends StatefulWidget {
  final String description;
  final bool completed;
  final bool isCurrent;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final ValueChanged<String> onEdit;

  const EditableTaskRow({
    super.key,
    required this.description,
    required this.completed,
    required this.isCurrent,
    required this.onToggle,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  State<EditableTaskRow> createState() => EditableTaskRowState();
}

class EditableTaskRowState extends State<EditableTaskRow> {
  bool _editing = false;
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.description);
  }

  @override
  void didUpdateWidget(EditableTaskRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.description != widget.description) {
      _controller.text = widget.description;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (_controller.text.trim().isNotEmpty) {
      widget.onEdit(_controller.text.trim());
    }
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Checkbox
          GestureDetector(
            onTap: widget.onToggle,
            child: Icon(
              widget.completed
                  ? Icons.check_box
                  : Icons.check_box_outline_blank,
              size: 16,
              color: widget.completed
                  ? AppColors.bondHighOf(context)
                  : widget.isCurrent
                  ? AppColors.taskAccentOf(context)
                  : AppColors.iconSecondary(context),
            ),
          ),
          const SizedBox(width: 6),

          // Description or edit field
          Expanded(
            child: _editing
                ? TextField(
                    controller: _controller,
                    autofocus: true,
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 11,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      filled: true,
                      fillColor: AppColors.surfaceContainerOf(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(
                          color: AppColors.taskAccentOf(context),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(
                          color: AppColors.taskAccentOf(context),
                        ),
                      ),
                    ),
                    onSubmitted: (_) => _save(),
                  )
                : GestureDetector(
                    onTap: widget.onToggle,
                    child: Text(
                      widget.description,
                      style: TextStyle(
                        fontSize: 11,
                        color: widget.completed
                            ? AppColors.textTertiary(context)
                            : widget.isCurrent
                            ? AppColors.textPrimary(context)
                            : AppColors.textSecondary(context),
                        decoration: widget.completed
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
          ),

          // Current task indicator
          if (widget.isCurrent && !_editing)
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Text(
                '◂',
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.taskAccentOf(context),
                ),
              ),
            ),

          const SizedBox(width: 4),

          // Edit / Save button
          if (_editing)
            GestureDetector(
              onTap: _save,
              child: Icon(
                Icons.check,
                size: 14,
                color: AppColors.bondHighOf(context),
              ),
            )
          else
            GestureDetector(
              onTap: () => setState(() => _editing = true),
              child: Icon(
                Icons.edit,
                size: 12,
                color: AppColors.iconSecondary(context),
              ),
            ),

          const SizedBox(width: 4),

          // Delete button
          GestureDetector(
            onTap: widget.onDelete,
            child: Icon(
              Icons.close,
              size: 12,
              color: AppColors.iconSecondary(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// A secondary objective ("side quest") row — goal text, task progress badge,
/// promote / clear buttons, and an expandable task list. AI-proposed side
/// quests come with auto-generated subtasks that drive the story, so the row
/// surfaces them (with the same editable task rows the primary quest uses)
/// instead of hiding them behind a bare text line.
class SecondaryObjectiveRow extends StatefulWidget {
  final ChatService chatService;
  final Objective objective;

  const SecondaryObjectiveRow({
    super.key,
    required this.chatService,
    required this.objective,
  });

  @override
  State<SecondaryObjectiveRow> createState() => _SecondaryObjectiveRowState();
}

class _SecondaryObjectiveRowState extends State<SecondaryObjectiveRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final obj = widget.objective;
    final tasks = widget.chatService.tasksForObjective(obj);
    final completedCount = tasks.where((t) => t['completed'] == true).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: tasks.isEmpty
                ? null
                : () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Icon(
                  tasks.isEmpty
                      ? Icons.circle_outlined
                      : _expanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: tasks.isEmpty ? 10 : 14,
                  color: AppColors.iconSecondary(context),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    obj.objective,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                ),
                if (tasks.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      '$completedCount/${tasks.length}',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textTertiary(context),
                      ),
                    ),
                  ),
                InkWell(
                  onTap: () => widget.chatService.promoteObjective(obj),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      Icons.keyboard_double_arrow_up,
                      size: 14,
                      color: AppColors.taskAccentOf(context),
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => widget.chatService.clearObjective(obj),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: AppColors.negativeAccentOf(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_expanded && tasks.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...tasks.asMap().entries.map((entry) {
              final i = entry.key;
              final task = entry.value;
              final completed = task['completed'] == true;
              final isCurrent =
                  !completed &&
                  tasks.take(i).every((t) => t['completed'] == true);
              return EditableTaskRow(
                key: ValueKey('side_task_${obj.id}_$i'),
                description: task['description'] as String,
                completed: completed,
                isCurrent: isCurrent,
                onToggle: () => widget.chatService.toggleTask(obj, i),
                onDelete: () => widget.chatService.removeTask(obj, i),
                onEdit: (newText) =>
                    widget.chatService.updateTask(obj, i, newText),
              );
            }),
          ],
        ],
      ),
    );
  }
}
