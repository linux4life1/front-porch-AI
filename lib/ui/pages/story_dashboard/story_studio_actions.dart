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
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Pipeline actions and exports for the studio. Every destructive action
/// confirms in the studio dialog and says what is lost (sketch V).
///
/// [context] is the studio page's own; [onChanged] asks the page to
/// rebuild after a run or a save lands.
class StoryStudioActions {
  final BuildContext context;
  final String projectId;
  final VoidCallback onChanged;

  const StoryStudioActions({
    required this.context,
    required this.projectId,
    required this.onChanged,
  });

  StoryProject? get _project =>
      Provider.of<StoryRepository>(context, listen: false).getById(projectId);

  StoryPipelineService get _pipeline =>
      Provider.of<StoryPipelineService>(context, listen: false);

  Future<void> runStoryArchitect() async {
    final project = _project;
    if (project == null) return;
    try {
      if (project.useChatHistory &&
          project.chatHistoryCharacterIds.isNotEmpty &&
          project.distilledTimeline.isEmpty) {
        await _pipeline.runChatDistiller(project);
      }
      await _pipeline.runStoryArchitect(project);
      if (context.mounted) onChanged();
    } catch (e) {
      if (context.mounted) showAiErrorSnackBar(context, e);
    }
  }

  Future<void> regenerateBible(StoryProject project) async {
    final written = project.orderedScenes
        .where((s) => project.beatsWritten(s.act, s.index) > 0)
        .length;
    final ok = await showStoryConfirm(
      context,
      title: 'Regenerate the bible?',
      body:
          'This rewrites the cast, themes, threads and lore from your idea. '
          '${written > 0 ? 'Your $written written scene${written == 1 ? '' : 's'} stay but may no longer match. ' : ''}'
          'Interviews and portraits are kept.',
      confirmLabel: 'Regenerate',
      destructive: true,
    );
    if (!ok) return;
    await runStoryArchitect();
  }

  Future<void> rewriteArc(StoryProject project) async {
    final written = project.orderedScenes
        .where((s) => project.beatsWritten(s.act, s.index) > 0)
        .length;
    final ok = await showStoryConfirm(
      context,
      title: 'Rewrite the arc?',
      body:
          'This rewrites the inciting incident, themes, twists and threads '
          'together, to fit your world and cast. The world, cast and '
          'interviews stay as they are.'
          '${project.acts.isEmpty ? '' : ' Your acts${written > 0 ? ' and $written written scene${written == 1 ? '' : 's'}' : ''} stay but may no longer match.'}',
      confirmLabel: 'Rewrite',
    );
    if (!ok) return;
    try {
      await _pipeline.runStoryArc(project);
      if (context.mounted) onChanged();
    } catch (e) {
      if (context.mounted) showAiErrorSnackBar(context, e);
    }
  }

  Future<void> redistill(StoryProject project) async {
    final ok = await showStoryConfirm(
      context,
      title: 'Redistill the chat?',
      body:
          'The timeline is rebuilt from the chat. The bible is not changed; '
          'regenerate it afterwards if the timeline moved.',
      confirmLabel: 'Redistill',
    );
    if (!ok) return;
    try {
      project.distilledTimeline = '';
      await _pipeline.runChatDistiller(project);
      if (context.mounted) onChanged();
    } catch (e) {
      if (context.mounted) showAiErrorSnackBar(context, e);
    }
  }

  Future<void> buildActs(StoryProject project) async {
    try {
      await _pipeline.runActStructurer(project);
      if (context.mounted) onChanged();
    } catch (e) {
      if (context.mounted) showAiErrorSnackBar(context, e);
    }
  }

  Future<void> continueWriting(StoryProject project) async {
    try {
      final wrote = await _pipeline.writeNextScene(project);
      if (!context.mounted) return;
      if (!wrote) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The whole story is written.')),
        );
      }
      onChanged();
    } catch (e) {
      if (context.mounted) showAiErrorSnackBar(context, e);
    }
  }

  Future<void> autopilot(StoryProject project) async {
    final total = project.orderedScenes.length;
    final written = project.orderedScenes
        .where((s) => project.beatsWritten(s.act, s.index) > 0)
        .length;
    final left = total - written;
    final ok = await showStoryConfirm(
      context,
      title: 'Write the whole story?',
      body: total == 0
          ? 'Autopilot builds the acts, outlines every sequence and writes '
                'every scene, one after another'
                '${project.reviewEnabled ? ', with reviews on' : ''}. You can '
                'stop at any time and keep what\'s done.'
          : 'Autopilot writes the $left scene${left == 1 ? '' : 's'} that '
                '${left == 1 ? 'is' : 'are'} left, one after another'
                '${project.reviewEnabled ? ', with reviews on' : ''}. It will '
                'not touch the $written already written or the bible. You can '
                'stop at any time and keep what\'s done.',
      confirmLabel: 'Start',
    );
    if (!ok) return;
    try {
      await _pipeline.runAutopilot(project);
      if (context.mounted) onChanged();
    } catch (e) {
      if (context.mounted) showAiErrorSnackBar(context, e);
    }
  }

  Future<void> deleteStory(StoryProject project) async {
    final words = project.wordCount;
    final ok = await showStoryConfirm(
      context,
      title: 'Delete ${project.title}?',
      body: words > 0
          ? '${thousands(words)} words, its bible and its run log will be '
                'removed. This cannot be undone.'
          : 'Its setup and bible will be removed. This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await Provider.of<StoryRepository>(
      context,
      listen: false,
    ).deleteProject(project.dbId!);
    if (context.mounted) Navigator.of(context).pop();
  }

  // ── Exports: one implementation, reached from the header ⋯ and the reader.

  Future<void> exportAudiobook(StoryProject project) async {
    final service = Provider.of<AudiobookGeneratorService>(
      context,
      listen: false,
    );
    try {
      final audiobook = await service.generateAudiobook(project);
      if (audiobook == null || !context.mounted) return;
      final wav = await audiobook.file.readAsBytes();
      final out = await GuardedPicker.saveFile(
        context,
        category: PickerPrefs.catExport,
        bytes: wav,
        dialogTitle: 'Save audiobook',
        fileName: 'audiobook_${project.title.replaceAll(' ', '_')}.wav',
        type: FileType.custom,
        allowedExtensions: ['wav'],
      );
      if (out != null && context.mounted) _saved('Audiobook saved to $out');
    } catch (e) {
      if (context.mounted) showAiErrorSnackBar(context, e);
    }
  }

  Future<void> exportEpub(StoryProject project) async {
    try {
      final epub = await EpubGeneratorService.generateEpub(project);
      if (epub == null || !context.mounted) return;
      final out = await GuardedPicker.saveFile(
        context,
        category: PickerPrefs.catExport,
        bytes: Uint8List.fromList(epub.bytes),
        dialogTitle: 'Save eBook',
        fileName: '${project.title.replaceAll(' ', '_')}.epub',
        type: FileType.custom,
        allowedExtensions: ['epub'],
      );
      if (out != null && context.mounted) _saved('eBook saved to $out');
    } catch (e) {
      if (context.mounted) showAiErrorSnackBar(context, e);
    }
  }

  Future<void> exportText(StoryProject project) async {
    try {
      final md = _pipeline.exportAsMarkdown(project);
      final out = await GuardedPicker.saveFile(
        context,
        category: PickerPrefs.catExport,
        bytes: Uint8List.fromList(utf8.encode(md)),
        dialogTitle: 'Save text',
        fileName: '${project.title.replaceAll(' ', '_')}.md',
        type: FileType.custom,
        allowedExtensions: ['md'],
      );
      if (out != null && context.mounted) _saved('Text saved to $out');
    } catch (e) {
      if (context.mounted) showAiErrorSnackBar(context, e);
    }
  }

  void _saved(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> editBibleField(
    StoryProject project,
    String label,
    String value,
    void Function(String) set,
  ) async {
    final ctl = TextEditingController(text: value);
    final ok = await showStoryDialog<bool>(
      context,
      title: label,
      width: 520,
      body: StoryTextArea(controller: ctl, minLines: 4, prose: true),
      actions: (ctx) => [
        StoryButton.ghost('Cancel', onPressed: () => Navigator.pop(ctx, false)),
        StoryButton.primary('Save', onPressed: () => Navigator.pop(ctx, true)),
      ],
    );
    if (ok != true || !context.mounted) return;
    set(ctl.text.trim());
    await Provider.of<StoryRepository>(
      context,
      listen: false,
    ).saveProject(project);
    onChanged();
  }
}
