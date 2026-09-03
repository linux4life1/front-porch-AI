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

part of 'story_reader_page.dart';

/// Scene regeneration + text export for [_StoryReaderPageState]: locating the
/// current page's (act, scene) metadata, the regenerate-this-scene confirm
/// dialog + pipeline call, assembling the full story text, and exporting it
/// to a file. Extracted from the inline state methods; direct state access
/// preserves behavior. AppColors + warm-porch accents.
extension _StoryReaderActions on _StoryReaderPageState {
  /// Returns the scene metadata (actIndex, sceneIndex) for the current page, or null if not a prose page.
  ({int actIndex, int sceneIndex})? _getCurrentSceneMeta() {
    if (_pages == null) return null;
    final width = MediaQuery.of(context).size.width;
    final isTwoPageSpread = width > 800;

    final pageIdx = isTwoPageSpread ? _currentPage * 2 : _currentPage;
    if (pageIdx >= _pages!.length) return null;

    final page = _pages![pageIdx];
    if (page.actIndex == null || page.sceneIndex == null) return null;
    return (actIndex: page.actIndex!, sceneIndex: page.sceneIndex!);
  }

  Future<void> _regenCurrentScene() async {
    final meta = _getCurrentSceneMeta();
    if (meta == null) return;

    final repo = Provider.of<StoryRepository>(context, listen: false);
    final pipeline = Provider.of<StoryPipelineService>(context, listen: false);
    final project = repo.getById(widget.projectId);
    if (project == null) return;

    final scene = project.scenes[meta.actIndex]?[meta.sceneIndex];
    if (scene == null) return;

    // Confirm
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(ctx),
        title: Text(
          'Rewrite Scene?',
          style: TextStyle(color: AppColors.textPrimary(ctx)),
        ),
        content: Text(
          'This will regenerate all prose for "${scene.title}". The page will update automatically when done.',
          style: TextStyle(color: AppColors.textSecondary(ctx)),
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
              style: TextStyle(color: AppColors.porchAmberOf(ctx)),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    rebuildState(() => _isRegenerating = true);

    // Clear prose for this scene
    final sId = '${meta.actIndex}-${meta.sceneIndex}';
    final beats = project.beats[sId] ?? [];
    for (int b = 0; b < beats.length; b++) {
      project.prose.remove('$sId-$b');
    }
    await repo.saveProject(project);

    try {
      await pipeline.regenerateSceneProse(
        project,
        meta.actIndex,
        meta.sceneIndex,
      );
      if (mounted) {
        // Force page rebuild
        _pages = null;
        _lastConstraints = null;
        rebuildState(() => _isRegenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ "${scene.title}" rewritten!'),
            backgroundColor: AppColors.surfaceOf(context),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        rebuildState(() => _isRegenerating = false);
        showAiErrorSnackBar(context, e);
      }
    }
  }

  /// Assemble the full story text for export.
  String _assembleFullText(StoryProject project) {
    final buffer = StringBuffer();
    buffer.writeln(project.title.toUpperCase());
    buffer.writeln('=' * project.title.length);
    buffer.writeln();
    buffer.writeln(project.concept);
    buffer.writeln();

    for (int actIdx = 0; actIdx < project.acts.length; actIdx++) {
      final act = project.acts[actIdx];
      final scenes = project.scenes[actIdx] ?? [];

      buffer.writeln();
      buffer.writeln('━' * 60);
      buffer.writeln('ACT ${act.number}: ${act.title.toUpperCase()}');
      buffer.writeln('━' * 60);
      buffer.writeln(act.description);
      buffer.writeln();

      for (int sceneIdx = 0; sceneIdx < scenes.length; sceneIdx++) {
        final scene = scenes[sceneIdx];
        final sId = '$actIdx-$sceneIdx';
        final beats = project.beats[sId] ?? [];

        buffer.writeln();
        buffer.writeln('— ${scene.title} —');
        buffer.writeln();

        for (int beatIdx = 0; beatIdx < beats.length; beatIdx++) {
          final bId = '$sId-$beatIdx';
          final prose =
              project.prose[bId]?.final_ ?? project.prose[bId]?.draft ?? '';
          if (prose.isNotEmpty) {
            buffer.writeln(prose);
            buffer.writeln();
          }
        }
      }
    }

    buffer.writeln();
    buffer.writeln('THE END');

    return buffer.toString();
  }

  Future<void> _exportStory() async {
    final repo = Provider.of<StoryRepository>(context, listen: false);
    final project = repo.getById(widget.projectId);
    if (project == null) return;

    final text = _assembleFullText(project);
    final fileName =
        '${project.title.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_')}.txt';

    try {
      final outputPath = await PickerPrefs.saveFile(
        category: PickerPrefs.catExport,
        bytes: Uint8List.fromList(utf8.encode(text)),
        dialogTitle: 'Export Story',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['txt', 'md'],
      );

      if (outputPath != null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('📖 Exported to $outputPath')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }
}
