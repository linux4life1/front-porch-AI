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
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Assemble the full story text for export.
String assembleStoryText(StoryProject project) {
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

/// Saves [project]'s full text through the export picker and reports the
/// result in a snack bar.
Future<void> exportStoryText(BuildContext context, StoryProject project) async {
  final text = assembleStoryText(project);
  final fileName =
      '${project.title.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_')}.txt';

  try {
    final outputPath = await GuardedPicker.saveFile(
      context,
      category: PickerPrefs.catExport,
      bytes: Uint8List.fromList(utf8.encode(text)),
      dialogTitle: 'Export Story',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['txt', 'md'],
    );

    if (outputPath != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('📖 Exported to $outputPath')));
      }
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }
}
