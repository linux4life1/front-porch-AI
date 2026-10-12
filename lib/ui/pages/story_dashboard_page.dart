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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/story/story.dart';
import 'package:front_porch_ai/ui/pages/story_dashboard/story_dashboard.dart';
import 'package:front_porch_ai/ui/pages/story_reader_page.dart';
import 'package:front_porch_ai/ui/pages/story_structure_page.dart';
import 'package:front_porch_ai/ui/pages/story_writer_page.dart';
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

export 'package:front_porch_ai/ui/pages/story_dashboard/studio_overview_cards.dart'
    show distilledEventCount;

/// The studio (sketch M): one header for the whole story, the sidebar, and
/// the selected section. The web twin is StudioShell.tsx + the section
/// pages.
class StoryDashboardPage extends StatefulWidget {
  final String projectId;
  final bool autoRunStoryArchitect;

  /// Which section to open first (the shelf's Read, a deep link).
  final StudioSection? openSection;

  const StoryDashboardPage({
    super.key,
    required this.projectId,
    this.autoRunStoryArchitect = false,
    this.openSection,
  });

  @override
  State<StoryDashboardPage> createState() => _StoryDashboardPageState();
}

class _StoryDashboardPageState extends State<StoryDashboardPage> {
  late StudioSection _section = widget.openSection ?? StudioSection.overview;

  /// The scene the Write screen shows; null picks the next unfinished one.
  ({int act, int scene})? _writeTarget;
  bool _hasAutoRun = false;

  /// The reader folds the sidebar away; ☰ in its bar brings it back.
  bool _sidebarShown = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.autoRunStoryArchitect && !_hasAutoRun) {
      _hasAutoRun = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _actions.runStoryArchitect(),
      );
    }
  }

  StoryStudioActions get _actions => StoryStudioActions(
    context: context,
    projectId: widget.projectId,
    onChanged: () => setState(() {}),
  );

  void _open(StudioSection s) => setState(() {
    _section = s;
    _sidebarShown = s != StudioSection.read;
  });

  @override
  Widget build(BuildContext context) {
    return Consumer2<StoryRepository, StoryPipelineService>(
      builder: (context, repo, pipeline, child) {
        final project = repo.getById(widget.projectId);
        if (project == null) {
          return StudioTheme(
            child: Scaffold(
              backgroundColor: StudioColors.bgOf(context),
              body: Center(
                child: Text(
                  'This story is gone.',
                  style: StudioType.ui(
                    context,
                    color: StudioColors.mutedOf(context),
                  ),
                ),
              ),
            ),
          );
        }
        final narrow =
            MediaQuery.of(context).size.width < kStudioSidebarBreakpoint;
        final sidebar = StudioSidebar(
          project: project,
          selected: _section,
          onSelect: _open,
          horizontal: narrow,
        );
        return StudioTheme(
          child: Scaffold(
            backgroundColor: StudioColors.bgOf(context),
            body: Column(
              children: [
                StudioHeader(
                  project: project,
                  pipeline: pipeline,
                  actions: _actions,
                ),
                _buildProgress(project),
                if (narrow && _sidebarShown) sidebar,
                Expanded(
                  child: narrow || !_sidebarShown
                      ? _buildSection(project, pipeline)
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            sidebar,
                            Expanded(child: _buildSection(project, pipeline)),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProgress(StoryProject project) {
    final st = storyShelfStatus(project);
    return StoryProgressBar(st.fraction, done: st.done);
  }

  void _openWriter(int act, int scene) => setState(() {
    _writeTarget = (act: act, scene: scene);
    _section = StudioSection.write;
  });

  Widget _buildSection(StoryProject project, StoryPipelineService pipeline) {
    switch (_section) {
      case StudioSection.overview:
        return StudioOverview(
          project: project,
          pipeline: pipeline,
          actions: _actions,
          onOpen: _open,
        );
      case StudioSection.read:
        return StoryReaderPage(
          key: ValueKey('reader-${project.dbId}'),
          projectId: widget.projectId,
          embedded: true,
          onToggleSidebar: () => setState(() => _sidebarShown = !_sidebarShown),
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
