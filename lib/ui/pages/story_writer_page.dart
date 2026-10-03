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

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/story/story.dart';
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';

part 'story_writer_page.beats.dart';
part 'story_writer_page.lenses.dart';

/// Write (sketch O): one scene, beat by beat. The header walks scenes with
/// ‹ ›; beats show quality chips, the continuity fix with Undo, and the beat
/// being written streams in place. Lives inside the studio.
class StoryWriterPage extends StatefulWidget {
  final String projectId;
  final int actIndex;
  final int sceneIndex;
  final bool embedded;
  final void Function(int act, int scene)? onPickScene;

  const StoryWriterPage({
    super.key,
    required this.projectId,
    required this.actIndex,
    required this.sceneIndex,
    this.embedded = false,
    this.onPickScene,
  });

  @override
  State<StoryWriterPage> createState() => _StoryWriterPageState();
}

class _StoryWriterPageState extends State<StoryWriterPage> {
  String get _sId =>
      StoryProjectShape.sceneKey(widget.actIndex, widget.sceneIndex);

  void rebuildState(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) {
    return Consumer2<StoryRepository, StoryPipelineService>(
      builder: (context, repo, pipeline, _) {
        final project = repo.getById(widget.projectId);
        final scene = project?.scenes[widget.actIndex]?[widget.sceneIndex];
        if (project == null || scene == null) {
          return const SizedBox.shrink();
        }
        final beats = project.beats[_sId] ?? const <StoryBeat>[];
        final body = Column(
          key: const ValueKey('studio-write'),
          children: [
            _buildHeader(project, scene, beats, pipeline),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (beats.isEmpty)
                      StoryEmptyState(
                        title: 'No beats yet',
                        detail:
                            'Plan the beats for this scene, then write them '
                            'one at a time or all at once.',
                        action: 'Plan beats',
                        onAction: pipeline.isRunning
                            ? null
                            : () => _planBeats(project, pipeline),
                      )
                    else
                      for (var b = 0; b < beats.length; b++) ...[
                        _buildBeatCard(project, beats, b, pipeline),
                        const SizedBox(height: 12),
                      ],
                    _buildBannedCard(project),
                  ],
                ),
              ),
            ),
            _buildBottomBar(project, scene, beats, pipeline),
          ],
        );
        if (widget.embedded) return body;
        return StudioTheme(
          child: Scaffold(
            backgroundColor: StudioColors.bgOf(context),
            body: body,
          ),
        );
      },
    );
  }

  Widget _buildHeader(
    StoryProject project,
    StoryScene scene,
    List<StoryBeat> beats,
    StoryPipelineService pipeline,
  ) {
    final refs = project.orderedScenes.toList();
    final at = refs.indexWhere(
      (r) => r.act == widget.actIndex && r.index == widget.sceneIndex,
    );
    final prev = at > 0 ? refs[at - 1] : null;
    final next = at >= 0 && at < refs.length - 1 ? refs[at + 1] : null;
    final written = project.beatsWritten(widget.actIndex, widget.sceneIndex);
    final studio = project.engineMode == StoryEngineMode.studio;
    final subtitle = [
      beats.isEmpty
          ? 'No beats yet'
          : 'Beat ${(written + 1).clamp(1, beats.length)} of ${beats.length}',
      if (studio && project.lensesEnabled)
        StoryLenses.resolve(project, scene.lens).name,
      if (scene.location.isNotEmpty) scene.location,
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: StudioColors.lineOf(context))),
      ),
      child: Row(
        children: [
          StoryIconButton(
            Icons.chevron_left,
            tooltip: prev == null ? 'First scene' : 'Previous scene',
            onPressed: prev == null
                ? null
                : () => widget.onPickScene?.call(prev.act, prev.index),
          ),
          Expanded(
            child: InkWell(
              onTap: () => _pickScene(project),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${project.sceneLabel(widget.actIndex, widget.sceneIndex)} · '
                      '${scene.title.isEmpty ? 'Untitled scene' : scene.title}',
                      overflow: TextOverflow.ellipsis,
                      style: StudioType.ui(
                        context,
                        size: 15,
                        weight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      overflow: TextOverflow.ellipsis,
                      style: StudioType.ui(
                        context,
                        size: 12.5,
                        color: StudioColors.mutedOf(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          StoryIconButton(
            Icons.chevron_right,
            tooltip: next == null ? 'Last scene' : 'Next scene',
            onPressed: next == null
                ? null
                : () => widget.onPickScene?.call(next.act, next.index),
          ),
          const SizedBox(width: 8),
          if (pipeline.isRunning)
            StoryChip('● ${pipeline.currentStep}', tone: 'amber'),
          StoryMenuButton(
            key: const ValueKey('story-scene-menu'),
            entries: [
              StoryMenuEntry(
                'Write the whole scene',
                enabled: !pipeline.isRunning && beats.isNotEmpty,
                onSelect: () => _writeScene(project, pipeline),
              ),
              StoryMenuEntry(
                beats.isEmpty ? 'Plan beats' : 'Plan beats again…',
                enabled: !pipeline.isRunning,
                onSelect: () =>
                    _planBeats(project, pipeline, again: beats.isNotEmpty),
              ),
              StoryMenuEntry(
                'Change lens…',
                enabled: studio && project.lensesEnabled,
                onSelect: () => _changeLens(project),
              ),
              StoryMenuEntry(
                'Copy scene text',
                divider: true,
                enabled: written > 0,
                onSelect: () => _copyScene(project),
              ),
              StoryMenuEntry(
                'Export scene…',
                enabled: written > 0,
                onSelect: () => _exportScene(project, scene),
              ),
              StoryMenuEntry(
                'Rewrite scene…',
                divider: true,
                danger: true,
                enabled: !pipeline.isRunning && written > 0,
                onSelect: () => _rewriteScene(project, scene, pipeline),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(
    StoryProject project,
    StoryScene scene,
    List<StoryBeat> beats,
    StoryPipelineService pipeline,
  ) {
    final written = project.beatsWritten(widget.actIndex, widget.sceneIndex);
    final studio = project.engineMode == StoryEngineMode.studio;
    final busy = pipeline.isRunning || beats.isEmpty;
    final done = written >= beats.length && beats.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: StudioColors.bgOf(context),
        border: Border(top: BorderSide(color: StudioColors.lineOf(context))),
      ),
      child: Row(
        children: [
          StoryButton(
            'Rewrite beat ${written.clamp(1, beats.isEmpty ? 1 : beats.length)} with a note…',
            key: const ValueKey('story-rewrite-beat'),
            onPressed: busy || written == 0
                ? null
                : () => _rewriteWithNote(project, written - 1, pipeline),
          ),
          const SizedBox(width: 10),
          if (studio && project.lensesEnabled)
            StoryButton(
              'Change lens',
              key: const ValueKey('story-change-lens'),
              onPressed: () => _changeLens(project),
            ),
          const Spacer(),
          StoryButton.primary(
            done ? 'Scene written' : 'Write next beat',
            key: const ValueKey('story-write-next'),
            onPressed: busy || done
                ? null
                : () => _writeBeat(project, written, pipeline),
          ),
        ],
      ),
    );
  }

  Future<void> _pickScene(StoryProject project) async {
    final pick = widget.onPickScene;
    if (pick == null) return;
    final chosen = await showStoryDialog<SceneRef>(
      context,
      title: 'Go to scene',
      width: 460,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final ref in project.orderedScenes)
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => Navigator.pop(context, ref),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text(
                        project.sceneLabel(ref.act, ref.index),
                        style: StudioType.mono(context),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        ref.scene.title,
                        overflow: TextOverflow.ellipsis,
                        style: StudioType.ui(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      actions: (ctx) => [
        StoryButton.ghost('Cancel', onPressed: () => Navigator.pop(ctx)),
      ],
    );
    if (chosen != null) pick(chosen.act, chosen.index);
  }
}
