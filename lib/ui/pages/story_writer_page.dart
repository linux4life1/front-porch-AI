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
// but WITHOUT ANY WARRANTY, without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

part 'story_writer_page.beats.dart';

/// Writer page — beat-by-beat prose view with draft/edit/regenerate controls.
class StoryWriterPage extends StatefulWidget {
  final String projectId;
  final int actIndex;
  final int sceneIndex;

  const StoryWriterPage({
    super.key,
    required this.projectId,
    required this.actIndex,
    required this.sceneIndex,
  });

  @override
  State<StoryWriterPage> createState() => _StoryWriterPageState();
}

class _StoryWriterPageState extends State<StoryWriterPage> {
  final ScrollController _scrollController = ScrollController();

  /// Class door for the beats part extension — [setState] is @protected
  /// and cannot be called from an extension.
  void rebuildState(VoidCallback fn) => setState(fn);

  String get _sId => '${widget.actIndex}-${widget.sceneIndex}';

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<StoryRepository, StoryPipelineService>(
      builder: (context, repo, pipeline, child) {
        final project = repo.getById(widget.projectId);
        if (project == null) {
          return const Scaffold(body: Center(child: Text('Project not found')));
        }

        final scene = project.scenes[widget.actIndex]?[widget.sceneIndex];
        if (scene == null) {
          return const Scaffold(body: Center(child: Text('Scene not found')));
        }

        final beats = project.beats[_sId] ?? [];

        return Scaffold(
          backgroundColor: AppColors.backgroundOf(context),
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(scene.title, style: const TextStyle(fontSize: 16)),
                Text(
                  'Act ${widget.actIndex + 1}, Scene ${widget.sceneIndex + 1} • ${scene.location}',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary(context),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.cardOf(context),
            foregroundColor: AppColors.textPrimary(context),
            elevation: 0,
            actions: [
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
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert,
                  color: AppColors.iconSecondary(context),
                ),
                color: AppColors.surfaceContainerOf(context),
                onSelected: (v) => _handleMenuAction(v, project, pipeline),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'copy',
                    child: ListTile(
                      leading: Icon(Icons.copy, size: 18),
                      title: Text(
                        'Copy Scene Text',
                        style: TextStyle(fontSize: 13),
                      ),
                      dense: true,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'export',
                    child: ListTile(
                      leading: Icon(Icons.save_alt, size: 18),
                      title: Text(
                        'Export Scene',
                        style: TextStyle(fontSize: 13),
                      ),
                      dense: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: pipeline.isRunning
              ? _buildRunningState(pipeline)
              : _buildBeatList(project, beats, pipeline),
        );
      },
    );
  }

  Widget _buildRunningState(StoryPipelineService pipeline) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: AppColors.porchHoneyOf(context),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            pipeline.currentStep,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            pipeline.statusMessage,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBeatList(
    StoryProject project,
    List<StoryBeat> beats,
    StoryPipelineService pipeline,
  ) {
    if (beats.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.view_timeline,
              size: 64,
              color: AppColors.porchHoneyOf(context).withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No beats yet',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Generate beats to break this scene into narrative units',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: beats.length,
      itemBuilder: (context, idx) =>
          _buildBeatCard(project, beats[idx], idx, pipeline),
    );
  }
}
