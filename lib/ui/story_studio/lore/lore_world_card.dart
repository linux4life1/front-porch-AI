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
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/ui/story_studio/story_world_lookup.dart';
import 'package:front_porch_ai/ui/story_studio/studio_buttons.dart';
import 'package:front_porch_ai/ui/story_studio/studio_cards.dart';
import 'package:front_porch_ai/ui/story_studio/studio_theme.dart';
import 'package:front_porch_ai/ui/story_studio/studio_widgets.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// The Lore tab's header for a story set in a world
/// (docs/design/stories-in-worlds.md §5): which world, how many of its
/// facts the story holds, Refresh from world, Detach. [busy] disables both
/// while a save is in flight so a double tap writes once.
class LoreWorldCard extends StatelessWidget {
  final StoryProject project;
  final WorldRepository? worlds;
  final bool busy;
  final VoidCallback onRefresh;
  final VoidCallback onDetach;

  const LoreWorldCard({
    super.key,
    required this.project,
    required this.worlds,
    required this.busy,
    required this.onRefresh,
    required this.onDetach,
  });

  @override
  Widget build(BuildContext context) {
    final p = project;
    final line = storyWorldLine(p, worlds) ?? 'Set in a world';
    final copied = p.lore.where(isWorldLore).length;
    final brief = storyWorldBrief(p, worlds);
    final gone = brief != null && brief.isEmpty && !(worlds?.isLoading ?? true);
    return StoryCard(
      key: const ValueKey('lore-world-card'),
      raised: true,
      children: [
        // Matches the PWA card: under about 600 px the text keeps its own
        // line and the two buttons wrap beneath it, instead of squeezing the
        // text into a column a word wide.
        LayoutBuilder(
          builder: (context, constraints) {
            final text = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line,
                  style: StudioType.ui(context, weight: FontWeight.w600),
                ),
                Text(
                  '$copied fact${copied == 1 ? '' : 's'} from this world · '
                  'the world is read live; its facts were copied when the '
                  'bible was built',
                  style: StudioType.ui(
                    context,
                    size: 12,
                    color: StudioColors.mutedOf(context),
                  ),
                ),
              ],
            );
            final buttons = [
              StoryButton(
                'Refresh from world',
                key: const ValueKey('lore-world-refresh'),
                icon: Icons.refresh,
                onPressed: busy || gone ? null : onRefresh,
              ),
              StoryButton.danger(
                'Detach',
                key: const ValueKey('lore-world-detach'),
                onPressed: busy ? null : onDetach,
              ),
            ];
            final head = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.public, color: StudioColors.honeyOf(context)),
                const SizedBox(width: 10),
                Expanded(child: text),
              ],
            );
            if (constraints.maxWidth < 600) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  head,
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: buttons),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: head),
                const SizedBox(width: 8),
                buttons[0],
                const SizedBox(width: 8),
                buttons[1],
              ],
            );
          },
        ),
      ],
    );
  }
}

/// The chips that say where a lore entry came from: an uploaded file, the
/// story's world, and the place inside it that owns the entry.
List<Widget> loreSourceChips(
  BuildContext context,
  StoryProject p,
  StoryLoreEntry entry,
  WorldRepository? worlds,
) {
  final chips = <Widget>[];
  final worldName = p.worldName.trim().isEmpty
      ? 'the world'
      : p.worldName.trim();
  var fromWorld = false;
  for (final r in entry.relatedTo) {
    if (r.startsWith('file:')) {
      chips.add(StoryChip(r.substring(5), icon: Icons.description_outlined));
    } else if (r.startsWith('world:')) {
      fromWorld = true;
    }
  }
  if (!fromWorld) return chips;
  chips.add(StoryChip('from $worldName', tone: 'honey', icon: Icons.public));
  for (final r in entry.relatedTo) {
    if (!r.startsWith('place:')) continue;
    final place = worlds?.worldById(r.substring(6));
    if (place == null || !place.isLocation) continue;
    chips.add(StoryChip(place.name.trim()));
  }
  return chips;
}
