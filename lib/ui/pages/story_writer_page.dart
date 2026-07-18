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
import 'package:path_provider/path_provider.dart';
import 'package:front_porch_ai/services/story_repository.dart';
import 'package:front_porch_ai/services/story_pipeline_service.dart';
import 'package:front_porch_ai/models/story_project.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/ai_engine_status_card.dart';

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

  Widget _buildBeatCard(
    StoryProject project,
    StoryBeat beat,
    int idx,
    StoryPipelineService pipeline,
  ) {
    final bId = '$_sId-$idx';
    final prose = project.prose[bId];
    final hasProse = prose?.final_ != null;

    return Card(
      color: AppColors.cardOf(context),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: hasProse
              ? AppColors.bondHighOf(context).withValues(alpha: 0.25)
              : AppColors.borderOf(context).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Beat header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _beatTypeColor(beat.type).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    beat.type,
                    style: TextStyle(
                      color: _beatTypeColor(beat.type),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Beat ${idx + 1}',
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                // Pacing indicator
                Icon(
                  beat.pacing == 0
                      ? Icons.speed
                      : (beat.pacing == 2 ? Icons.flash_on : Icons.balance),
                  size: 16,
                  color: AppColors.iconSecondary(context),
                ),
                const SizedBox(width: 8),
                // Valence
                Text(
                  beat.valence > 0 ? '+${beat.valence}' : '${beat.valence}',
                  style: TextStyle(
                    color: (beat.valence > 0
                            ? AppColors.bondHighOf(context)
                            : AppColors.negativeAccentOf(context))
                        .withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // Beat description
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              beat.description,
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),

          // Prose content
          if (hasProse)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.sunkenSurfaceOf(context),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  prose!.final_!,
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 14,
                    height: 1.7,
                    fontFamily: 'serif',
                  ),
                ),
              ),
            ),

          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!hasProse)
                  TextButton.icon(
                    onPressed: pipeline.isRunning
                        ? null
                        : () => _writeBeat(project, idx, pipeline),
                    icon: const Icon(Icons.edit, size: 14),
                    label: const Text('Write', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.porchHoneyOf(context),
                    ),
                  ),
                if (hasProse) ...[
                  TextButton.icon(
                    onPressed: pipeline.isRunning
                        ? null
                        : () => _writeBeat(project, idx, pipeline),
                    icon: const Icon(Icons.refresh, size: 14),
                    label: const Text(
                      'Rewrite',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textTertiary(context),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: prose!.final_!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Copied!'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 14),
                    label: const Text('Copy', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textTertiary(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _beatTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'action':
        return AppColors.negativeAccentOf(context);
      case 'reaction':
        return AppColors.frostAccentOf(context);
      case 'dialogue':
        return AppColors.porchHoneyOf(context);
      case 'revelation':
        return AppColors.fixationAccentOf(context);
      case 'resolution':
        return AppColors.bondHighOf(context);
      default:
        return AppColors.textTertiary(context);
    }
  }

  Future<void> _generateBeats(
    StoryProject project,
    StoryPipelineService pipeline,
  ) async {
    try {
      await pipeline.runBeatDirector(
        project,
        widget.actIndex,
        widget.sceneIndex,
      );
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showAiErrorSnackBar(context, e);
    }
  }

  Future<void> _writeBeat(
    StoryProject project,
    int beatIdx,
    StoryPipelineService pipeline,
  ) async {
    try {
      await pipeline.runDraftAndEdit(
        project,
        widget.actIndex,
        widget.sceneIndex,
        beatIdx,
      );
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showAiErrorSnackBar(context, e);
    }
  }

  Future<void> _autoWriteScene(
    StoryProject project,
    StoryPipelineService pipeline,
  ) async {
    try {
      await pipeline.autoWriteScene(
        project,
        widget.actIndex,
        widget.sceneIndex,
      );
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Scene complete!'),
            backgroundColor: AppColors.surfaceContainerOf(context),
          ),
        );
      }
    } catch (e) {
      if (mounted) showAiErrorSnackBar(context, e);
    }
  }

  void _handleMenuAction(
    String action,
    StoryProject project,
    StoryPipelineService pipeline,
  ) {
    final sceneText = _getSceneText(project);
    switch (action) {
      case 'copy':
        Clipboard.setData(ClipboardData(text: sceneText));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Scene text copied!'),
            duration: Duration(seconds: 1),
          ),
        );
        break;
      case 'export':
        _exportScene(project, sceneText);
        break;
    }
  }

  String _getSceneText(StoryProject project) {
    final beats = project.beats[_sId] ?? [];
    final buffer = StringBuffer();
    for (int i = 0; i < beats.length; i++) {
      final prose = project.prose['$_sId-$i'];
      if (prose?.final_ != null) {
        buffer.writeln(prose!.final_);
        buffer.writeln();
      }
    }
    return buffer.toString();
  }

  Future<void> _exportScene(StoryProject project, String text) async {
    try {
      final scene = project.scenes[widget.actIndex]![widget.sceneIndex];
      final dir = await getApplicationDocumentsDirectory();
      final file = File(
        '${dir.path}/${project.title}_${scene.title}.txt'.replaceAll(
          RegExp(r'[^\w\s.]'),
          '_',
        ),
      );
      await file.writeAsString(text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported to ${file.path}'),
            backgroundColor: AppColors.surfaceContainerOf(context),
          ),
        );
      }
    } catch (e) {
      if (mounted) showAiErrorSnackBar(context, e);
    }
  }
}
