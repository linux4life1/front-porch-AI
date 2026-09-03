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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Shared field decoration for the Objectives panel's two text inputs (the
/// manual-task field and the add-goal field). Public because the field itself
/// moved out here while the manual-task field stayed behind in
/// ObjectivePanel — one decoration, two callers, rather than a copy each.
InputDecoration objectiveFieldDecoration(BuildContext context, String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: AppColors.textTertiary(context), fontSize: 11),
    filled: true,
    fillColor: AppColors.surfaceContainerOf(context),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
  );
}

/// The Objectives panel's footer: the add-goal field and its As Primary / As
/// Side buttons — plus, on a chat with no quest yet, the line of copy that
/// says what this box is now FOR.
///
/// Extracted from ObjectivePanel, which had reached exactly 500 lines (the
/// hard per-file cap) and could not grow to carry the empty-state copy.
///
/// The copy exists because "Current Task / Quest" was removed from the
/// character editor: a quest belongs to one conversation, not baked onto a
/// card forever. That was the right call, but it left the affordance with no
/// obvious new home — an author who used to type a starting quest on the card
/// now finds an unlabelled "Add new goal..." box below an empty Side Quests
/// region and no hint that this is where it went. The web PWA already framed
/// its empty state ("Set a goal for this character…"); desktop is the surface
/// catching up here, which inverts the usual parity direction.
///
/// Deliberately shown by "no quest yet" rather than "brand-new chat": there is
/// no fresh-chat flag on the service, `messages.isEmpty` is already false by
/// the time the sidebar first paints (the greeting is appended in the same
/// branch that seeds objectives), and scanning `chat.messages` in a build
/// would copy the whole list on every notify during streaming. "No primary and
/// no side quests" is the state the guidance is actually useful in, costs one
/// null check, and reads the same in 1:1 and group.
class ObjectiveAddGoal extends StatefulWidget {
  final ChatService chatService;

  const ObjectiveAddGoal({super.key, required this.chatService});

  @override
  State<ObjectiveAddGoal> createState() => _ObjectiveAddGoalState();
}

class _ObjectiveAddGoalState extends State<ObjectiveAddGoal> {
  final _goalController = TextEditingController();

  @override
  void dispose() {
    _goalController.dispose();
    super.dispose();
  }

  /// Shared submit path for the field and both buttons.
  Future<void> _submitGoal({required bool isPrimary}) async {
    final text = _goalController.text.trim();
    if (text.isEmpty) return;
    await widget.chatService.setObjective(text, isPrimary: isPrimary);
    _goalController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final chatService = widget.chatService;
    final hasNoQuest =
        chatService.primaryObjective == null &&
        chatService.secondaryObjectives.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        if (hasNoQuest) ...[
          Text(
            'STARTING QUEST',
            style: TextStyle(
              fontSize: 9,
              color: AppColors.taskAccentOf(context),
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Give them something to be working on, or leave it — they will '
            'propose their own goals as the story moves.',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.35,
              color: AppColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 6),
        ],
        AppTextField(
          controller: _goalController,
          style: TextStyle(color: AppColors.textPrimary(context), fontSize: 11),
          decoration: objectiveFieldDecoration(
            context,
            hasNoQuest ? 'Set a starting quest...' : 'Add new goal...',
          ),
          onSubmitted: (_) =>
              _submitGoal(isPrimary: chatService.primaryObjective == null),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: WrapAlignment.end,
          children: [
            ElevatedButton(
              onPressed: () => _submitGoal(isPrimary: true),
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
              onPressed:
                  chatService.secondaryObjectives.length >=
                      kMaxSecondaryObjectives
                  ? null
                  : () => _submitGoal(isPrimary: false),
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
  }
}
