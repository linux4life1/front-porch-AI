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
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Dedicated, group-aware objectives manager.
///
/// Replaces the previous hack of swapping global `_activeObjectives` via
/// `focusObjectivesForGroupCharacter` + reusing the 1:1 `_ObjectiveSection`.
/// Each member keeps fully independent objectives; the dialog owns the
/// per-character scoping and never pollutes the global 1:1 list.
class GroupObjectivesDialog extends StatefulWidget {
  final ChatService chatService;
  final List<CharacterCard> groupCharacters;
  final CharacterCard? initialCharacter;

  const GroupObjectivesDialog({
    super.key,
    required this.chatService,
    required this.groupCharacters,
    this.initialCharacter,
  });

  @override
  State<GroupObjectivesDialog> createState() => _GroupObjectivesDialogState();
}

class _GroupObjectivesDialogState extends State<GroupObjectivesDialog> {
  late CharacterCard _focused;
  List<Objective> _objectives = [];
  bool _loading = true;

  bool _generatingTasks = false;
  bool _nsfw = false;
  int _taskCount = 5;
  final _goalController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _focused = widget.initialCharacter ?? widget.groupCharacters.first;
    _loadForCurrent();
  }

  @override
  void dispose() {
    _goalController.dispose();
    super.dispose();
  }

  Future<void> _loadForCurrent() async {
    setState(() => _loading = true);
    final list = await widget.chatService.getActiveObjectivesFor(_focused);
    if (mounted) {
      setState(() {
        _objectives = list;
        _loading = false;
      });
    }
  }

  Objective? get _primary =>
      _objectives.where((o) => o.isPrimary && o.active).firstOrNull;
  List<Objective> get _secondaries =>
      _objectives.where((o) => !o.isPrimary && o.active).toList();

  List<Map<String, dynamic>> _tasksFor(Objective obj) {
    try {
      return (jsonDecode(obj.tasks) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> _addObjective({required bool isPrimary}) async {
    final goal = _goalController.text.trim();
    if (goal.isEmpty) return;
    await widget.chatService.setObjective(
      goal,
      isPrimary: isPrimary,
      targetCharacter: _focused,
    );
    _goalController.clear();
    await _loadForCurrent();
  }

  Future<void> _generateTasks(Objective obj) async {
    setState(() => _generatingTasks = true);
    await widget.chatService.generateObjectiveTasks(
      obj,
      taskCount: _taskCount,
      nsfw: _nsfw,
    );
    await _loadForCurrent();
    if (mounted) setState(() => _generatingTasks = false);
  }

  Future<void> _toggleTask(Objective obj, int index) async {
    await widget.chatService.toggleTask(obj, index);
    await _loadForCurrent();
  }

  Future<void> _updateTask(Objective obj, int index, String newText) async {
    await widget.chatService.updateTask(obj, index, newText);
    await _loadForCurrent();
  }

  Future<void> _clearObjective(Objective obj) async {
    await widget.chatService.clearObjective(obj);
    await _loadForCurrent();
  }

  Future<void> _switchCharacter(CharacterCard ch) async {
    if (ch.name == _focused.name) return;
    setState(() {
      _focused = ch;
      _loading = true;
    });
    await _loadForCurrent();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surfaceOf(context),
      child: SizedBox(
        width: 520,
        height: 620,
        child: Column(
          children: [
            // Header with character switcher
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.flag, color: Colors.amber),
                  const SizedBox(width: 8),
                  Text(
                    'Group Objectives',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Character selector (compact horizontal)
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                itemCount: widget.groupCharacters.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  final ch = widget.groupCharacters[i];
                  final selected = ch.name == _focused.name;
                  return GestureDetector(
                    onTap: () => _switchCharacter(ch),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected
                                  ? Colors.amber
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 20,
                            backgroundImage: ch.imagePath != null
                                ? FileImage(
                                    File(ch.imagePath!),
                                  ) // safe in context of app
                                : null,
                            child: ch.imagePath == null
                                ? Text(ch.name[0])
                                : null,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ch.name.length > 12
                              ? '${ch.name.substring(0, 10)}…'
                              : ch.name,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: selected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: selected
                                ? Colors.amber
                                : AppColors.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            const Divider(height: 1),

            // Main editor area for the focused character
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Primary
                          Text(
                            'Primary Objective',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (_primary != null) ...[
                            _buildObjectiveCard(_primary!, isPrimary: true),
                          ] else ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.cardOf(context),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppColors.borderOf(
                                    context,
                                  ).withValues(alpha: 0.2),
                                ),
                              ),
                              child: const Text(
                                'No primary objective set.',
                                style: TextStyle(fontStyle: FontStyle.italic),
                              ),
                            ),
                          ],

                          const SizedBox(height: 16),

                          // Secondaries
                          Row(
                            children: [
                              Text(
                                'Secondary Objectives',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textSecondary(context),
                                ),
                              ),
                              const Spacer(),
                              if (_secondaries.length < 2)
                                TextButton.icon(
                                  onPressed: () =>
                                      _showAddDialog(isPrimary: false),
                                  icon: const Icon(Icons.add, size: 16),
                                  label: const Text(
                                    'Add',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (_secondaries.isEmpty)
                            const Text(
                              'None set.',
                              style: TextStyle(
                                fontStyle: FontStyle.italic,
                                fontSize: 12,
                              ),
                            )
                          else
                            ..._secondaries.map(
                              (s) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: _buildObjectiveCard(s, isPrimary: false),
                              ),
                            ),

                          const SizedBox(height: 20),

                          // Add new
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.cardOf(context),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'New Objective',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _goalController,
                                  decoration: const InputDecoration(
                                    hintText: 'Describe the goal...',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  onSubmitted: (_) => _addObjective(
                                    isPrimary: _primary == null,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    ElevatedButton(
                                      onPressed: () => _addObjective(
                                        isPrimary: _primary == null,
                                      ),
                                      child: const Text('Add'),
                                    ),
                                    const SizedBox(width: 12),
                                    TextButton(
                                      onPressed: () => _showGenerateDialog(),
                                      child: const Text('Generate with AI'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),

            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

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
                    final controller = TextEditingController(
                      text: t['description'],
                    );
                    final newText = await showDialog<String>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Edit task'),
                        content: TextField(
                          controller: controller,
                          autofocus: true,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(ctx, controller.text),
                            child: const Text('Save'),
                          ),
                        ],
                      ),
                    );
                    if (newText != null && newText.trim().isNotEmpty) {
                      await _updateTask(obj, i, newText.trim());
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

  void _showAddDialog({required bool isPrimary}) {
    showDialog(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: Text(
            isPrimary ? 'New Primary Objective' : 'New Secondary Objective',
          ),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Goal description'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final g = ctrl.text.trim();
                if (g.isNotEmpty) {
                  Navigator.pop(ctx);
                  await widget.chatService.setObjective(
                    g,
                    isPrimary: isPrimary,
                    targetCharacter: _focused,
                  );
                  await _loadForCurrent();
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
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
                if (_secondaries.length < 2) {
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
