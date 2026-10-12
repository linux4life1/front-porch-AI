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
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// The "Phrases to avoid" card (always shown, so a first phrase can be
/// added).
class StoryBannedPhrasesCard extends StatelessWidget {
  final StoryProject project;
  final VoidCallback onEdit;

  const StoryBannedPhrasesCard({
    super.key,
    required this.project,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final auto = project.autoBannedPhrases;
    final own = project.bannedPhrases;
    final all = [...own, ...auto];
    return StoryCard(
      key: const ValueKey('story-banned'),
      children: [
        Row(
          children: [
            const Expanded(child: StoryKeyLabel('Phrases to avoid')),
            StoryButton.ghost('Edit list', onPressed: onEdit),
          ],
        ),
        if (all.isEmpty)
          Text(
            'None yet. The engine adds phrases it notices itself repeating; '
            'add your own with Edit list.',
            style: StudioType.ui(
              context,
              size: 12,
              color: StudioColors.mutedOf(context),
            ),
          )
        else ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in all.take(10)) StoryChip('“$p”'),
              if (all.length > 10) StoryChip('+ ${all.length - 10} more'),
            ],
          ),
          Text(
            [
              if (auto.isNotEmpty)
                '${auto.length} of these ${auto.length == 1 ? 'was' : 'were'} '
                    'noticed by the engine in the last chapter',
              if (own.isNotEmpty)
                '${auto.isNotEmpty ? 'the rest are' : 'These are'} yours and '
                    'stay for the whole story',
            ].join('; '),
            style: StudioType.ui(
              context,
              size: 12,
              color: StudioColors.mutedOf(context),
            ),
          ),
        ],
      ],
    );
  }
}
