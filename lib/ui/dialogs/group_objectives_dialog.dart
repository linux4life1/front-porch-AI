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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import 'group_objectives/group_objectives.dart';
import 'package:front_porch_ai/utils/utils.dart';

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
  final _generation = ObjectiveGenerationSettings();
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
      taskCount: _generation.taskCount,
      nsfw: _generation.nsfw,
    );
    await _loadForCurrent();
    if (mounted) setState(() => _generatingTasks = false);
  }

  Future<void> _promoteObjective(Objective obj) async {
    // Promote IN PLACE (keeps id + task progress; the old
    // setObjective-with-same-text pattern inserted a duplicate
    // primary and left this side quest active).
    await widget.chatService.promoteObjective(obj);
    await _loadForCurrent();
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

  Future<void> _showAddDialog({required bool isPrimary}) async {
    final goal = await promptForObjectiveText(
      context,
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
    showGenerateObjectivesDialog(
      context,
      settings: _generation,
      onGenerate: _generateObjectives,
    );
  }

  Future<void> _generateObjectives() async {
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
        taskCount: _generation.taskCount,
        nsfw: _generation.nsfw,
      );
    }
    await _loadForCurrent();
  }

  Widget _buildObjectiveCard(Objective obj, {required bool isPrimary}) {
    return GroupObjectiveCard(
      objective: obj,
      isPrimary: isPrimary,
      generatingTasks: _generatingTasks,
      onDelete: () => _clearObjective(obj),
      onToggleTask: (i) => _toggleTask(obj, i),
      onEditTask: (i, newText) => _updateTask(obj, i, newText),
      onRegenerateTasks: () => _generateTasks(obj),
      onPromote: () => _promoteObjective(obj),
    );
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
                  Icon(Icons.flag, color: AccentColors.goldOf(context)),
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
                                  ? AccentColors.goldOf(context)
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          // A character made without a portrait shows its
                          // initial, not its flat card colour.
                          child: RealPortrait(
                            file: ch.imagePath != null
                                ? File(ch.imagePath!)
                                : null,
                            portrait: (_, file) => CircleAvatar(
                              radius: 20,
                              backgroundImage: portraitAvatarImage(file),
                            ),
                            noPortrait: (_) => CircleAvatar(
                              radius: 20,
                              backgroundColor: AppColors.surfaceContainerOf(
                                context,
                              ),
                              child: Text(
                                ch.name[0],
                                style: TextStyle(
                                  color: AppColors.textSecondary(context),
                                ),
                              ),
                            ),
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
                                ? AccentColors.goldOf(context)
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
                              if (_secondaries.length < kMaxSecondaryObjectives)
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
}
