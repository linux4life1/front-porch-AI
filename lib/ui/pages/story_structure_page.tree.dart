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

/// Act/scene tree, valence chips, and the sparkline painter.
extension _StoryStructureTree on _StoryStructurePageState {
  Widget _buildStructureTree(
    StoryProject project,
    StoryPipelineService pipeline,
  ) {
    final accent = AppColors.porchTerracottaOf(context);
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: project.acts.length,
      itemBuilder: (context, actIdx) {
        final act = project.acts[actIdx];
        final scenes = project.scenes[actIdx] ?? [];
        final isExpanded = _expandedActIndex == actIdx;

        return Column(
          children: [
            // Act header
            InkWell(
              onTap: () => rebuildState(
                () => _expandedActIndex = isExpanded ? -1 : actIdx,
              ),
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
                                : '${scenes.length} scenes',
                            style: TextStyle(
                              color: AppColors.textTertiary(context),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Valence sparkline
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
                      // Show completion status
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

            // Scenes (when expanded)
            if (isExpanded && scenes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 32, top: 8),
                child: Column(
                  children: scenes.asMap().entries.map((entry) {
                    final sceneIdx = entry.key;
                    final scene = entry.value;
                    final sId = '$actIdx-$sceneIdx';
                    final beats = project.beats[sId] ?? [];
                    final proseCount = beats.where((b) {
                      final bId = '$sId-${b.number - 1}';
                      return project.prose[bId]?.final_ != null;
                    }).length;

                    return Card(
                      color: AppColors.sunkenSurfaceOf(context),
                      margin: const EdgeInsets.only(bottom: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: _valenceIndicator(scene.valence),
                        title: Text(
                          scene.title,
                          style: TextStyle(
                            color: AppColors.textSecondary(context),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          '${scene.location} • ${scene.castNames.join(", ")}',
                          style: TextStyle(
                            color: AppColors.textTertiary(context),
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (beats.isNotEmpty)
                              Text(
                                '$proseCount/${beats.length}',
                                style: TextStyle(
                                  color: proseCount == beats.length
                                      ? AppColors.bondHighOf(context)
                                      : AppColors.textTertiary(context),
                                  fontSize: 12,
                                ),
                              ),
                            if (proseCount > 0)
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
                            const SizedBox(width: 4),
                            Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: AppColors.iconSecondary(context),
                            ),
                          ],
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => StoryWriterPage(
                              projectId: widget.projectId,
                              actIndex: actIdx,
                              sceneIndex: sceneIdx,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

            if (isExpanded && scenes.isEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 32, top: 8),
                child: Container(
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
                      'Generate scenes to fill this act',
                      style: TextStyle(color: AppColors.textTertiary(context)),
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 12),
          ],
        );
      },
    );
  }

  Widget _valenceIndicator(int valence) {
    final color = valence > 0
        ? AppColors.bondHighOf(context)
        : valence == 0
        ? AppColors.textTertiary(context)
        : valence > -3
        ? AppColors.taskAccentOf(context)
        : AppColors.negativeAccentOf(context);
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Text(
          valence > 0 ? '+$valence' : '$valence',
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _actCompletionBadge(StoryProject project, int actIdx) {
    final scenes = project.scenes[actIdx] ?? [];
    // Check if any scene has prose
    int scenesWithProse = 0;
    for (int s = 0; s < scenes.length; s++) {
      final sId = '$actIdx-$s';
      final beats = project.beats[sId] ?? [];
      if (beats.isNotEmpty) {
        final hasAllProse = beats.asMap().entries.every((e) {
          final bId = '$sId-${e.key}';
          return project.prose[bId]?.final_ != null;
        });
        if (hasAllProse) scenesWithProse++;
      }
    }

    final isComplete = scenesWithProse == scenes.length && scenes.isNotEmpty;
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
        isComplete ? '✓ Complete' : '$scenesWithProse/${scenes.length}',
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
