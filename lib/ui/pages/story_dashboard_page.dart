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
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/audiobook_generator_service.dart';
import 'package:front_porch_ai/services/epub_generator_service.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/story/story.dart';
import 'package:front_porch_ai/ui/pages/story_home_view.dart';
import 'package:front_porch_ai/ui/pages/story_reader_page.dart';
import 'package:front_porch_ai/ui/pages/story_setup_page.dart';
import 'package:front_porch_ai/ui/pages/story_structure_page.dart';
import 'package:front_porch_ai/ui/pages/story_writer_page.dart';
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';

part 'story_dashboard_page.shell.dart';
part 'story_dashboard_page.overview.dart';
part 'story_dashboard_page.up_next.dart';
part 'story_dashboard_page.actions.dart';

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
      WidgetsBinding.instance.addPostFrameCallback((_) => _runStoryArchitect());
    }
  }

  StoryProject? get _project => Provider.of<StoryRepository>(
    context,
    listen: false,
  ).getById(widget.projectId);

  /// Re-exposes the protected [setState] for the `part of` extensions.
  void rebuildState(VoidCallback fn) => setState(fn);

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
                _buildHeader(project, pipeline),
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
}
