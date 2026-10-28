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
import 'package:front_porch_ai/services/world_chain.dart';
import 'package:front_porch_ai/ui/pages/worlds/world_library_rows.dart';
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// "Where does it happen?": the library as a tree, roots with their places
/// indented, the starting place starred. Picking a root starts the story at
/// its starred place; picking a place inside starts it there. Resolves to
/// the chosen world, or null.
Future<World?> showStoryWorldPicker(
  BuildContext context, {
  required List<World> places,
}) {
  final rows = libraryDisplayOrder(places);
  final byId = {for (final w in places) w.id: w};
  final starts = {
    for (final w in rows)
      if (!w.isLocation) w.id: startingPlaceOf(w, (id) => byId[id]).id,
  };
  return showStoryDialog<World>(
    context,
    title: 'Where does it happen?',
    width: 520,
    body: rows.isEmpty
        ? Text(
            'No worlds in the library yet. Make one on the Worlds page, or '
            'add a starter world.',
            style: StudioType.ui(
              context,
              size: 12.5,
              color: StudioColors.mutedOf(context),
            ),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Pick a world, or a place inside one. The story starts there '
                'and reads the whole world.',
                style: StudioType.ui(
                  context,
                  size: 12.5,
                  color: StudioColors.mutedOf(context),
                ),
              ),
              const SizedBox(height: 8),
              for (final w in rows)
                _WorldPickRow(
                  world: w,
                  root: topWorldOf(w, (id) => byId[id]),
                  isStart: starts.values.contains(w.id),
                  startName: w.isLocation
                      ? null
                      : byId[starts[w.id]]?.name ?? w.name,
                  depth: worldChain(w, (id) => byId[id]).length - 1,
                  placeCount: w.isLocation
                      ? 0
                      : places.where((p) => p.parentWorldId != null).where((p) {
                          return topWorldOf(p, (id) => byId[id]).id == w.id;
                        }).length,
                  onPick: () => Navigator.pop(context, w),
                ),
            ],
          ),
    actions: (ctx) => [
      StoryButton.ghost('Cancel', onPressed: () => Navigator.pop(ctx)),
    ],
  );
}

class _WorldPickRow extends StatelessWidget {
  final World world;
  final World root;
  final bool isStart;
  final String? startName;
  final int depth;
  final int placeCount;
  final VoidCallback onPick;

  const _WorldPickRow({
    required this.world,
    required this.root,
    required this.isStart,
    required this.startName,
    required this.depth,
    required this.placeCount,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final muted = StudioColors.mutedOf(context);
    final facts = world.lorebook.enabledEntryCount;
    final isRoot = !world.isLocation;
    final detail = isRoot
        ? '$placeCount place${placeCount == 1 ? '' : 's'} · '
              '${facts == 0 ? 'no book' : '$facts fact${facts == 1 ? '' : 's'}'}'
        : 'inside ${root.name}${facts == 0 ? '' : ' · $facts fact${facts == 1 ? '' : 's'}'}';
    return InkWell(
      key: ValueKey('story-world-row-${world.id}'),
      onTap: onPick,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          10 + 22.0 * depth,
          isRoot ? 8 : 6,
          10,
          isRoot ? 8 : 6,
        ),
        child: Row(
          children: [
            if (isRoot)
              Icon(Icons.public, size: 18, color: StudioColors.honeyOf(context))
            else
              Icon(
                isStart ? Icons.star : Icons.star_border,
                size: 14,
                color: isStart
                    ? StudioColors.honeyOf(context)
                    : StudioColors.lineOf(context),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    world.name,
                    style: StudioType.ui(
                      context,
                      weight: isRoot ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  Text(
                    detail,
                    style: StudioType.ui(context, size: 12, color: muted),
                  ),
                ],
              ),
            ),
            if (isRoot && startName != null) ...[
              const SizedBox(width: 8),
              StoryChip('starts at $startName', tone: 'amber'),
            ],
          ],
        ),
      ),
    );
  }
}
