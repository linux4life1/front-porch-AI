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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/pages/story_writer_page.dart';
import 'package:front_porch_ai/ui/pages/story_reader_page.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

part 'story_structure_page.tree.dart';

/// Structure page — act/scene tree with valence indicators and generation controls.
class StoryStructurePage extends StatefulWidget {
  final String projectId;
  const StoryStructurePage({super.key, required this.projectId});

  @override
  State<StoryStructurePage> createState() => _StoryStructurePageState();
}

class _StoryStructurePageState extends State<StoryStructurePage> {
  int _expandedActIndex = -1;

  /// Class door for the tree part extension — [setState] is @protected
  /// and cannot be called from an extension.
  void rebuildState(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) {
    return Consumer2<StoryRepository, StoryPipelineService>(
      builder: (context, repo, pipeline, child) {
        final project = repo.getById(widget.projectId);
        if (project == null) {
          return const Scaffold(body: Center(child: Text('Project not found')));
        }

        return Scaffold(
          backgroundColor: AppColors.backgroundOf(context),
          appBar: AppBar(
            title: Text('Structure — ${project.title}'),
            backgroundColor: AppColors.cardOf(context),
            foregroundColor: AppColors.textPrimary(context),
            elevation: 0,
            actions: [
              // Show Read button when any act has prose
              if (project.prose.isNotEmpty)
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          StoryReaderPage(projectId: widget.projectId),
                    ),
                  ),
                  icon: Icon(
                    Icons.auto_stories,
                    size: 18,
                    color: AppColors.porchHoneyOf(context),
                  ),
                  label: Text(
                    'Read Story',
                    style: TextStyle(color: AppColors.porchHoneyOf(context)),
                  ),
                ),
            ],
          ),
          body: pipeline.isRunning
              ? _buildRunningOverlay(pipeline)
              : _buildStructureTree(project, pipeline),
        );
      },
    );
  }

  Widget _buildRunningOverlay(StoryPipelineService pipeline) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.porchHoneyOf(context),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              pipeline.currentStep,
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              pipeline.statusMessage,
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            if (pipeline.tokenCount > 0) ...[
              const SizedBox(height: 16),
              Text(
                '${pipeline.tokenCount} tokens generated',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _generateFullAct(
    StoryProject project,
    int actIdx,
    StoryPipelineService pipeline,
  ) async {
    try {
      await pipeline.generateFullAct(project, actIdx);
      if (mounted) {
        setState(() => _expandedActIndex = actIdx);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Act ${actIdx + 1} complete! Review the scenes below.',
            ),
            backgroundColor: AppColors.surfaceContainerOf(context),
          ),
        );
      }
    } catch (e) {
      if (mounted) showAiErrorSnackBar(context, e);
    }
  }

  Future<void> _regenerateScene(
    StoryProject project,
    int actIdx,
    int sceneIdx,
    StoryPipelineService pipeline,
  ) async {
    final scene = project.scenes[actIdx]?[sceneIdx];
    if (scene == null) return;

    // Confirm with user
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(context),
        title: Text(
          'Rewrite Scene?',
          style: TextStyle(color: AppColors.textPrimary(context)),
        ),
        content: Text(
          'This will regenerate all prose for "${scene.title}" using the new per-beat system. The old text will be replaced.',
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Rewrite',
              style: TextStyle(color: AppColors.taskAccentOf(context)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Clear prose for this scene only
    final sId = '$actIdx-$sceneIdx';
    final beats = project.beats[sId] ?? [];
    for (int b = 0; b < beats.length; b++) {
      project.prose.remove('$sId-$b');
    }

    // Save the cleared state
    final repo = Provider.of<StoryRepository>(context, listen: false);
    await repo.saveProject(project);

    // Re-run prose generation for this scene
    try {
      await pipeline.regenerateSceneProse(project, actIdx, sceneIdx);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ "${scene.title}" rewritten!'),
            backgroundColor: AppColors.surfaceContainerOf(context),
          ),
        );
      }
    } catch (e) {
      if (mounted) showAiErrorSnackBar(context, e);
    }
  }
}
