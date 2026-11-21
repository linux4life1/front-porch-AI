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
import 'package:front_porch_ai/ui/pages/edit_character_page/edit_character_form_kit.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page/editor_tags_field.dart';
import 'package:front_porch_ai/ui/pages/edit_group/edit_group_draft.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Details 4: Personality & World (Personality, Scenario).
class EditGroupPersonalityCard extends StatelessWidget {
  const EditGroupPersonalityCard({super.key, required this.draft});

  final EditGroupDraft draft;

  @override
  Widget build(BuildContext context) {
    final kit = EditCharacterFormKit(context);
    return kit.sectionCard(
      icon: Icons.psychology_outlined,
      title: 'Personality & World',
      color: AppColors.porchHoneyOf(context),
      children: [
        kit.styledField(
          controller: draft.personality,
          label: 'Personality',
          maxLines: 3,
          expandable: true,
          hint: 'How the group acts, speaks, thinks...',
        ),
        const SizedBox(height: 16),
        kit.styledField(
          controller: draft.scenario,
          label: 'Scenario',
          maxLines: 3,
          expandable: true,
          hint: 'The setting, situation, or context...',
        ),
      ],
    );
  }
}

/// Details 5: Advanced Prompts (collapsed): System Prompt, Post-History
/// Instructions, and per member the group system prompt, author's note and
/// strength (the same store as the member editor's "In the group").
class EditGroupAdvancedPromptsCard extends StatelessWidget {
  const EditGroupAdvancedPromptsCard({
    super.key,
    required this.draft,
    required this.members,
    required this.onChanged,
  });

  final EditGroupDraft draft;
  final List<CharacterCard> members;
  final VoidCallback onChanged;

  String _id(CharacterCard c) => c.dbId ?? c.name;

  @override
  Widget build(BuildContext context) {
    final kit = EditCharacterFormKit(context);
    return kit.sectionCard(
      icon: Icons.settings_suggest_outlined,
      title: 'Advanced Prompts',
      color: AppColors.textTertiary(context),
      collapsed: true,
      children: [
        kit.styledField(
          controller: draft.systemPrompt,
          label: 'System Prompt',
          maxLines: 4,
          expandable: true,
          hint: 'Custom system prompt for this group...',
        ),
        const SizedBox(height: 16),
        kit.styledField(
          controller: draft.postHistory,
          label: 'Post-History Instructions',
          maxLines: 3,
          expandable: true,
          hint: 'Injected after chat history (jailbreak/reminder)...',
        ),
        const SizedBox(height: 16),
        kit.fieldLabel('Per-character, in this group only (optional)'),
        const SizedBox(height: 8),
        for (final m in members) _member(context, kit, m),
      ],
    );
  }

  Widget _member(
    BuildContext context,
    EditCharacterFormKit kit,
    CharacterCard m,
  ) {
    final id = _id(m);
    final helper = TextStyle(
      color: AppColors.textTertiary(context),
      fontSize: 11,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            m.name,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: Key('group-prompt-$id'),
            controller: draft.promptOf(id),
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 14,
            ),
            decoration: kit.inputDecoration(
              'Group-only system prompt (blank uses ${m.name}\'s card)',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: Key('group-note-$id'),
            controller: draft.noteOf(id),
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 14,
            ),
            decoration: kit.inputDecoration(
              "Author's note (when ${m.name} speaks)",
            ),
          ),
          Row(
            children: [
              Text('Strength · ${draft.strengthOf(id)}', style: helper),
              Expanded(
                child: Slider(
                  key: Key('group-strength-$id'),
                  value: draft.strengthOf(id).toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  onChanged: (v) {
                    draft.strengths[id] = v.round();
                    onChanged();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Details 6: Tags, the 1:1 tag control.
class EditGroupTagsCard extends StatelessWidget {
  const EditGroupTagsCard({
    super.key,
    required this.draft,
    required this.onChanged,
  });

  final EditGroupDraft draft;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final kit = EditCharacterFormKit(context);
    return kit.sectionCard(
      icon: Icons.sell_outlined,
      title: 'Tags',
      color: AppColors.formAccentOf(context),
      children: [
        EditorTagsField(
          tags: draft.tags,
          controller: draft.tagController,
          onChanged: onChanged,
          showLabel: false,
        ),
      ],
    );
  }
}
