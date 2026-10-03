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

/// Text export for [_StoryReaderPageState]: assembling the full story text
/// and saving it. Rewriting a scene lives in Structure and Write, not here.
extension _StoryReaderActions on _StoryReaderPageState {
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
