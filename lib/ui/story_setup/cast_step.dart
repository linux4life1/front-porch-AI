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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/story_setup/setup_widgets.dart';
import 'package:front_porch_ai/ui/story_setup/story_setup_draft.dart';
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// Step 2 of 4 (sketch J): characters from the library with a role chip
/// row each, "You in the story", and whether the chat is canon.
class CastStep extends StatelessWidget {
  final StorySetupDraft draft;
  final VoidCallback onChanged;

  const CastStep({super.key, required this.draft, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final chars = Provider.of<CharacterRepository>(context).characters;
    final persona = Provider.of<UserPersonaService>(context).persona;
    final picked = [
      for (final c in chars)
        if (c.dbId != null && draft.selectedCharacterIds.contains(c.dbId)) c,
    ];
    final chat = draft.chatSource;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StoryCard(
          children: [
            Row(
              children: [
                const Expanded(child: StoryKeyLabel('From your characters')),
                StoryButton(
                  'Add from library',
                  key: const ValueKey('story-add-cast'),
                  icon: Icons.add,
                  onPressed: () => _addFromLibrary(context, chars),
                ),
              ],
            ),
            if (picked.isEmpty)
              const SetupNote(
                'No one yet. Anyone you don\'t add here, the bible writes for '
                'you.',
              ),
            for (final c in picked)
              _CastRow(
                name: c.name,
                detail: chat?.characterId == c.dbId
                    ? 'From the chat · the card and the chat are canon'
                    : 'Library card',
                imagePath: c.imagePath,
                role: draft.characterRoles[c.dbId!] ?? 'Supporting',
                onRole: (r) {
                  draft.characterRoles[c.dbId!] = r;
                  onChanged();
                },
                onRemove: () {
                  draft.selectedCharacterIds.remove(c.dbId);
                  draft.characterRoles.remove(c.dbId);
                  if (chat?.characterId == c.dbId) draft.dropChat();
                  onChanged();
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        StoryCard(
          children: [
            StoryToggleRow(
              key: const ValueKey('story-persona'),
              value: draft.includeUserPersona,
              onChanged: (v) {
                draft.includeUserPersona = v;
                onChanged();
              },
              label: 'You in the story',
              detail: 'as your persona, ${persona.name}',
            ),
            if (draft.includeUserPersona)
              SetupChipRow(
                options: {for (final r in storyRoleOptions) r: r},
                selected: {draft.userPersonaRole},
                onToggle: (r, _) {
                  draft.userPersonaRole = r;
                  onChanged();
                },
              ),
          ],
        ),
        if (chat != null) ...[
          const SizedBox(height: 12),
          StoryCard(
            children: [
              StoryToggleRow(
                value: draft.useChatHistory,
                onChanged: (v) {
                  draft.useChatHistory = v;
                  onChanged();
                },
                label: 'Use the chat as canon',
                detail:
                    'The chat with ${chat.characterName} is distilled into a '
                    'timeline the bible must respect',
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        const SetupNote(
          'You can add or remove cast later from the Cast screen.',
        ),
      ],
    );
  }

  Future<void> _addFromLibrary(
    BuildContext context,
    List<CharacterCard> chars,
  ) async {
    final available = [
      for (final c in chars)
        if (c.dbId != null && !draft.selectedCharacterIds.contains(c.dbId)) c,
    ];
    final chosen = await showStoryDialog<CharacterCard>(
      context,
      title: 'Add from library',
      width: 460,
      body: available.isEmpty
          ? Text(
              'Every character is already in the cast.',
              style: StudioType.ui(
                context,
                size: 12.5,
                color: StudioColors.mutedOf(context),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final c in available)
                  InkWell(
                    key: ValueKey('story-library-${c.dbId}'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => Navigator.pop(context, c),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          StoryAvatar(c.name, imagePath: c.imagePath),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              c.name,
                              style: StudioType.ui(
                                context,
                                weight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
      actions: (ctx) => [
        StoryButton.ghost('Cancel', onPressed: () => Navigator.pop(ctx)),
      ],
    );
    if (chosen == null) return;
    draft.selectedCharacterIds.add(chosen.dbId!);
    draft.characterRoles[chosen.dbId!] =
        draft.characterRoles.values.any((r) => r == 'Protagonist')
        ? 'Supporting'
        : 'Protagonist';
    onChanged();
  }
}

class _CastRow extends StatelessWidget {
  final String name;
  final String detail;
  final String? imagePath;
  final String role;
  final ValueChanged<String> onRole;
  final VoidCallback onRemove;

  const _CastRow({
    required this.name,
    required this.detail,
    required this.imagePath,
    required this.role,
    required this.onRole,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      StoryAvatar(name, imagePath: imagePath),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: StudioType.ui(context, weight: FontWeight.w600)),
            Text(
              detail,
              style: StudioType.ui(
                context,
                size: 12,
                color: StudioColors.mutedOf(context),
              ),
            ),
            const SizedBox(height: 6),
            SetupChipRow(
              options: {for (final r in storyRoleOptions) r: r},
              selected: {role},
              onToggle: (r, _) => onRole(r),
            ),
          ],
        ),
      ),
      StoryIconButton(Icons.close, tooltip: 'Remove', onPressed: onRemove),
    ],
  );
}
