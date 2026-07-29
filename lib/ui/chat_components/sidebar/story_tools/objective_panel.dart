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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import '../sidebar_tokens.dart';
import 'objective_task_row.dart';

/// Objectives panel — primary quest, task generation/list, secondary
/// objectives, and the add-goal field. Lives in its own SidebarBody
/// accordion (collapsed by default); the accordion provides collapse.
class ObjectivePanel extends StatefulWidget {
  final ChatService chatService;
  const ObjectivePanel({super.key, required this.chatService});

  @override
  State<ObjectivePanel> createState() => _ObjectivePanelState();
}

class _ObjectivePanelState extends State<ObjectivePanel> {
  bool _generatingTasks = false;
  final _goalController = TextEditingController();
  final _manualTaskController = TextEditingController();

  @override
  void dispose() {
    _goalController.dispose();
    _manualTaskController.dispose();
    super.dispose();
  }

  /// Shared submit path for the add-goal field and its two buttons.
  Future<void> _submitGoal(
    ChatService chatService, {
    required bool isPrimary,
  }) async {
    final text = _goalController.text.trim();
    if (text.isEmpty) return;
    await chatService.setObjective(text, isPrimary: isPrimary);
    _goalController.clear();
  }

  /// Shared decoration for the manual-task and add-goal fields.
  InputDecoration _goalFieldDecoration(BuildContext context, String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: AppColors.textTertiary(context),
        fontSize: 11,
      ),
      filled: true,
      fillColor: AppColors.surfaceContainerOf(context),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatService>(
      builder: (context, chatService, _) {
        final pObj = chatService.primaryObjective;
        final secondaries = chatService.secondaryObjectives;

        final primaryTasks = pObj != null
            ? chatService.tasksForObjective(pObj)
            : [];
        final completedCount = primaryTasks
            .where((t) => t['completed'] == true)
            .length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            SidebarSubHeader(
              icon: Icons.flag,
              label: 'Objectives',
              accent: AppColors.porchHoneyOf(context),
              trailing: pObj != null
                  ? Text(
                      '$completedCount/${primaryTasks.length}',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textTertiary(context),
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 10),

            // Primary Objective Display
            if (pObj != null) ...[
              Text(
                'PRIMARY QUEST',
                style: TextStyle(
                  fontSize: 9,
                  color: AppColors.taskAccentOf(context),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.taskAccentOf(
                    context,
                  ).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: AppColors.taskAccentOf(
                      context,
                    ).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.star,
                      size: 14,
                      color: AppColors.taskAccentOf(context),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        pObj.objective,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textPrimary(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => chatService.clearObjective(pObj),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
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

              // NSFW toggle
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 14,
                    color: AppColors.iconSecondary(context),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'NSFW Tasks',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    height: 24,
                    child: Switch(
                      value: chatService.objectiveNsfwTasks,
                      activeThumbColor: AppColors.lustAccentOf(context),
                      onChanged: (v) =>
                          setState(() => chatService.objectiveNsfwTasks = v),
                    ),
                  ),
                ],
              ),

              if (primaryTasks.isEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _generatingTasks
                            ? null
                            : () async {
                                setState(() => _generatingTasks = true);
                                await chatService.generateObjectiveTasks(
                                  pObj,
                                  taskCount: chatService.objectiveTaskCount,
                                  nsfw: chatService.objectiveNsfwTasks,
                                );
                                if (mounted) {
                                  setState(() => _generatingTasks = false);
                                }
                              },
                        icon: _generatingTasks
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.textPrimary(context),
                                ),
                              )
                            : const Icon(Icons.auto_awesome, size: 14),
                        label: Text(
                          _generatingTasks ? 'Generating...' : 'Generate Tasks',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.surfaceContainerOf(
                            context,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerOf(context),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: DropdownButton<int>(
                        value: chatService.objectiveTaskCount,
                        underline: const SizedBox.shrink(),
                        dropdownColor: AppColors.surfaceContainerOf(context),
                        style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontSize: 12,
                        ),
                        isDense: true,
                        items: [3, 4, 5, 6, 7, 8, 10]
                            .map(
                              (n) => DropdownMenuItem(
                                value: n,
                                child: Text('$n'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => chatService.objectiveTaskCount = v ?? 5),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: _manualTaskController,
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 11,
                      ),
                      decoration: _goalFieldDecoration(
                        context,
                        'Add a task manually...',
                      ),
                      onSubmitted: (text) async {
                        if (text.trim().isEmpty) return;
                        await chatService.addManualTask(pObj, text);
                        _manualTaskController.clear();
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () async {
                      final text = _manualTaskController.text.trim();
                      if (text.isEmpty) return;
                      await chatService.addManualTask(pObj, text);
                      _manualTaskController.clear();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.add_circle_outline,
                        size: 18,
                        color: AppColors.taskAccentOf(context),
                      ),
                    ),
                  ),
                ],
              ),

              if (primaryTasks.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...primaryTasks.asMap().entries.map((entry) {
                  final i = entry.key;
                  final task = entry.value;
                  final completed = task['completed'] == true;
                  final isCurrent =
                      !completed &&
                      primaryTasks
                          .take(i)
                          .every((t) => t['completed'] == true);

                  return EditableTaskRow(
                    key: ValueKey('task_$i'),
                    description: task['description'] as String,
                    completed: completed,
                    isCurrent: isCurrent,
                    onToggle: () => chatService.toggleTask(pObj, i),
                    onDelete: () => chatService.removeTask(pObj, i),
                    onEdit: (newText) =>
                        chatService.updateTask(pObj, i, newText),
                  );
                }),

                const SizedBox(height: 8),
                // Two rows so a narrow sidebar never overflows (was fixed
                // 80px slider + labels + "Check now" → +13px overflow).
                Row(
                  children: [
                    Text(
                      'Check every',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 5,
                          ),
                          activeTrackColor: AppColors.textTertiary(context),
                          inactiveTrackColor: AppColors.borderOf(
                            context,
                          ).withValues(alpha: 0.2),
                          thumbColor: AppColors.textSecondary(context),
                          overlayShape: SliderComponentShape.noOverlay,
                        ),
                        child: Slider(
                          value: pObj.checkFrequency.toDouble(),
                          min: 1,
                          max: 10,
                          divisions: 9,
                          onChanged: (v) =>
                              chatService.updateCheckFrequency(pObj, v.round()),
                        ),
                      ),
                    ),
                    Text(
                      '${pObj.checkFrequency} msgs',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: chatService.isCheckingCompletion
                      ? Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: AppColors.bondHighOf(context),
                            ),
                          ),
                        )
                      : TextButton.icon(
                          onPressed: () => chatService.forceCheckCompletion(),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.bondHighOf(context),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 0,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.check_circle_outline, size: 12),
                          label: const Text(
                            'Check now',
                            style: TextStyle(fontSize: 10),
                          ),
                        ),
                ),
              ],
            ],

            // Secondary Objectives
            if (secondaries.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'SIDE QUESTS',
                style: TextStyle(
                  fontSize: 9,
                  color: AppColors.textSecondary(context),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              for (final sObj in secondaries)
                SecondaryObjectiveRow(
                  key: ValueKey(sObj.id),
                  chatService: chatService,
                  objective: sObj,
                ),
            ],

            const SizedBox(height: 12),

            // Add new objective — field full width; buttons wrap below on
            // narrow sidebars instead of overflowing.
            AppTextField(
              controller: _goalController,
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 11,
              ),
              decoration: _goalFieldDecoration(context, 'Add new goal...'),
              onSubmitted: (_) => _submitGoal(
                chatService,
                isPrimary: chatService.primaryObjective == null,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              children: [
                ElevatedButton(
                  onPressed: () => _submitGoal(chatService, isPrimary: true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.taskAccentOf(context),
                    foregroundColor: AppColors.onChaosAccent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 0,
                    ),
                    minimumSize: const Size(0, 28),
                    textStyle: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  child: const Text('As Primary'),
                ),
                ElevatedButton(
                  onPressed: () => _submitGoal(chatService, isPrimary: false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.surfaceContainerOf(context),
                    foregroundColor: AppColors.textPrimary(context),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 0,
                    ),
                    minimumSize: const Size(0, 28),
                    textStyle: const TextStyle(fontSize: 10),
                  ),
                  child: const Text('As Side'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
