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

/// Beat cards, write/rewrite actions, and scene export for [StoryWriterPage].
extension _StoryWriterBeats on _StoryWriterPageState {
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
                    color:
                        (beat.valence > 0
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
      if (mounted) rebuildState(() {});
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
      if (mounted) rebuildState(() {});
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
        rebuildState(() {});
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
        storySceneExportPath(dir.path, project.title, scene.title),
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

/// Absolute path a scene export is written to: [dirPath] plus a sanitized
/// `<project>_<scene>.txt` file name.
///
/// Only the FILE NAME may be sanitized. The sanitizer used to run over the
/// whole interpolated path, so every separator (and the Windows drive colon)
/// became `_` and the export landed in the process working directory under a
/// mangled name — invisible on macOS/Linux, an access-denied write on Windows
/// where the CWD is the install folder.
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
