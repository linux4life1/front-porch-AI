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
import 'package:front_porch_ai/ui/pages/story_writer/story_writer.dart';
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';

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
            StoryWriterHeader(
              project: project,
              scene: scene,
              beats: beats,
              pipeline: pipeline,
              actIndex: widget.actIndex,
              sceneIndex: widget.sceneIndex,
              onPickScene: widget.onPickScene,
              onTapTitle: () => _pickScene(project),
              onWriteScene: () => _writeScene(project, pipeline),
              onPlanBeats: (again) =>
                  _planBeats(project, pipeline, again: again),
              onChangeLens: () => _changeLens(project),
              onCopyScene: () => _copyScene(project),
              onExportScene: () => _exportScene(project, scene),
              onRewriteScene: () => _rewriteScene(project, scene, pipeline),
            ),
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
                        StoryBeatCard(
                          project: project,
                          actIndex: widget.actIndex,
                          sceneIndex: widget.sceneIndex,
                          beats: beats,
                          beatIndex: b,
                          pipeline: pipeline,
                          onEditByHand: (text) => _editByHand(project, b, text),
                          onWrite: () => _writeBeat(project, b, pipeline),
                          onRewrite: () => _rewriteBeat(project, b, pipeline),
                          onRewriteWithNote: () =>
                              _rewriteWithNote(project, b, pipeline),
                        ),
                        const SizedBox(height: 12),
                      ],
                    StoryBannedPhrasesCard(
                      project: project,
                      onEdit: () => _editBannedList(project),
                    ),
                  ],
                ),
              ),
            ),
            StoryWriterBottomBar(
              project: project,
              beats: beats,
              pipeline: pipeline,
              actIndex: widget.actIndex,
              sceneIndex: widget.sceneIndex,
              onRewriteWithNote: (b) => _rewriteWithNote(project, b, pipeline),
              onChangeLens: () => _changeLens(project),
              onWriteBeat: (b) => _writeBeat(project, b, pipeline),
            ),
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

  Future<void> _pickScene(StoryProject project) async {
    final pick = widget.onPickScene;
    if (pick == null) return;
    final chosen = await showStoryScenePicker(context, project);
    if (chosen != null) pick(chosen.act, chosen.index);
  }

  Future<void> _save(StoryProject project) =>
      Provider.of<StoryRepository>(context, listen: false).saveProject(project);

  Future<void> _guarded(Future<void> Function() work) async {
    try {
      await work();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showAiErrorSnackBar(context, e);
    }
  }

  Future<void> _planBeats(
    StoryProject project,
    StoryPipelineService pipeline, {
    bool again = false,
  }) async {
    if (again) {
      final ok = await showStoryConfirm(
        context,
        title: 'Plan the beats again?',
        body:
            'The beat list is rebuilt. Prose already written for this scene '
            'is kept but may no longer line up with the new beats.',
        confirmLabel: 'Plan again',
      );
      if (!ok) return;
    }
    await _guarded(
      () =>
          pipeline.runBeatDirector(project, widget.actIndex, widget.sceneIndex),
    );
  }

  Future<void> _writeBeat(
    StoryProject project,
    int b,
    StoryPipelineService pipeline,
  ) => _guarded(
    () => pipeline.runDraftAndEdit(
      project,
      widget.actIndex,
      widget.sceneIndex,
      b,
    ),
  );

  Future<void> _writeScene(
    StoryProject project,
    StoryPipelineService pipeline,
  ) => _guarded(
    () => pipeline.autoWriteScene(project, widget.actIndex, widget.sceneIndex),
  );

  Future<void> _rewriteBeat(
    StoryProject project,
    int b,
    StoryPipelineService pipeline,
  ) => _guarded(
    () => pipeline.rewriteBeat(project, widget.actIndex, widget.sceneIndex, b),
  );

  Future<void> _rewriteWithNote(
    StoryProject project,
    int b,
    StoryPipelineService pipeline,
  ) async {
    final note = await showStoryRewriteNoteDialog(context, b);
    if (note == null || !mounted) return;
    await _guarded(
      () => pipeline.rewriteBeat(
        project,
        widget.actIndex,
        widget.sceneIndex,
        b,
        directive: note,
      ),
    );
  }

  Future<void> _editByHand(StoryProject project, int b, String text) async {
    final edited = await showStoryEditBeatDialog(context, b, text);
    if (edited == null || !mounted) return;
    final key = StoryProjectShape.beatKey(
      widget.actIndex,
      widget.sceneIndex,
      b,
    );
    final prose = project.prose[key] ?? BeatProse();
    prose
      ..final_ = edited
      ..fix = null;
    project.prose[key] = prose;
    await _save(project);
    setState(() {});
  }

  Future<void> _rewriteScene(
    StoryProject project,
    StoryScene scene,
    StoryPipelineService pipeline,
  ) async {
    final ok = await showStoryConfirm(
      context,
      title:
          'Rewrite ${project.sceneLabel(widget.actIndex, widget.sceneIndex)} · ${scene.title}?',
      body: storyRewriteSceneBody(project, widget.actIndex, widget.sceneIndex),
      confirmLabel: 'Rewrite',
      destructive: true,
    );
    if (!ok) return;
    await _guarded(() async {
      StoryStructure.clearSceneProse(
        project,
        widget.actIndex,
        widget.sceneIndex,
      );
      await _save(project);
      await pipeline.regenerateSceneProse(
        project,
        widget.actIndex,
        widget.sceneIndex,
      );
    });
  }

  void _copyScene(StoryProject project) {
    Clipboard.setData(
      ClipboardData(
        text: project.sceneText(widget.actIndex, widget.sceneIndex),
      ),
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Scene copied.')));
  }

  Future<void> _exportScene(StoryProject project, StoryScene scene) async {
    final text = project.sceneText(widget.actIndex, widget.sceneIndex);
    final out = await GuardedPicker.saveFile(
      context,
      category: PickerPrefs.catExport,
      bytes: Uint8List.fromList(utf8.encode(text)),
      dialogTitle: 'Save scene',
      fileName: p.basename(
        storySceneExportPath('', project.title, scene.title),
      ),
      type: FileType.custom,
      allowedExtensions: ['txt'],
    );
    if (out != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Scene saved to $out')));
    }
  }

  Future<void> _editBannedList(StoryProject project) async {
    final phrases = await showStoryBannedPhrasesDialog(context, project);
    if (phrases == null || !mounted) return;
    project.bannedPhrases = phrases;
    await _save(project);
    setState(() {});
  }

  Future<void> _changeLens(StoryProject project) async {
    final scene = project.scenes[widget.actIndex]![widget.sceneIndex];
    final current = StoryLenses.normalizeId(scene.lens);
    final picked = await showStoryLensPicker(context, project, current);
    if (picked == null || !mounted) return;
    if (picked == '+') return _addCustomLens(project, scene);
    scene.lens = picked;
    await _save(project);
    setState(() {});
  }

  Future<void> _addCustomLens(StoryProject project, StoryScene scene) async {
    final lens = await showStoryCustomLensDialog(context);
    if (lens == null || !mounted) return;
    project.customLenses
      ..removeWhere((l) => l.id == lens.id)
      ..add(lens);
    scene.lens = lens.id;
    await _save(project);
    setState(() {});
  }
}

/// Path a scene export is written to: [dirPath] plus a sanitized
/// `<project>_<scene>.txt` file name. Only the FILE NAME is sanitized — a
/// sanitizer run over the whole path once turned every separator (and the
/// Windows drive colon) into `_`, so exports landed in the process working
/// directory under a mangled name. The save dialog takes the basename.
String storySceneExportPath(
  String dirPath,
  String projectTitle,
  String sceneTitle,
) {
  final name = '${projectTitle}_$sceneTitle.txt'.replaceAll(
    RegExp(r'[^\w\s.]'),
    '_',
  );
  return p.join(dirPath, name);
}
