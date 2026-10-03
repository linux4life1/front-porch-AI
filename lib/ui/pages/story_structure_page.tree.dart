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

part of 'story_structure_page.dart';

/// The board: act headers (raised, inline ✎), sequence headings in honey,
/// scene rows per the spec (number · lens · title/detail · tension · type ·
/// status · ⋯).
extension _StoryStructureTree on _StoryStructurePageState {
  Widget _buildStructureTree(
    StoryProject project,
    StoryPipelineService pipeline,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var a = 0; a < project.acts.length; a++) ...[
        if (a > 0) const SizedBox(height: 10),
        _buildAct(project, a, pipeline),
      ],
    ],
  );

  Widget _buildAct(StoryProject p, int a, StoryPipelineService pipeline) {
    final act = p.acts[a];
    final scenes = p.scenes[a] ?? const <StoryScene>[];
    final written = [
      for (var i = 0; i < scenes.length; i++)
        if (p.beatsWritten(a, i) > 0) i,
    ].length;
    final open = _open.contains(a);
    final studio = p.engineMode == StoryEngineMode.studio;
    final seqs = studio ? p.sequencesInAct(a) : const <StorySequence>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: ValueKey('story-act-$a'),
          borderRadius: BorderRadius.circular(8),
          onTap: () =>
              rebuildState(() => open ? _open.remove(a) : _open.add(a)),
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
                    onPressed: pipeline.isRunning
                        ? null
                        : () => _generateFullAct(p, a, pipeline),
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
                  onPressed: () => _editAct(p, a),
                ),
                StoryIconButton(
                  open ? Icons.expand_less : Icons.expand_more,
                  tooltip: open ? 'Collapse' : 'Expand',
                  onPressed: () =>
                      rebuildState(() => open ? _open.remove(a) : _open.add(a)),
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
              _buildSceneRow(p, a, i, pipeline)
          else
            for (final seq in seqs) _buildSequence(p, a, seq, pipeline),
        ],
      ],
    );
  }

  Widget _buildSequence(
    StoryProject p,
    int a,
    StorySequence seq,
    StoryPipelineService pipeline,
  ) {
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
                  onPressed: pipeline.isRunning
                      ? null
                      : () => _planSequence(p, seq.number, pipeline),
                ),
            ],
          ),
        ),
        for (final i in indexes) _buildSceneRow(p, a, i, pipeline),
      ],
    );
  }

  Widget _buildSceneRow(
    StoryProject p,
    int a,
    int i,
    StoryPipelineService pipeline,
  ) {
    final sc = p.scenes[a]![i];
    final beats = p.beats[StoryProjectShape.sceneKey(a, i)] ?? const [];
    final written = p.beatsWritten(a, i);
    final studio = p.engineMode == StoryEngineMode.studio;
    final isNext = beats.isEmpty || written < beats.length
        ? _isFirstUnfinished(p, a, i)
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
    final running = pipeline.isRunning;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: InkWell(
        key: ValueKey('story-scene-$a-$i'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => widget.onOpenWriter?.call(a, i),
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
                      Text(
                        detail,
                        overflow: TextOverflow.ellipsis,
                        style: StudioType.ui(
                          context,
                          size: 12,
                          color: StudioColors.mutedOf(context),
                        ),
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
                    onSelect: () => _writeScene(p, a, i, pipeline),
                  ),
                  StoryMenuEntry(
                    beats.isEmpty ? 'Plan beats' : 'Plan beats again…',
                    enabled: !running,
                    onSelect: () => _planBeats(p, a, i, pipeline),
                  ),
                  StoryMenuEntry(
                    'Edit title & summary…',
                    onSelect: () => _editScene(p, a, i),
                  ),
                  StoryMenuEntry(
                    'Insert scene after…',
                    divider: true,
                    enabled: !running,
                    onSelect: () => _insertAfter(p, a, i),
                  ),
                  StoryMenuEntry(
                    'Rewrite prose…',
                    enabled: !running && written > 0,
                    onSelect: () => _rewriteScene(p, a, i, pipeline),
                  ),
                  StoryMenuEntry(
                    'Delete scene…',
                    danger: true,
                    enabled: !running,
                    onSelect: () => _deleteScene(p, a, i),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isFirstUnfinished(StoryProject p, int a, int i) {
    for (final ref in p.orderedScenes) {
      final count =
          p.beats[StoryProjectShape.sceneKey(ref.act, ref.index)]?.length ?? 0;
      if (count == 0 || p.beatsWritten(ref.act, ref.index) < count) {
        return ref.act == a && ref.index == i;
      }
    }
    return false;
  }
}
