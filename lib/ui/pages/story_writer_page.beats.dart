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

part of 'story_writer_page.dart';

/// Beat cards (sketch O) and the actions behind them.
extension _StoryWriterBeats on _StoryWriterPageState {
  Widget _buildBeatCard(
    StoryProject project,
    List<StoryBeat> beats,
    int b,
    StoryPipelineService pipeline,
  ) {
    final beat = beats[b];
    final prose =
        project.prose[StoryProjectShape.beatKey(
          widget.actIndex,
          widget.sceneIndex,
          b,
        )];
    final text = prose?.final_ ?? prose?.draft ?? '';
    final written = project.beatsWritten(widget.actIndex, widget.sceneIndex);
    // The beat being written right now streams in place.
    final streaming =
        pipeline.isRunning &&
        text.isEmpty &&
        b == written &&
        pipeline.streamingText.isNotEmpty;
    final muted = StudioColors.mutedOf(context);
    final fix = prose?.fix;
    return StoryCard(
      key: ValueKey('story-beat-$b'),
      selected: streaming,
      children: [
        Row(
          children: [
            StoryChip('Beat ${b + 1}'),
            const SizedBox(width: 6),
            if (beat.type.isNotEmpty) StoryChip(beat.type, tone: 'honey'),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                beat.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: StudioType.ui(context, size: 12, color: muted),
              ),
            ),
            if (streaming)
              const StoryChip('writing…', tone: 'amber')
            else
              StoryMenuButton(
                key: ValueKey('story-beat-menu-$b'),
                entries: [
                  StoryMenuEntry(
                    'Edit text by hand',
                    enabled: text.isNotEmpty,
                    onSelect: () => _editByHand(project, b, text),
                  ),
                  StoryMenuEntry(
                    text.isEmpty ? 'Write' : 'Rewrite',
                    enabled: !pipeline.isRunning,
                    onSelect: () => text.isEmpty
                        ? _writeBeat(project, b, pipeline)
                        : _rewriteBeat(project, b, pipeline),
                  ),
                  StoryMenuEntry(
                    'Rewrite with a note…',
                    enabled: !pipeline.isRunning && text.isNotEmpty,
                    onSelect: () => _rewriteWithNote(project, b, pipeline),
                  ),
                  StoryMenuEntry(
                    'Copy',
                    enabled: text.isNotEmpty,
                    onSelect: () =>
                        Clipboard.setData(ClipboardData(text: text)),
                  ),
                ],
              ),
          ],
        ),
        if (text.isNotEmpty) _qualityChips(project, text),
        if (fix != null) _fixCard(project, b, fix, pipeline),
        if (streaming)
          Text.rich(
            TextSpan(
              text: pipeline.streamingText,
              children: [
                TextSpan(
                  text: '▍',
                  style: TextStyle(color: StudioColors.amberOf(context)),
                ),
              ],
            ),
            style: StudioType.prose(context),
          )
        else if (text.isNotEmpty)
          SelectableText(text, style: StudioType.prose(context))
        else if (beat.anchor.isNotEmpty)
          Text(
            'Anchor: ${beat.anchor}',
            style: StudioType.ui(
              context,
              size: 12,
              color: muted,
            ).copyWith(fontStyle: FontStyle.italic),
          ),
      ],
    );
  }

  Widget _qualityChips(StoryProject project, String prose) {
    final quality = StoryQuality.analyze(
      prose,
      bannedPhrases: [...project.bannedPhrases, ...project.autoBannedPhrases],
    );
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final chip in quality.chips)
          StoryChip(chip.label, tone: chip.tone.name),
      ],
    );
  }

  /// "Continuity: fixed" with the reason, the patched lines as
  /// strike-through / insert, and Undo.
  Widget _fixCard(
    StoryProject project,
    int b,
    ContinuityFix fix,
    StoryPipelineService pipeline,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const StoryChip('Continuity: fixed', tone: 'bad'),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              fix.reason,
              style: StudioType.ui(
                context,
                size: 12,
                color: StudioColors.mutedOf(context),
              ),
            ),
          ),
          StoryButton.ghost(
            'Undo fix',
            key: ValueKey('story-undo-fix-$b'),
            onPressed: pipeline.isRunning
                ? null
                : () => pipeline.undoContinuityFix(
                    project,
                    widget.actIndex,
                    widget.sceneIndex,
                    b,
                  ),
          ),
        ],
      ),
      for (final edit in fix.edits)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: edit.find,
                  style: const TextStyle(
                    decoration: TextDecoration.lineThrough,
                    color: StudioColors.diffDelFg,
                    backgroundColor: StudioColors.diffDelBg,
                  ),
                ),
                const TextSpan(text: ' '),
                TextSpan(
                  text: edit.replace,
                  style: const TextStyle(
                    color: StudioColors.diffInsFg,
                    backgroundColor: StudioColors.diffInsBg,
                  ),
                ),
              ],
            ),
            style: StudioType.prose(context, size: 13.5),
          ),
        ),
    ],
  );

  // ── Actions ─────────────────────────────────────────────────────────

  Future<void> _guarded(Future<void> Function() work) async {
    try {
      await work();
      if (mounted) rebuildState(() {});
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
    final note = TextEditingController();
    final ok = await showStoryDialog<bool>(
      context,
      title: 'Rewrite beat ${b + 1} with a note',
      width: 460,
      body: StoryTextArea(
        controller: note,
        hint:
            'What should change? e.g. slower, let Joss speak first, less '
            'smoke',
        minLines: 3,
      ),
      actions: (ctx) => [
        StoryButton.ghost('Cancel', onPressed: () => Navigator.pop(ctx, false)),
        StoryButton.primary(
          'Rewrite',
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    );
    if (ok != true || !mounted) return;
    await _guarded(
      () => pipeline.rewriteBeat(
        project,
        widget.actIndex,
        widget.sceneIndex,
        b,
        directive: note.text.trim(),
      ),
    );
  }

  Future<void> _editByHand(StoryProject project, int b, String text) async {
    final ctl = TextEditingController(text: text);
    final ok = await showStoryDialog<bool>(
      context,
      title: 'Beat ${b + 1}',
      width: 640,
      body: StoryTextArea(controller: ctl, minLines: 10, prose: true),
      actions: (ctx) => [
        StoryButton.ghost('Cancel', onPressed: () => Navigator.pop(ctx, false)),
        StoryButton.primary('Save', onPressed: () => Navigator.pop(ctx, true)),
      ],
    );
    if (ok != true || !mounted) return;
    final key = StoryProjectShape.beatKey(
      widget.actIndex,
      widget.sceneIndex,
      b,
    );
    final prose = project.prose[key] ?? BeatProse();
    prose
      ..final_ = ctl.text.trim()
      ..fix = null;
    project.prose[key] = prose;
    await Provider.of<StoryRepository>(
      context,
      listen: false,
    ).saveProject(project);
    rebuildState(() {});
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
      await Provider.of<StoryRepository>(
        context,
        listen: false,
      ).saveProject(project);
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
    final out = await PickerPrefs.saveFile(
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
