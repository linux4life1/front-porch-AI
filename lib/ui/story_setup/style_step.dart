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
// but WITHOUT ANY WARRANTY, without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/story_setup/setup_widgets.dart';
import 'package:front_porch_ai/ui/story_setup/story_setup_draft.dart';

/// Wizard step: the story's voice — point of view, genres, moods, and prose
/// style.
class StyleStep extends StatelessWidget {
  final StorySetupDraft draft;
  final VoidCallback onChanged;

  const StyleStep({super.key, required this.draft, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SetupSectionHeader(
          'Point of View',
          Icons.visibility,
          subtitle: 'Choose who narrates the story',
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: storyPovOptions
              .map(
                (pov) => SetupRadioChip(
                  pov,
                  selected: draft.pov == pov,
                  onTap: () {
                    draft.pov = pov;
                    onChanged();
                  },
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 28),
        const SetupSectionHeader(
          'Genre',
          Icons.category,
          subtitle: 'Select one or more genres to blend',
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: storyGenreOptions
              .map(
                (g) => SetupChip(
                  g,
                  selected: draft.selectedGenres.contains(g),
                  onTap: () {
                    if (!draft.selectedGenres.remove(g)) {
                      draft.selectedGenres.add(g);
                    }
                    onChanged();
                  },
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 28),
        const SetupSectionHeader(
          'Mood',
          Icons.palette,
          subtitle: 'Set the emotional atmosphere',
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: storyMoodOptions
              .map(
                (m) => SetupChip(
                  m,
                  selected: draft.selectedMoods.contains(m),
                  onTap: () {
                    if (!draft.selectedMoods.remove(m)) {
                      draft.selectedMoods.add(m);
                    }
                    onChanged();
                  },
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 28),
        const SetupSectionHeader(
          'Writing Style',
          Icons.brush,
          subtitle: 'Optional — tap again to clear',
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: storyWritingStyles
              .map(
                (s) => SetupRadioChip(
                  s,
                  selected: draft.writingStyle == s,
                  onTap: () {
                    draft.writingStyle = draft.writingStyle == s ? '' : s;
                    onChanged();
                  },
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
