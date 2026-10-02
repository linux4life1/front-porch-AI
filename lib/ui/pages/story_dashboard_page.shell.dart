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

/// The studio shell: title with progress, the sidebar, and the section it
/// selected. Structure and Write embed their own pages; Read opens the
/// reader as a full-screen route.
extension _StoryDashboardShell on _StoryDashboardPageState {
  Widget _buildTitle(StoryProject project) {
    final words = project.wordCount;
    final next = project.orderedScenes
        .where(
          (r) =>
              (project.beats['${r.act}-${r.index}']?.length ?? 0) == 0 ||
              project.beatsWritten(r.act, r.index) <
                  project.beats['${r.act}-${r.index}']!.length,
        )
        .firstOrNull;
    final actLabel = project.acts.isEmpty
        ? 'Setting up'
        : 'Act ${_roman((next?.act ?? project.acts.length - 1) + 1)}';
    final progress = project.engineMode == StoryEngineMode.studio
        ? '${_group(words)} / ${_group(project.targetWords)} words'
        : '${_group(words)} words';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(project.title, style: const TextStyle(fontSize: 16)),
        Text(
          '$actLabel · $progress',
          style: TextStyle(
            fontSize: 11.5,
            color: AppColors.textTertiary(context),
          ),
        ),
      ],
    );
  }

  static String _roman(int n) =>
      const [
        '',
        'I',
        'II',
        'III',
        'IV',
        'V',
        'VI',
        'VII',
        'VIII',
      ].elementAtOrNull(n) ??
      '$n';

  static String _group(int n) => n.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );

  void _openSection(StudioSection section) {
    if (section == StudioSection.read) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => StoryReaderPage(projectId: widget.projectId),
        ),
      );
      return;
    }
    rebuildState(() => _section = section);
  }

  void _openWriter(int act, int scene) => rebuildState(() {
    _writeTarget = (act: act, scene: scene);
    _section = StudioSection.write;
  });

  Widget _buildShell(StoryProject project, StoryPipelineService pipeline) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < kStudioSidebarBreakpoint;
        final sidebar = StudioSidebar(
          project: project,
          selected: _section,
          onSelect: _openSection,
          horizontal: narrow,
        );
        final main = _buildSection(project, pipeline);
        if (narrow) {
          return Column(
            children: [
              sidebar,
              Divider(height: 1, color: AppColors.borderOf(context)),
              Expanded(child: main),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            sidebar,
            VerticalDivider(width: 1, color: AppColors.borderOf(context)),
            Expanded(child: main),
          ],
        );
      },
    );
  }

  Widget _buildSection(StoryProject project, StoryPipelineService pipeline) {
    switch (_section) {
      case StudioSection.overview:
      case StudioSection.read:
        return _buildBody(project, pipeline);
      case StudioSection.structure:
        return StoryStructurePage(
          projectId: widget.projectId,
          embedded: true,
          onOpenWriter: _openWriter,
        );
      case StudioSection.write:
        final target = _writeTarget ?? _defaultWriteTarget(project);
        if (target == null) {
          return _emptySection(
            'Nothing to write yet',
            'Build the structure first; the Write screen follows the scene '
                'you pick there.',
            action: StoryPrimaryButton(
              'Go to Structure',
              onPressed: () => _openSection(StudioSection.structure),
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
      final count = project.beats['${ref.act}-${ref.index}']?.length ?? 0;
      if (count == 0 || project.beatsWritten(ref.act, ref.index) < count) {
        return (act: ref.act, scene: ref.index);
      }
    }
    return last == null ? null : (act: last.act, scene: last.index);
  }

  Widget _emptySection(String title, String body, {Widget? action}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 13.5,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 16), action],
        ],
      ),
    ),
  );
}
