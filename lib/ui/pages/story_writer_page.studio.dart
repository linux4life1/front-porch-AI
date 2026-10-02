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

/// Studio additions to the writer: the embedded header with a scene picker,
/// quality chips per beat, the continuity-fix card with its diff and Undo,
/// the banned-phrase list, and the lens picker.
extension _StoryWriterStudio on _StoryWriterPageState {
  List<String> _allBanned(StoryProject project) => [
    ...project.bannedPhrases,
    ...project.autoBannedPhrases,
  ];

  /// "3.3 · The wagon fire" with "Beat 6 of 14 · Lens: Kinetic action".
  Widget _buildEmbeddedHeader(
    StoryProject project,
    StoryScene scene,
    List<StoryBeat> beats,
    StoryPipelineService pipeline,
  ) {
    final written = project.beatsWritten(widget.actIndex, widget.sceneIndex);
    final studio = project.engineMode == StoryEngineMode.studio;
    final lens = StoryLenses.resolve(project, scene.lens);
    final subtitle = [
      if (beats.isNotEmpty)
        'Beat ${(written + 1).clamp(1, beats.length)} of ${beats.length}'
      else
        'No beats yet',
      if (studio && project.lensesEnabled) 'Lens: ${lens.name}',
      if (scene.location.isNotEmpty) scene.location,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '${project.sceneLabel(widget.actIndex, widget.sceneIndex)} · '
                        '${scene.title}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _scenePicker(project),
                  ],
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textTertiary(context),
                  ),
                ),
              ],
            ),
          ),
          if (beats.isEmpty)
            TextButton.icon(
              onPressed: pipeline.isRunning
                  ? null
                  : () => _generateBeats(project, pipeline),
              icon: Icon(
                Icons.auto_fix_high,
                size: 16,
                color: AppColors.porchHoneyOf(context),
              ),
              label: Text(
                'Generate Beats',
                style: TextStyle(color: AppColors.porchHoneyOf(context)),
              ),
            ),
          if (beats.isNotEmpty)
            TextButton.icon(
              onPressed: pipeline.isRunning
                  ? null
                  : () => _autoWriteScene(project, pipeline),
              icon: Icon(
                Icons.play_arrow,
                size: 16,
                color: AppColors.bondHighOf(context),
              ),
              label: Text(
                'Auto-Write',
                style: TextStyle(color: AppColors.bondHighOf(context)),
              ),
            ),
          _menuButton(project, pipeline),
        ],
      ),
    );
  }

  Widget _scenePicker(StoryProject project) {
    final pick = widget.onPickScene;
    if (pick == null) return const SizedBox.shrink();
    return PopupMenuButton<({int act, int scene})>(
      tooltip: 'Another scene',
      icon: Icon(
        Icons.unfold_more,
        size: 18,
        color: AppColors.iconSecondary(context),
      ),
      color: AppColors.surfaceContainerOf(context),
      onSelected: (v) => pick(v.act, v.scene),
      itemBuilder: (_) => [
        for (final ref in project.orderedScenes)
          PopupMenuItem(
            value: (act: ref.act, scene: ref.index),
            child: Text(
              '${project.sceneLabel(ref.act, ref.index)}  ${ref.scene.title}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
      ],
    );
  }

  Widget _menuButton(StoryProject project, StoryPipelineService pipeline) =>
      PopupMenuButton<String>(
        icon: Icon(Icons.more_vert, color: AppColors.iconSecondary(context)),
        color: AppColors.surfaceContainerOf(context),
        onSelected: (v) => _handleMenuAction(v, project, pipeline),
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 'copy',
            child: ListTile(
              leading: Icon(Icons.copy, size: 18),
              title: Text('Copy Scene Text', style: TextStyle(fontSize: 13)),
              dense: true,
            ),
          ),
          PopupMenuItem(
            value: 'export',
            child: ListTile(
              leading: Icon(Icons.save_alt, size: 18),
              title: Text('Export Scene', style: TextStyle(fontSize: 13)),
              dense: true,
            ),
          ),
        ],
      );

  /// Rewrite beat · Change lens · Write next beat.
  Widget _buildBottomBar(
    StoryProject project,
    List<StoryBeat> beats,
    StoryPipelineService pipeline,
  ) {
    final written = project.beatsWritten(widget.actIndex, widget.sceneIndex);
    final studio = project.engineMode == StoryEngineMode.studio;
    final busy = pipeline.isRunning || beats.isEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.borderOf(context))),
      ),
      child: Row(
        children: [
          StoryQuietButton(
            'Rewrite beat',
            icon: Icons.refresh,
            onPressed: busy || written == 0
                ? null
                : () => _rewriteBeat(project, written - 1, pipeline),
          ),
          const SizedBox(width: 8),
          if (studio && project.lensesEnabled)
            StoryQuietButton(
              'Change lens',
              icon: Icons.camera_outlined,
              onPressed: pipeline.isRunning ? null : () => _changeLens(project),
            ),
          const Spacer(),
          StoryPrimaryButton(
            'Write next beat',
            icon: Icons.edit,
            onPressed: busy || written >= beats.length
                ? null
                : () => _writeBeat(project, written, pipeline),
          ),
        ],
      ),
    );
  }

  Widget _qualityChips(StoryProject project, String prose) {
    final quality = StoryQuality.analyze(
      prose,
      bannedPhrases: _allBanned(project),
    );
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final chip in quality.chips)
          StoryChip(chip.label, tone: chip.tone.name),
      ],
    );
  }

  /// The patched passage with the old words struck through and the new
  /// ones marked, plus the reason and an Undo.
  Widget _buildFixCard(
    StoryProject project,
    int beatIdx,
    BeatProse prose,
    StoryPipelineService pipeline,
  ) {
    final fix = prose.fix!;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.negativeAccentOf(context).withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const StoryChip('Continuity: fixed', tone: 'bad'),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  fix.reason,
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 12,
                  ),
                ),
              ),
              TextButton(
                onPressed: pipeline.isRunning
                    ? null
                    : () => pipeline.undoContinuityFix(
                        project,
                        widget.actIndex,
                        widget.sceneIndex,
                        beatIdx,
                      ),
                child: const Text('Undo fix'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final edit in fix.edits)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 13.5,
                    height: 1.6,
                    fontFamily: 'serif',
                  ),
                  children: [
                    TextSpan(
                      text: edit.find,
                      style: TextStyle(
                        decoration: TextDecoration.lineThrough,
                        color: AppColors.negativeAccentOf(context),
                        backgroundColor: AppColors.negativeAccentOf(
                          context,
                        ).withValues(alpha: 0.12),
                      ),
                    ),
                    const TextSpan(text: ' '),
                    TextSpan(
                      text: edit.replace,
                      style: TextStyle(
                        color: AppColors.journalAccentOf(context),
                        backgroundColor: AppColors.journalAccentOf(
                          context,
                        ).withValues(alpha: 0.12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _rewriteBeat(
    StoryProject project,
    int beatIdx,
    StoryPipelineService pipeline,
  ) async {
    try {
      await pipeline.rewriteBeat(
        project,
        widget.actIndex,
        widget.sceneIndex,
        beatIdx,
      );
      if (mounted) rebuildState(() {});
    } catch (e) {
      if (mounted) showAiErrorSnackBar(context, e);
    }
  }
}
