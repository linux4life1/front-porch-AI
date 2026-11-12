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

import 'package:front_porch_ai/ui/pages/edit_character_page/edit_character_form_kit.dart';
import 'package:front_porch_ai/ui/pages/edit_group/edit_group_draft.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/group_alternate_greetings_editor.dart';

/// Dialogue tab of the group editor: the 1:1 editor's three cards over the
/// group: First Message, Alternate Greetings (each with its opening seed)
/// and Example Dialogue.
class EditGroupDialogueTab extends StatelessWidget {
  const EditGroupDialogueTab({
    super.key,
    required this.draft,
    required this.onChanged,
  });

  final EditGroupDraft draft;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final kit = EditCharacterFormKit(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              kit.sectionCard(
                icon: Icons.chat_bubble_outline,
                title: 'First Message',
                color: AppColors.formAccentOf(context),
                children: [
                  kit.styledField(
                    controller: draft.firstMessage,
                    label: 'Opening Message',
                    maxLines: 6,
                    expandable: true,
                    hint:
                        "The group's opening line when a conversation starts...",
                  ),
                ],
              ),
              const SizedBox(height: 20),
              kit.sectionCard(
                icon: Icons.swap_horiz,
                title: 'Alternate Greetings',
                color: AppColors.porchHoneyOf(context),
                children: [
                  GroupAlternateGreetingsEditor(
                    greetings: draft.altGreetings,
                    seeds: draft.altGreetingSeeds,
                    showNeeds: true,
                    onChanged: (g, s) {
                      draft.altGreetings = g;
                      draft.altGreetingSeeds = s;
                      onChanged();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
              kit.sectionCard(
                icon: Icons.format_quote_outlined,
                title: 'Example Dialogue',
                color: AppColors.porchTerracottaOf(context),
                children: [
                  kit.styledField(
                    controller: draft.mesExample,
                    label: 'Example Conversations',
                    maxLines: 6,
                    expandable: true,
                    hint:
                        '<START>\n{{user}}: Hello!\n{{char}}: *smiles warmly*',
                  ),
                ],
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }
}
