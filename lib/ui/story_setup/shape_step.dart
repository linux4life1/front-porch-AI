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
import 'package:front_porch_ai/services/story/story.dart';
import 'package:front_porch_ai/ui/story_setup/setup_widgets.dart';
import 'package:front_porch_ai/ui/story_setup/story_setup_draft.dart';
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';

/// Step 3 of 4 (sketch K): length, format, voice, genre, mood, style, pace,
/// dialogue, maturity.
class ShapeStep extends StatelessWidget {
  final StorySetupDraft draft;
  final VoidCallback onChanged;

  const ShapeStep({super.key, required this.draft, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 760;
    final pacing = StoryPacing.forTarget(draft.targetWords);
    final length = StoryCard(
      children: [
        SetupField(
          label: 'Length',
          child: StorySegmented(
            key: const ValueKey('story-length'),
            options: storyLengthOptions,
            selected: draft.proseLength,
            onSelect: (v) {
              draft.proseLength = v;
              onChanged();
            },
          ),
        ),
        SetupNote(pacing.summary),
      ],
    );
    final format = StoryCard(
      children: [
        SetupField(
          label: 'Format',
          child: StorySegmented(
            key: const ValueKey('story-format'),
            options: const {'novel': 'Novel', 'audioDrama': 'Audio drama'},
            selected: draft.storyFormat.name,
            onSelect: (v) {
              draft.storyFormat = v == 'audioDrama'
                  ? StoryFormat.audioDrama
                  : StoryFormat.novel;
              onChanged();
            },
          ),
        ),
        const SetupNote(
          'Audio drama writes a voiced script for your cast voices.',
        ),
      ],
    );
    final pace = StoryCard(
      children: [
        SetupField(
          label: 'Pace',
          child: StorySegmented(
            options: storyPaceOptions,
            selected: draft.narrativePace,
            onSelect: (v) {
              draft.narrativePace = v;
              onChanged();
            },
          ),
        ),
      ],
    );
    final dialogue = StoryCard(
      children: [
        SetupField(
          label: 'Dialogue',
          child: StorySegmented(
            options: storyDialogueOptions,
            selected: draft.dialogueDensity,
            onSelect: (v) {
              draft.dialogueDensity = v;
              onChanged();
            },
          ),
        ),
      ],
    );
    final maturity = StoryCard(
      children: [
        SetupField(
          label: 'Maturity',
          child: StorySegmented(
            options: storyMaturityOptions,
            selected: draft.maturityRating,
            onSelect: (v) {
              draft.maturityRating = v;
              onChanged();
            },
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: length),
              const SizedBox(width: 12),
              Expanded(child: format),
            ],
          )
        else ...[
          length,
          const SizedBox(height: 12),
          format,
        ],
        const SizedBox(height: 12),
        StoryCard(
          children: [
            SetupField(
              label: 'Told from',
              child: SetupChipRow(
                options: storyPovOptions,
                selected: {draft.pov},
                onToggle: (v, _) {
                  draft.pov = v;
                  onChanged();
                },
              ),
            ),
            SetupField(
              label: 'Genre',
              hint: '(pick any)',
              child: SetupChipRow(
                multi: true,
                options: {for (final g in storyGenreOptions) g: g},
                selected: draft.selectedGenres,
                onToggle: (v, on) {
                  on
                      ? draft.selectedGenres.add(v)
                      : draft.selectedGenres.remove(v);
                  onChanged();
                },
              ),
            ),
            SetupField(
              label: 'Mood',
              hint: '(pick any)',
              child: SetupChipRow(
                multi: true,
                options: {for (final m in storyMoodOptions) m: m},
                selected: draft.selectedMoods,
                onToggle: (v, on) {
                  on
                      ? draft.selectedMoods.add(v)
                      : draft.selectedMoods.remove(v);
                  onChanged();
                },
              ),
            ),
            SetupField(
              label: 'Writing style',
              child: SetupChipRow(
                options: {for (final s in storyWritingStyles) s: s},
                selected: {draft.writingStyle},
                onToggle: (v, on) {
                  draft.writingStyle = on ? v : '';
                  onChanged();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: pace),
              const SizedBox(width: 10),
              Expanded(child: dialogue),
              const SizedBox(width: 10),
              Expanded(child: maturity),
            ],
          )
        else ...[
          pace,
          const SizedBox(height: 12),
          dialogue,
          const SizedBox(height: 12),
          maturity,
        ],
      ],
    );
  }
}
