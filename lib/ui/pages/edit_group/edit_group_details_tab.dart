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
import 'package:front_porch_ai/ui/pages/edit_group/edit_group_cast_cards.dart';
import 'package:front_porch_ai/ui/pages/edit_group/edit_group_draft.dart';
import 'package:front_porch_ai/ui/pages/edit_group/edit_group_prompt_cards.dart';
import 'package:front_porch_ai/ui/pages/edit_group/edit_group_realism_card.dart';

/// Details tab of the group editor: the 1:1 editor's cards, in the order of
/// docs/design/group-editor.md: Identity (with the cast), Turns, Voice,
/// Personality & World, Advanced Prompts, Tags, Realism Engine and Your
/// chats together.
class EditGroupDetailsTab extends StatelessWidget {
  const EditGroupDetailsTab({
    super.key,
    required this.groupId,
    required this.draft,
    required this.members,
    required this.onEditMember,
    required this.cast,
    required this.onChanged,
  });

  final String groupId;
  final EditGroupDraft draft;
  final List<CharacterCard> members;
  final void Function(CharacterCard member) onEditMember;
  final CastActions cast;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 20);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EditGroupIdentityCard(
                draft: draft,
                members: members,
                onEditMember: onEditMember,
                cast: cast,
                onChanged: onChanged,
              ),
              gap,
              EditGroupTurnsCard(draft: draft, onChanged: onChanged),
              gap,
              EditGroupVoiceCard(members: members),
              gap,
              EditGroupPersonalityCard(draft: draft),
              gap,
              EditGroupAdvancedPromptsCard(
                draft: draft,
                members: members,
                onChanged: onChanged,
              ),
              gap,
              EditGroupTagsCard(draft: draft, onChanged: onChanged),
              gap,
              EditGroupRealismCard(
                draft: draft,
                members: members,
                onChanged: onChanged,
              ),
              gap,
              EditGroupStatsCard(groupId: groupId),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }
}
