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

part of 'story_dashboard_page.dart';

/// The studio header (sketch M): ← Stories, title, where you are, the one
/// Stop while a run is on, Setup, ⋯. Then the 4px progress bar and the
/// section router.
extension _StoryDashboardShell on _StoryDashboardPageState {
  Widget _buildHeader(StoryProject project, StoryPipelineService pipeline) {
    final st = storyShelfStatus(project);
    final running = pipeline.isRunning;
    // "Act II · 41,200 / 80,000" gains the unit here; the shelf has no room.
    final subtitle = running && project.acts.isEmpty
        ? 'Building the bible…'
        : st.status.contains(' / ')
        ? '${st.status} words'
        : st.status;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
      decoration: BoxDecoration(
        color: StudioColors.sideOf(context),
        border: Border(bottom: BorderSide(color: StudioColors.lineOf(context))),
      ),
      child: Row(
        children: [
          StoryButton.ghost(
            '← Stories',
            key: const ValueKey('studio-back'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: () => renameStory(context, project),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      project.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StudioType.ui(
                        context,
                        size: 15,
                        weight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
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
          const SizedBox(width: 8),
          if (running) ...[
            StoryChip(
              pipeline.stopRequested
                  ? 'Stopping after this step…'
                  : '● ${pipeline.currentStep}',
              tone: 'amber',
            ),
            const SizedBox(width: 8),
            StoryButton(
              'Stop',
              key: const ValueKey('story-stop'),
              onPressed: pipeline.stopRequested ? null : pipeline.requestStop,
            ),
            const SizedBox(width: 8),
          ],
          _audiobookChip(),
          StoryButton.ghost(
            'Setup',
            key: const ValueKey('studio-setup'),
            onPressed: running
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => StorySetupPage(projectId: project.dbId!),
                    ),
                  ),
          ),
          StoryMenuButton(
            key: const ValueKey('studio-menu'),
            entries: [
              StoryMenuEntry(
                'Export eBook (.epub)',
                enabled: project.wordCount > 0,
                onSelect: () => _exportEpub(project),
              ),
              StoryMenuEntry(
                'Export audiobook (.wav)',
                enabled: project.wordCount > 0,
                onSelect: () => _exportAudiobook(project),
              ),
              StoryMenuEntry(
                'Export text (.md)',
                enabled: project.wordCount > 0,
                onSelect: () => _exportText(project),
              ),
              StoryMenuEntry(
                'Rename',
                divider: true,
                onSelect: () => renameStory(context, project),
              ),
              StoryMenuEntry(
                'Delete story…',
                danger: true,
                enabled: !running,
                onSelect: () => _deleteStory(project),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// A slim status while an audiobook compiles, with Abort.
  Widget _audiobookChip() {
    final service = context.watch<AudiobookGeneratorService>();
    if (!service.isGenerating) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StoryChip(
          'Exporting audiobook ${(service.progress * 100).round()}%',
          tone: 'honey',
        ),
        StoryButton.ghost('Abort', onPressed: service.stop),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildProgress(StoryProject project) {
    final st = storyShelfStatus(project);
    return StoryProgressBar(st.fraction, done: st.done);
  }

  void _openWriter(int act, int scene) => rebuildState(() {
    _writeTarget = (act: act, scene: scene);
    _section = StudioSection.write;
  });

  Widget _buildSection(StoryProject project, StoryPipelineService pipeline) {
    switch (_section) {
      case StudioSection.overview:
        return _buildOverview(project, pipeline);
      case StudioSection.read:
        return StoryReaderPage(
          key: ValueKey('reader-${project.dbId}'),
          projectId: widget.projectId,
          embedded: true,
          onToggleSidebar: () =>
              rebuildState(() => _sidebarShown = !_sidebarShown),
        );
      case StudioSection.structure:
        return StoryStructurePage(
          projectId: widget.projectId,
          embedded: true,
          onOpenWriter: _openWriter,
        );
      case StudioSection.write:
        final target = _writeTarget ?? _defaultWriteTarget(project);
        if (target == null) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: StoryEmptyState(
              title: 'Nothing to write yet',
              detail:
                  'Build the structure first; Write follows the scene you '
                  'pick there.',
              action: 'Go to Structure',
              onAction: () => _open(StudioSection.structure),
            ),
          );
        }
        return StoryWriterPage(
          key: ValueKey('writer-${target.act}-${target.scene}'),
          projectId: widget.projectId,
          actIndex: target.act,
          sceneIndex: target.scene,
          embedded: true,
          onPickScene: _openWriter,
        );
      case StudioSection.director:
        return DirectorSection(project: project, pipeline: pipeline);
      case StudioSection.cast:
        return CastSection(project: project, pipeline: pipeline);
      case StudioSection.relationships:
        return RelationshipsSection(project: project);
      case StudioSection.lore:
        return LoreSection(project: project, pipeline: pipeline);
      case StudioSection.runLog:
        return RunLogSection(project: project, pipeline: pipeline);
    }
  }

  /// The next unfinished scene, else the last scene.
  ({int act, int scene})? _defaultWriteTarget(StoryProject project) {
    SceneRef? last;
    for (final ref in project.orderedScenes) {
      last = ref;
      final count =
          project
              .beats[StoryProjectShape.sceneKey(ref.act, ref.index)]
              ?.length ??
          0;
      if (count == 0 || project.beatsWritten(ref.act, ref.index) < count) {
        return (act: ref.act, scene: ref.index);
      }
    }
    return last == null ? null : (act: last.act, scene: last.index);
  }
}
