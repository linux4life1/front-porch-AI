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

/// The structure board: acts, their sequences, and scene rows carrying the
/// lens, tension, type and how much of the scene is written.
extension _StoryStructureTree on _StoryStructurePageState {
  Widget _buildStructureTree(
    StoryProject project,
    StoryPipelineService pipeline,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: project.acts.length,
      itemBuilder: (context, actIdx) => _buildAct(project, pipeline, actIdx),
    );
  }

  Widget _buildAct(
    StoryProject project,
    StoryPipelineService pipeline,
    int actIdx,
  ) {
    final accent = AppColors.porchTerracottaOf(context);
    final act = project.acts[actIdx];
    final scenes = project.scenes[actIdx] ?? [];
    final isExpanded = _expandedActIndex == actIdx;
    return Column(
      children: [
        InkWell(
          onTap: () =>
              rebuildState(() => _expandedActIndex = isExpanded ? -1 : actIdx),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardOf(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isExpanded
                    ? accent
                    : AppColors.borderOf(context).withValues(alpha: 0.4),
                width: isExpanded ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      '${act.number}',
                      style: TextStyle(
                        color: accent,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        act.title,
                        style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        scenes.isEmpty
                            ? 'No scenes yet'
                            : '${scenes.length} scenes · '
                                  '${project.sequencesInAct(actIdx).length} '
                                  'sequence${project.sequencesInAct(actIdx).length == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: AppColors.textTertiary(context),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (scenes.isNotEmpty)
                  SizedBox(
                    width: 100,
                    height: 30,
                    child: CustomPaint(
                      painter: _ValenceSparklinePainter(
                        scenes.map((s) => s.valence).toList(),
                        lineColor: AppColors.frostAccentOf(
                          context,
                        ).withValues(alpha: 0.6),
                        zeroLineColor: AppColors.borderOf(
                          context,
                        ).withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                if (scenes.isEmpty)
                  ElevatedButton.icon(
                    onPressed: pipeline.isRunning
                        ? null
                        : () => _generateFullAct(project, actIdx, pipeline),
                    icon: const Icon(Icons.auto_fix_high, size: 16),
                    label: const Text(
                      'Generate Act',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.porchHoneyOf(context),
                      foregroundColor: AppColors.resolve(
                        context,
                        AppColors.onChaosAccent,
                        AppColors.userText,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                if (scenes.isNotEmpty) ...[
                  _actCompletionBadge(project, actIdx),
                  const SizedBox(width: 8),
                ],
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: AppColors.iconSecondary(context),
                ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 8),
            child: scenes.isEmpty
                ? _emptyAct(project, pipeline, actIdx)
                : Column(
                    children: [
                      for (final seq in project.sequencesInAct(actIdx))
                        _buildSequence(project, pipeline, actIdx, seq),
                    ],
                  ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _emptyAct(
    StoryProject project,
    StoryPipelineService pipeline,
    int actIdx,
  ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.sunkenSurfaceOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.borderOf(context).withValues(alpha: 0.2),
        ),
      ),
      child: Center(
        child: Text(
          project.engineMode == StoryEngineMode.studio
              ? 'Generate Act outlines each sequence, then writes it scene by '
                    'scene.'
              : 'Generate scenes to fill this act',
          style: TextStyle(color: AppColors.textTertiary(context)),
        ),
      ),
    );
  }

  Widget _buildSequence(
    StoryProject project,
    StoryPipelineService pipeline,
    int actIdx,
    StorySequence seq,
  ) {
    final indexes = project.sceneIndexesInSequence(seq.number);
    final studio = project.engineMode == StoryEngineMode.studio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (studio)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 4,
              children: [
                Text(
                  'Sequence ${seq.number} · ${seq.title}',
                  style: TextStyle(
                    color: AppColors.porchHoneyOf(context),
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
                StoryChip('Act ${project.acts[actIdx].number}', tone: 'honey'),
                if (seq.dramaticQuestion.isNotEmpty)
                  Text(
                    '“${seq.dramaticQuestion}”',
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 12,
                    ),
                  ),
                if (indexes.isEmpty)
                  TextButton(
                    onPressed: pipeline.isRunning
                        ? null
                        : () => _planSequence(project, seq.number, pipeline),
                    child: const Text('Outline scenes'),
                  ),
              ],
            ),
          ),
        for (final i in indexes) _buildSceneRow(project, pipeline, actIdx, i),
      ],
    );
  }

  Widget _buildSceneRow(
    StoryProject project,
    StoryPipelineService pipeline,
    int actIdx,
    int sceneIdx,
  ) {
    final scene = project.scenes[actIdx]![sceneIdx];
    final beats = project.beats['$actIdx-$sceneIdx'] ?? const <StoryBeat>[];
    final written = project.beatsWritten(actIdx, sceneIdx);
    final studio = project.engineMode == StoryEngineMode.studio;
    final isNext = beats.isEmpty || written < beats.length;
    final status = beats.isEmpty
        ? const StoryChip('Not planned')
        : written == beats.length
        ? const StoryChip('Written', tone: 'teal')
        : written == 0
        ? StoryChip('${beats.length} beats planned', tone: 'amber')
        : StoryChip('$written of ${beats.length} written', tone: 'amber');
    final detail = [
      if (scene.castNames.isNotEmpty) scene.castNames.join(', '),
      if (scene.location.isNotEmpty) scene.location,
      if (scene.valueFrom.isNotEmpty || scene.valueTo.isNotEmpty)
        '${scene.valueFrom} → ${scene.valueTo}',
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isNext && written == 0 && beats.isNotEmpty
              ? AppColors.porchAmberOf(context)
              : AppColors.borderOf(context).withValues(alpha: 0.4),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openScene(actIdx, sceneIdx),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  project.sceneLabel(actIdx, sceneIdx),
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (studio && project.lensesEnabled) ...[
                StoryLensMark(scene.lens),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      scene.title,
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (detail.isNotEmpty)
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textTertiary(context),
                          fontSize: 11.5,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (studio) StoryTensionBars(scene.tension),
                  if (studio && scene.sceneType.isNotEmpty)
                    StoryChip(
                      scene.sceneType == 'reaction' ? 'Reaction' : 'Action',
                    ),
                  status,
                  if (beats.isNotEmpty)
                    Text(
                      '$written/${beats.length}',
                      style: TextStyle(
                        color: written == beats.length
                            ? AppColors.bondHighOf(context)
                            : AppColors.textTertiary(context),
                        fontSize: 12,
                      ),
                    ),
                  if (written > 0)
                    IconButton(
                      icon: Icon(
                        Icons.refresh,
                        size: 16,
                        color: AppColors.taskAccentOf(
                          context,
                        ).withValues(alpha: 0.8),
                      ),
                      tooltip: 'Rewrite scene prose',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onPressed: pipeline.isRunning
                          ? null
                          : () => _regenerateScene(
                              project,
                              actIdx,
                              sceneIdx,
                              pipeline,
                            ),
                    ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppColors.iconSecondary(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openScene(int actIdx, int sceneIdx) {
    final open = widget.onOpenWriter;
    if (open != null) {
      open(actIdx, sceneIdx);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StoryWriterPage(
          projectId: widget.projectId,
          actIndex: actIdx,
          sceneIndex: sceneIdx,
        ),
      ),
    );
  }

  Widget _actCompletionBadge(StoryProject project, int actIdx) {
    final scenes = project.scenes[actIdx] ?? [];
    var done = 0;
    for (var s = 0; s < scenes.length; s++) {
      final count = project.beats['$actIdx-$s']?.length ?? 0;
      if (count > 0 && project.beatsWritten(actIdx, s) == count) done++;
    }
    final isComplete = done == scenes.length && scenes.isNotEmpty;
    final color = isComplete
        ? AppColors.bondHighOf(context)
        : AppColors.porchHoneyOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isComplete ? '✓ Complete' : '$done/${scenes.length}',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Draws a tiny sparkline of scene valence values.
class _ValenceSparklinePainter extends CustomPainter {
  final List<int> values;
  final Color lineColor;
  final Color zeroLineColor;

  _ValenceSparklinePainter(
    this.values, {
    required this.lineColor,
    required this.zeroLineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    final paint = Paint()
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..color = lineColor;

    final zeroPaint = Paint()
      ..color = zeroLineColor
      ..strokeWidth = 0.5;

    final yCenter = size.height / 2;
    canvas.drawLine(Offset(0, yCenter), Offset(size.width, yCenter), zeroPaint);

    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final x = (i / (values.length - 1)) * size.width;
      final y = yCenter - (values[i] / 10.0) * (size.height / 2);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ValenceSparklinePainter oldDelegate) =>
      values != oldDelegate.values || lineColor != oldDelegate.lineColor;
}
