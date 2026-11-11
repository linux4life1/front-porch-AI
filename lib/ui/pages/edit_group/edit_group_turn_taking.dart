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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/pages/edit_group/turn_taking/auto_advance_card.dart';
import 'package:front_porch_ai/ui/pages/edit_group/turn_taking/director_mode_section.dart';
import 'package:front_porch_ai/ui/pages/edit_group/turn_taking/turn_strategy_card.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The Details tab's turn-taking part: turn order, auto-advance and whether
/// the group starts in Director. The turn order and auto-advance apply to the
/// open chat when Save lands; Director here is only where a chat STARTS (the
/// live switch is in the chat's sidebar).
class EditGroupTurnTaking extends StatelessWidget {
  const EditGroupTurnTaking({
    super.key,
    required this.turnOrder,
    required this.autoAdvance,
    required this.directorMode,
    required this.onTurnOrderChanged,
    required this.onAutoAdvanceChanged,
    required this.onDirectorModeChanged,
  });

  final TurnOrder turnOrder;
  final bool autoAdvance;
  final bool directorMode;
  final ValueChanged<TurnOrder> onTurnOrderChanged;
  final ValueChanged<bool> onAutoAdvanceChanged;
  final ValueChanged<bool> onDirectorModeChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('edit-group-turn-taking'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Turn Order',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary(context),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: GroupTurnStrategyCard(
                isSelected: turnOrder == TurnOrder.roundRobin,
                label: 'Round Robin',
                onTap: () => onTurnOrderChanged(TurnOrder.roundRobin),
                description:
                    'Characters respond in a fixed repeating order. Predictable and fair.',
                icon: Icons.repeat,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GroupTurnStrategyCard(
                isSelected: turnOrder == TurnOrder.random,
                label: 'Random',
                onTap: () => onTurnOrderChanged(TurnOrder.random),
                description:
                    'Any eligible character may speak next. More spontaneous and lively.',
                icon: Icons.shuffle,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GroupAutoAdvanceCard(
          value: autoAdvance,
          onChanged: onAutoAdvanceChanged,
        ),
        const SizedBox(height: 12),
        GroupDirectorModeDefaultCard(
          value: directorMode,
          onChanged: onDirectorModeChanged,
        ),
      ],
    );
  }
}
