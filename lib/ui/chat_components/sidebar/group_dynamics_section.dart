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
import 'package:front_porch_ai/services/chat/chat.dart' show GroupDynamics;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/theme/tier_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import 'porch_accordion.dart';

/// Group Dynamics — read-only. How the focused member feels about each other
/// member of the group, on the same bond scale and bars as their feelings
/// toward you. One of the two group-only pieces of the sidebar (the other is
/// turn-taking); nothing here is editable.
///
/// Shows only in a group while Realism runs: the feelings keep moving while
/// you direct, and stay stored (but unshown) while Realism is off.
class GroupDynamicsSection extends StatelessWidget {
  const GroupDynamicsSection({
    super.key,
    required this.chat,
    required this.member,
    required this.initiallyExpanded,
    this.onExpansionChanged,
  });

  final ChatService chat;
  final CharacterCard member;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;

  /// Whether the section mounts for this chat and member.
  static bool visibleFor(ChatService chat, CharacterCard? member) =>
      chat.isGroupMode &&
      chat.realismEnabled &&
      member != null &&
      !member.isLite;

  /// The read for [member] off the live chat.
  static GroupDynamics readFor(ChatService chat, CharacterCard member) =>
      GroupDynamics.of(
        focused: member,
        roster: chat.groupCharacters,
        relationships:
            chat.getRealismStateForGroupCharacter(member)?['relationships']
                as Map<String, dynamic>?,
        idOf: chat.characterIdFor,
      );

  @override
  Widget build(BuildContext context) {
    final dynamics = readFor(chat, member);
    return PorchAccordion(
      id: 'group_dynamics',
      emoji: '🫂',
      title: 'Group Dynamics',
      subtitle: member.name,
      accent: AppColors.porchHoneyOf(context),
      initiallyExpanded: initiallyExpanded,
      onExpansionChanged: onExpansionChanged,
      child: !dynamics.tracked
          ? Text(
              'Feelings between characters are tracked in groups of two to '
              'four characters.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary(context),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "How ${member.name} feels about the others. Read-only.",
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary(context),
                  ),
                ),
                const SizedBox(height: 8),
                for (final f in dynamics.feelings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: RealismProgressRow(
                      key: ValueKey('group-dynamics-${f.memberId}'),
                      label: f.name,
                      value: f.score,
                      tier: f.tier,
                      tierName: f.tierName,
                      color: TierColors.tierColor(context, f.tier),
                      icon: f.score < 0 ? Icons.heart_broken : Icons.favorite,
                      progress: f.progress,
                      tooltip:
                          '${member.name} toward ${f.name}. Moves as they '
                          'talk and act around each other.',
                    ),
                  ),
              ],
            ),
    );
  }
}
