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
import 'package:front_porch_ai/ui/story_setup/story_setup_draft.dart';
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// "Your story so far": the summary rail beside the steps (sketch I), or
/// the phone's final "Ready?" page when [asPage].
class SetupRail extends StatelessWidget {
  final StorySetupDraft draft;
  final int step;
  final bool asPage;

  const SetupRail({
    super.key,
    required this.draft,
    required this.step,
    this.asPage = false,
  });

  @override
  Widget build(BuildContext context) {
    final chars = Provider.of<CharacterRepository>(context).characters;
    final persona = Provider.of<UserPersonaService>(context).persona;
    final storage = Provider.of<StorageService>(context);
    final llm = Provider.of<LLMProvider>(context);
    String? idea = draft.conceptController.text.trim();
    if (idea.isEmpty) idea = null;
    final castNames = [
      for (final c in chars)
        if (c.dbId != null && draft.selectedCharacterIds.contains(c.dbId))
          '${c.name} (${(draft.characterRoles[c.dbId!] ?? 'Supporting').toLowerCase()})',
      if (draft.includeUserPersona)
        'you as ${persona.name} (${draft.userPersonaRole.toLowerCase()})',
    ];
    final shape = [
      storyLengthOptions[draft.proseLength] ?? draft.proseLength,
      draft.storyFormat == StoryFormat.audioDrama ? 'audio drama' : 'novel',
      (storyPovOptions[draft.pov] ?? draft.pov).toLowerCase(),
      if (draft.selectedGenres.isNotEmpty)
        draft.selectedGenres.join(', ').toLowerCase(),
      if (draft.selectedMoods.isNotEmpty)
        draft.selectedMoods.join(', ').toLowerCase(),
      if (draft.writingStyle.isNotEmpty) draft.writingStyle.toLowerCase(),
    ].join(' · ');
    String short(StoryLaneChoice c) {
      final label = storyLaneLabel(storage, llm, c);
      return label.split(' · ').last;
    }

    final engine = [
      draft.engineMode == StoryEngineMode.studio ? 'Studio' : 'Quick',
      if (draft.engineMode == StoryEngineMode.studio) ...[
        'checks ${draft.reviewEnabled ? 'on' : 'off'}',
        'lenses ${draft.lensesEnabled ? 'on' : 'off'}',
      ] else
        '${draft.actCount} acts',
      '${short(draft.planningLane)} / ${short(draft.proseLane)} / ${short(draft.reviewLane)}',
    ].join(' · ');
    final rows = <(String, String?, int)>[
      (
        'Title',
        draft.titleController.text.trim().isEmpty
            ? null
            : draft.titleController.text.trim(),
        0,
      ),
      ('Idea', idea, 0),
      if (draft.chatSource != null)
        (
          'From chat',
          '${draft.chatSource!.characterName} · ${draft.chatSource!.faithful ? 'faithful' : 'inspired by'}',
          0,
        ),
      ('Cast', castNames.isEmpty ? null : castNames.join(', '), 1),
      ('Shape', step >= 2 ? shape : null, 2),
      ('Engine', step >= 3 ? engine : null, 3),
    ];
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StoryKeyLabel(asPage ? 'Ready?' : 'Your story so far'),
        const SizedBox(height: 4),
        for (final (k, v, at) in rows) ...[
          const SizedBox(height: 8),
          Text(k.toUpperCase(), style: StudioType.label(context)),
          const SizedBox(height: 2),
          Text(
            v ??
                switch (k) {
                  'Title' => 'Suggested later',
                  'Cast' => step > 1 ? 'The bible invents the cast' : 'Step 2',
                  _ => 'Step ${at + 1}',
                },
            maxLines: asPage ? null : 3,
            overflow: asPage ? null : TextOverflow.ellipsis,
            style: StudioType.ui(
              context,
              size: 12.5,
              color: v == null
                  ? StudioColors.faintOf(context)
                  : StudioColors.inkOf(context),
            ),
          ),
        ],
        if (step >= 3) ...[
          const SizedBox(height: 12),
          Text(
            draft.engineMode == StoryEngineMode.studio
                ? 'Build the bible takes a few minutes with Studio. You can '
                      'keep using the app.'
                : 'Build the bible takes a minute or two.',
            style: StudioType.ui(
              context,
              size: 12,
              color: StudioColors.faintOf(context),
            ),
          ),
        ],
      ],
    );
    if (asPage) return StoryCard(children: [body]);
    return Container(
      width: 250,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      decoration: BoxDecoration(
        color: StudioColors.sideOf(context),
        border: Border(left: BorderSide(color: StudioColors.lineOf(context))),
      ),
      child: SingleChildScrollView(child: body),
    );
  }
}
