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

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/story/story.dart';
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// "Go to scene": the chosen scene, or null on Cancel.
Future<SceneRef?> showStoryScenePicker(
  BuildContext context,
  StoryProject project,
) => showStoryDialog<SceneRef>(
  context,
  title: 'Go to scene',
  width: 460,
  body: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final ref in project.orderedScenes)
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => Navigator.pop(context, ref),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text(
                    project.sceneLabel(ref.act, ref.index),
                    style: StudioType.mono(context),
                  ),
                ),
                Expanded(
                  child: Text(
                    ref.scene.title,
                    overflow: TextOverflow.ellipsis,
                    style: StudioType.ui(context),
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  ),
  actions: (ctx) => [
    StoryButton.ghost('Cancel', onPressed: () => Navigator.pop(ctx)),
  ],
);

/// "Rewrite beat N with a note": the trimmed note, or null on Cancel.
Future<String?> showStoryRewriteNoteDialog(BuildContext context, int b) async {
  final note = TextEditingController();
  final ok = await showStoryDialog<bool>(
    context,
    title: 'Rewrite beat ${b + 1} with a note',
    width: 460,
    body: StoryTextArea(
      controller: note,
      hint:
          'What should change? e.g. slower, let Joss speak first, less '
          'smoke',
      minLines: 3,
    ),
    actions: (ctx) => [
      StoryButton.ghost('Cancel', onPressed: () => Navigator.pop(ctx, false)),
      StoryButton.primary('Rewrite', onPressed: () => Navigator.pop(ctx, true)),
    ],
  );
  if (ok != true) return null;
  return note.text.trim();
}

/// Hand-edit a beat's text: the trimmed text, or null on Cancel.
Future<String?> showStoryEditBeatDialog(
  BuildContext context,
  int b,
  String text,
) async {
  final ctl = TextEditingController(text: text);
  final ok = await showStoryDialog<bool>(
    context,
    title: 'Beat ${b + 1}',
    width: 640,
    body: StoryTextArea(controller: ctl, minLines: 10, prose: true),
    actions: (ctx) => [
      StoryButton.ghost('Cancel', onPressed: () => Navigator.pop(ctx, false)),
      StoryButton.primary('Save', onPressed: () => Navigator.pop(ctx, true)),
    ],
  );
  if (ok != true) return null;
  return ctl.text.trim();
}

/// Edit the user's own "Phrases to avoid": the new list, or null on Cancel.
Future<List<String>?> showStoryBannedPhrasesDialog(
  BuildContext context,
  StoryProject project,
) async {
  final controller = TextEditingController(
    text: project.bannedPhrases.join('\n'),
  );
  final ok = await showStoryDialog<bool>(
    context,
    title: 'Phrases to avoid',
    width: 420,
    body: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'One per line. The engine adds its own as it notices repeats; '
          'yours stay for the whole story.',
          style: StudioType.ui(
            context,
            size: 12.5,
            color: StudioColors.mutedOf(context),
          ),
        ),
        const SizedBox(height: 10),
        StoryTextArea(controller: controller, minLines: 5),
        if (project.autoBannedPhrases.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Noticed lately: ${project.autoBannedPhrases.join(', ')}',
            style: StudioType.ui(
              context,
              size: 12.5,
              color: StudioColors.mutedOf(context),
            ),
          ),
        ],
      ],
    ),
    actions: (ctx) => [
      StoryButton.ghost('Cancel', onPressed: () => Navigator.pop(ctx, false)),
      StoryButton.primary('Save', onPressed: () => Navigator.pop(ctx, true)),
    ],
  );
  if (ok != true) return null;
  return controller.text
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

/// The writing-lens picker: a lens id, `'+'` for "Add your own lens", or
/// null on Cancel.
Future<String?> showStoryLensPicker(
  BuildContext context,
  StoryProject project,
  String current,
) => showStoryDialog<String>(
  context,
  title: 'Writing lens for this scene',
  width: 480,
  body: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final lens in StoryLenses.forProject(project))
        InkWell(
          key: ValueKey('story-lens-${lens.id}'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => Navigator.pop(context, lens.id),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: lens.id == current
                ? BoxDecoration(
                    color: StudioColors.raiseOf(context),
                    borderRadius: BorderRadius.circular(8),
                  )
                : null,
            child: Row(
              children: [
                StoryLensMark(lens.id),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: lens.name,
                          style: StudioType.ui(
                            context,
                            weight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(
                          text: '  ${lens.context}',
                          style: StudioType.ui(
                            context,
                            size: 12,
                            color: StudioColors.mutedOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  ),
  actions: (ctx) => [
    StoryButton.ghost(
      'Add your own lens',
      onPressed: () => Navigator.pop(ctx, '+'),
    ),
    StoryButton.ghost('Cancel', onPressed: () => Navigator.pop(ctx)),
  ],
);

/// A lens of the user's own: a name, when to use it, how to write in it.
/// Null on Cancel or when the name is left empty.
Future<StoryLens?> showStoryCustomLensDialog(BuildContext context) async {
  final name = TextEditingController();
  final when = TextEditingController();
  final how = TextEditingController();
  final ok = await showStoryDialog<bool>(
    context,
    title: 'Your own lens',
    width: 460,
    body: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        StoryField(controller: name, hint: 'Name'),
        const SizedBox(height: 8),
        StoryField(controller: when, hint: 'When to use it (one line)'),
        const SizedBox(height: 8),
        StoryTextArea(
          controller: how,
          hint:
              'How to write in it: sentence rhythm, what the narration '
              'notices, how people talk…',
          minLines: 4,
        ),
      ],
    ),
    actions: (ctx) => [
      StoryButton.ghost('Cancel', onPressed: () => Navigator.pop(ctx, false)),
      StoryButton.primary(
        'Save lens',
        onPressed: () => Navigator.pop(ctx, true),
      ),
    ],
  );
  if (ok != true || name.text.trim().isEmpty) return null;
  return StoryLens(
    id: StoryLenses.normalizeId(name.text),
    name: name.text.trim(),
    context: when.text.trim(),
    prompt: how.text.trim(),
  );
}
