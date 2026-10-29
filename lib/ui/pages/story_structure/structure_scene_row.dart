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
import 'package:front_porch_ai/ui/pages/story_structure/structure_board_actions.dart';
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// One scene row per the spec (number · lens · title/detail · tension ·
/// type · status · ⋯).
class StructureSceneRow extends StatelessWidget {
  final StoryProject project;
  final int act;
  final int index;
  final bool running;
  final StructureBoardActions actions;

  const StructureSceneRow({
    super.key,
    required this.project,
    required this.act,
    required this.index,
    required this.running,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final p = project;
    final a = act;
    final i = index;
    final sc = p.scenes[a]![i];
    final beats = p.beats[StoryProjectShape.sceneKey(a, i)] ?? const [];
    final written = p.beatsWritten(a, i);
    final studio = p.engineMode == StoryEngineMode.studio;
    final isNext = beats.isEmpty || written < beats.length
        ? isFirstUnfinishedScene(p, a, i)
        : false;
    final detail = [
      if (sc.castNames.isNotEmpty) sc.castNames.join(', '),
      if (sc.location.isNotEmpty) sc.location,
      if (sc.valueFrom.isNotEmpty || sc.valueTo.isNotEmpty)
        '${sc.valueFrom} → ${sc.valueTo}',
    ].join(' · ');
    final Widget status = beats.isEmpty
        ? const StoryChip('Not planned')
        : written == 0
        ? StoryChip('${beats.length} beats planned', tone: 'amber')
        : written < beats.length
        ? StoryChip('$written of ${beats.length} written', tone: 'amber')
        : const StoryChip('Written', tone: 'teal');
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: InkWell(
        key: ValueKey('story-scene-$a-$i'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => actions.onOpenScene(a, i),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: StudioColors.cardOf(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isNext
                  ? StudioColors.amberOf(context)
                  : StudioColors.lineOf(context),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  p.sceneLabel(a, i),
                  style: StudioType.mono(context),
                ),
              ),
              if (studio && p.lensesEnabled) ...[
                StoryLensMark(sc.lens),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sc.title.isEmpty ? 'Untitled scene' : sc.title,
                      overflow: TextOverflow.ellipsis,
                      style: StudioType.ui(context, weight: FontWeight.w600),
                    ),
                    if (detail.isNotEmpty)
                      _SceneDetail(
                        detail: detail,
                        newPlaceKey: storySceneIsNewPlace(p, sc)
                            ? ValueKey('story-scene-new-place-$a-$i')
                            : null,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (studio) ...[
                StoryTensionBars(sc.tension),
                const SizedBox(width: 10),
                if (sc.sceneType.isNotEmpty) ...[
                  StoryChip(
                    sc.sceneType[0].toUpperCase() + sc.sceneType.substring(1),
                  ),
                  const SizedBox(width: 10),
                ],
              ],
              status,
              StoryMenuButton(
                key: ValueKey('story-scene-menu-$a-$i'),
                entries: [
                  StoryMenuEntry(
                    'Write this scene',
                    enabled: !running,
                    onSelect: () => actions.onWriteScene(a, i),
                  ),
                  StoryMenuEntry(
                    beats.isEmpty ? 'Plan beats' : 'Plan beats again…',
                    enabled: !running,
                    onSelect: () => actions.onPlanBeats(a, i),
                  ),
                  StoryMenuEntry(
                    'Edit title & summary…',
                    onSelect: () => actions.onEditScene(a, i),
                  ),
                  StoryMenuEntry(
                    'Insert scene after…',
                    divider: true,
                    enabled: !running,
                    onSelect: () => actions.onInsertAfter(a, i),
                  ),
                  StoryMenuEntry(
                    'Rewrite prose…',
                    enabled: !running && written > 0,
                    onSelect: () => actions.onRewriteScene(a, i),
                  ),
                  StoryMenuEntry(
                    'Delete scene…',
                    danger: true,
                    enabled: !running,
                    onSelect: () => actions.onDeleteScene(a, i),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Whether scene [i] of act [a] is the first unfinished one in story order.
bool isFirstUnfinishedScene(StoryProject p, int a, int i) {
  for (final ref in p.orderedScenes) {
    final count =
        p.beats[StoryProjectShape.sceneKey(ref.act, ref.index)]?.length ?? 0;
    if (count == 0 || p.beatsWritten(ref.act, ref.index) < count) {
      return ref.act == a && ref.index == i;
    }
  }
  return false;
}

/// The scene's cast, place and value line, with the "new place" chip beside
/// it while the row is wide enough and on its own line beneath it when not,
/// so a phone-width window neither overflows nor hides the chip (the PWA's
/// `.s-scene .d-row` wraps the same way).
class _SceneDetail extends StatelessWidget {
  const _SceneDetail({required this.detail, required this.newPlaceKey});

  final String detail;

  /// Null when the scene's place is known: no chip.
  final Key? newPlaceKey;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      detail,
      overflow: TextOverflow.ellipsis,
      style: StudioType.ui(
        context,
        size: 12,
        color: StudioColors.mutedOf(context),
      ),
    );
    final key = newPlaceKey;
    if (key == null) return text;
    final chip = StoryChip('new place', key: key, tone: 'honey');
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 210) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              text,
              const SizedBox(height: 4),
              // At phone width the row's right-hand chips leave this column
              // narrower than the chip itself; scale it down to fit.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: chip,
              ),
            ],
          );
        }
        return Row(
          children: [
            Flexible(child: text),
            const SizedBox(width: 6),
            chip,
          ],
        );
      },
    );
  }
}
