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

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/pages/story_structure_page.dart';
import 'package:front_porch_ai/ui/pages/story_reader_page.dart';
import 'package:front_porch_ai/services/audiobook_generator_service.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/services/epub_generator_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/utils.dart';

// The pipeline actions, body composition, chat-history preview, editable act
// cards, and bible display cards live in these `part of` files (extensions on
// _StoryDashboardPageState) to keep every file under the 500-LOC cap — same
// pattern chat_service.dart / settings_page.dart use. They share this
// library's imports and access the page's private state directly, so
// behavior is unchanged.
part 'story_dashboard_page.actions.dart';
part 'story_dashboard_page.body.dart';
part 'story_dashboard_page.chat_history.dart';
part 'story_dashboard_page.act_cards.dart';
part 'story_dashboard_page.bible_cards.dart';

/// Dashboard page — story bible overview: concept, themes, cast, threads, lore.
class StoryDashboardPage extends StatefulWidget {
  final String projectId;
  final bool autoRunStoryArchitect;

  const StoryDashboardPage({
    super.key,
    required this.projectId,
    this.autoRunStoryArchitect = false,
  });

  @override
  State<StoryDashboardPage> createState() => _StoryDashboardPageState();
}

class _StoryDashboardPageState extends State<StoryDashboardPage> {
  bool _hasAutoRun = false;
  bool _showChatPreview = false;
  List<String> _chatPreviewMessages = [];
  bool _loadingChatPreview = false;

  // Editable act controllers
  final Map<int, TextEditingController> _actTitleControllers = {};
  final Map<int, TextEditingController> _actDescControllers = {};

  // Relocated from its original mid-file position under the CHAT HISTORY
  // PREVIEW banner (now story_dashboard_page.chat_history.dart) — extensions
  // cannot hold fields, so this lives here with the rest of the state.
  bool _showRawMessages = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.autoRunStoryArchitect && !_hasAutoRun) {
      _hasAutoRun = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _runStoryArchitect());
    }
  }

  @override
  void dispose() {
    for (final c in _actTitleControllers.values) {
      c.dispose();
    }
    for (final c in _actDescControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  StoryProject? get _project => Provider.of<StoryRepository>(
    context,
    listen: false,
  ).getById(widget.projectId);

  /// Re-exposes the protected [setState] for the `part of` extensions
  /// (`story_dashboard_page.*.dart`), which hold the pipeline actions, chat
  /// history preview, and editable cards but can't call a State's protected
  /// members directly.
  void rebuildState(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) {
    return Consumer2<StoryRepository, StoryPipelineService>(
      builder: (context, repo, pipeline, child) {
        final project = repo.getById(widget.projectId);
        if (project == null) {
          return Scaffold(
            body: Center(
              child: Text(
                'Project not found',
                style: TextStyle(color: AppColors.textSecondary(context)),
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: AppColors.backgroundOf(context),
          appBar: AppBar(
            title: Text(project.title),
            backgroundColor: AppColors.surfaceContainerOf(context),
            foregroundColor: AppColors.textPrimary(context),
            elevation: 0,
            actions: [
              if (project.acts.isNotEmpty)
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          StoryReaderPage(projectId: widget.projectId),
                    ),
                  ),
                  icon: Icon(
                    Icons.menu_book,
                    color: AppColors.porchHoneyOf(context),
                  ),
                  label: Text(
                    'Read',
                    style: TextStyle(
                      color: AppColors.porchHoneyOf(context),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (project.acts.isNotEmpty)
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          StoryStructurePage(projectId: widget.projectId),
                    ),
                  ),
                  icon: Icon(
                    Icons.account_tree,
                    color: AppColors.textSecondary(context),
                  ),
                  label: Text(
                    'Structure',
                    style: TextStyle(color: AppColors.textSecondary(context)),
                  ),
                ),
            ],
          ),
          body: _buildBody(project, pipeline),
        );
      },
    );
  }
}
