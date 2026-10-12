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
import 'package:front_porch_ai/ui/pages/story_structure/structure_board_actions.dart';
import 'package:front_porch_ai/ui/pages/story_structure/structure_scene_row.dart';
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// The board: act headers (raised, inline ✎), sequence headings in honey,
/// scene rows.
class StructureBoard extends StatelessWidget {
  final StoryProject project;
  final Set<int> openActs;
  final bool running;
  final StructureBoardActions actions;

  const StructureBoard({
    super.key,
    required this.project,
    required this.openActs,
    required this.running,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var a = 0; a < project.acts.length; a++) ...[
        if (a > 0) const SizedBox(height: 10),
        StructureAct(
          project: project,
          act: a,
          open: openActs.contains(a),
          running: running,
          actions: actions,
        ),
      ],
    ],
  );
}

/// One act: its header, then its scenes (grouped by sequence in Studio).
class StructureAct extends StatelessWidget {
  final StoryProject project;
  final int act;
  final bool open;
  final bool running;
  final StructureBoardActions actions;

  const StructureAct({
    super.key,
    required this.project,
    required this.act,
    required this.open,
    required this.running,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final p = project;
    final a = this.act;
    final act = p.acts[a];
    final scenes = p.scenes[a] ?? const <StoryScene>[];
    final written = [
      for (var i = 0; i < scenes.length; i++)
        if (p.beatsWritten(a, i) > 0) i,
    ].length;
    final studio = p.engineMode == StoryEngineMode.studio;
    final seqs = studio ? p.sequencesInAct(a) : const <StorySequence>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: ValueKey('story-act-$a'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => actions.onToggleAct(a, open),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: StudioColors.raiseOf(context),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Text('ACT ${romanAct(a + 1)}', style: StudioType.mono(context)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    act.title.isEmpty ? 'Untitled act' : act.title,
                    overflow: TextOverflow.ellipsis,
                    style: StudioType.ui(context, weight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 10),
                if (scenes.isEmpty) ...[
                  StoryButton.ghost(
                    'Generate act',
                    key: ValueKey('story-generate-act-$a'),
                    onPressed: running ? null : () => actions.onGenerateAct(a),
                  ),
                  const SizedBox(width: 6),
                  const StoryChip('No scenes yet'),
                ] else if (written == scenes.length)
                  StoryChip('✓ $written scenes written', tone: 'teal')
                else
                  StoryChip(
                    '$written of ${scenes.length} written',
                    tone: 'amber',
                  ),
                StoryIconButton(
                  Icons.edit_outlined,
                  tooltip: 'Edit act',
                  onPressed: () => actions.onEditAct(a),
                ),
                StoryIconButton(
                  open ? Icons.expand_less : Icons.expand_more,
                  tooltip: open ? 'Collapse' : 'Expand',
                  onPressed: () => actions.onToggleAct(a, open),
                ),
              ],
            ),
          ),
        ),
        if (open) ...[
          if (act.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
              child: Text(
                act.description,
                style: StudioType.ui(
                  context,
                  size: 12.5,
                  color: StudioColors.mutedOf(context),
                ),
              ),
            ),
          if (scenes.isEmpty && seqs.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Nothing planned for this act yet.',
                style: StudioType.ui(
                  context,
                  size: 12.5,
                  color: StudioColors.mutedOf(context),
                ),
              ),
            ),
          if (seqs.isEmpty)
            for (var i = 0; i < scenes.length; i++)
              StructureSceneRow(
                project: p,
                act: a,
                index: i,
                running: running,
                actions: actions,
              )
          else
            for (final seq in seqs)
              StructureSequence(
                project: p,
                act: a,
                sequence: seq,
                running: running,
                actions: actions,
              ),
        ],
      ],
    );
  }
}

/// A sequence heading in honey, then its scene rows.
class StructureSequence extends StatelessWidget {
  final StoryProject project;
  final int act;
  final StorySequence sequence;
  final bool running;
  final StructureBoardActions actions;

  const StructureSequence({
    super.key,
    required this.project,
    required this.act,
    required this.sequence,
    required this.running,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final p = project;
    final a = act;
    final seq = sequence;
    final indexes = p.sceneIndexesInSequence(seq.number);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
          child: Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Sequence ${seq.number}${seq.title.isEmpty ? '' : ' · ${seq.title}'}',
                style: StudioType.ui(
                  context,
                  weight: FontWeight.w600,
                  color: StudioColors.honeyOf(context),
                ),
              ),
              if (seq.dramaticQuestion.isNotEmpty)
                Text(
                  '“${seq.dramaticQuestion}”',
                  style: StudioType.ui(
                    context,
                    size: 12,
                    color: StudioColors.mutedOf(context),
                  ),
                ),
              if (indexes.isEmpty)
                StoryButton.ghost(
                  'Outline scenes',
                  key: ValueKey('story-outline-${seq.number}'),
                  onPressed: running
                      ? null
                      : () => actions.onPlanSequence(seq.number),
                ),
            ],
          ),
        ),
        for (final i in indexes)
          StructureSceneRow(
            project: p,
            act: a,
            index: i,
            running: running,
            actions: actions,
          ),
      ],
    );
  }
}
