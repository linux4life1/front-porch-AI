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
import 'package:front_porch_ai/ui/story_setup/model_picker_sheet.dart';
import 'package:front_porch_ai/ui/story_setup/setup_widgets.dart';
import 'package:front_porch_ai/ui/story_setup/story_setup_draft.dart';
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';

/// Step 4 of 4 (sketch L): Quick or Studio, who does which job, prompt
/// style. No engine card, no door into the chat's model dialog.
class EngineStep extends StatelessWidget {
  final StorySetupDraft draft;
  final VoidCallback onChanged;

  const EngineStep({super.key, required this.draft, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 760;
    final storage = Provider.of<StorageService>(context);
    final llm = Provider.of<LLMProvider>(context);
    final quick = draft.engineMode == StoryEngineMode.quick;
    final quickCard = StoryCard(
      key: ValueKey('story-engine-quick${quick ? '-on' : ''}'),
      selected: quick,
      raised: !quick,
      onTap: () => _mode(StoryEngineMode.quick),
      children: [
        Row(
          children: [
            Text(
              'Quick',
              style: StudioType.ui(context, weight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            const StoryChip('fewer calls'),
          ],
        ),
        const SetupNote(
          'Plans and writes in one pass. No reviewers. Good for a fast first '
          'draft.',
        ),
        Opacity(
          opacity: quick ? 1 : 0.5,
          child: Row(
            children: [
              const SetupNote('Acts'),
              const SizedBox(width: 10),
              StorySegmented(
                options: {for (var i = 1; i <= 5; i++) '$i': '$i'},
                selected: '${draft.actCount}',
                onSelect: quick
                    ? (v) {
                        draft.actCount = int.parse(v);
                        onChanged();
                      }
                    : (_) => _mode(StoryEngineMode.quick),
              ),
            ],
          ),
        ),
      ],
    );
    final studioCard = StoryCard(
      key: ValueKey('story-engine-studio${quick ? '' : '-on'}'),
      selected: !quick,
      raised: quick,
      onTap: () => _mode(StoryEngineMode.studio),
      children: [
        Row(
          children: [
            Text(
              'Studio',
              style: StudioType.ui(context, weight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            const StoryChip('recommended', tone: 'amber'),
          ],
        ),
        const SetupNote(
          'Interviews the cast, checks every step, tracks continuity and '
          'relationships. 3 acts, 8 sequences.',
        ),
        StoryToggleRow(
          value: draft.reviewEnabled,
          onChanged: quick
              ? null
              : (v) {
                  draft.reviewEnabled = v;
                  onChanged();
                },
          label: 'Check each step before moving on',
        ),
        StoryToggleRow(
          value: draft.lensesEnabled,
          onChanged: quick
              ? null
              : (v) {
                  draft.lensesEnabled = v;
                  onChanged();
                },
          label: 'A writing lens per scene',
        ),
      ],
    );
    final lanes = [
      ('Planning', 'planning', draft.planningLane),
      ('Prose', 'prose', draft.proseLane),
      ('Review', 'review', draft.reviewLane),
    ];
    final laneFields = [
      for (final (label, key, choice) in lanes)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SetupNote(label),
            const SizedBox(height: 4),
            StoryPickField(
              key: ValueKey('story-lane-$key'),
              value: storyLaneLabel(storage, llm, choice),
              onTap: () => _pick(context, label, choice),
            ),
          ],
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StoryCard(
          children: [
            const StoryKeyLabel('How should it write?'),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: quickCard),
                  const SizedBox(width: 12),
                  Expanded(child: studioCard),
                ],
              )
            else ...[
              quickCard,
              const SizedBox(height: 12),
              studioCard,
            ],
          ],
        ),
        const SizedBox(height: 12),
        StoryCard(
          children: [
            const StoryKeyLabel('Who does which job'),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < laneFields.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(child: laneFields[i]),
                  ],
                ],
              )
            else
              for (final f in laneFields) f,
            const SetupNote(
              'Planning plans and checks. Prose writes. Review reads '
              'planning\'s work and sends it back when it slips.',
            ),
            const SetupNote(
              'Review also checks every beat as it is written. A model that '
              'thinks before it answers can take a minute or more per check, '
              'which makes the whole story slow. A quick model suits this job.',
            ),
          ],
        ),
        const SizedBox(height: 12),
        StoryCard(
          children: [
            Row(
              children: [
                const Expanded(child: StoryKeyLabel('Prompt style')),
                StorySegmented(
                  options: {
                    for (final e in storyTierOptions.entries)
                      e.key.name: e.value,
                  },
                  selected: draft.tier.name,
                  onSelect: (v) {
                    draft.tier = PromptTier.values.firstWhere(
                      (t) => t.name == v,
                    );
                    onChanged();
                  },
                ),
              ],
            ),
            const SetupNote(
              'Full detail is written for frontier models. Rich trims for '
              'large local models; Simplified for small ones.',
            ),
          ],
        ),
      ],
    );
  }

  void _mode(StoryEngineMode m) {
    draft.engineMode = m;
    onChanged();
  }

  Future<void> _pick(
    BuildContext context,
    String job,
    StoryLaneChoice choice,
  ) async {
    final picked = await showModelPickerSheet(
      context,
      job: job,
      current: choice,
    );
    if (picked == null) return;
    choice
      ..lane = picked.lane
      ..backendType = picked.backendType
      ..apiUrl = picked.apiUrl
      ..model = picked.model
      ..kcpps = picked.kcpps;
    onChanged();
  }
}
