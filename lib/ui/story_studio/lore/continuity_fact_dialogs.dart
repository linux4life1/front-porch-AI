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
import 'package:front_porch_ai/ui/story_studio/studio_buttons.dart';
import 'package:front_porch_ai/ui/story_studio/studio_cards.dart';
import 'package:front_porch_ai/ui/story_studio/studio_theme.dart';
import 'package:front_porch_ai/ui/story_studio/studio_widgets.dart';

const _factCategories = ['Body', 'Object', 'Promise', 'Place', 'Fact'];

/// The trimmed fields of a fact the user added or edited.
typedef ContinuityFactInput = ({
  String category,
  String key,
  String value,
  String entity,
});

/// "Add fact" ([f] null) / "Edit fact": the entered fields, or null on
/// Cancel or when "What" is left empty.
Future<ContinuityFactInput?> showContinuityFactDialog(
  BuildContext context,
  ContinuityFact? f,
) async {
  var category = f?.category ?? 'Fact';
  final key = TextEditingController(text: f?.key ?? '');
  final value = TextEditingController(text: f?.value ?? '');
  final entity = TextEditingController(text: f?.entity ?? '');
  final ok = await showStoryDialog<bool>(
    context,
    title: f == null ? 'Add fact' : 'Edit fact',
    width: 460,
    body: StatefulBuilder(
      builder: (ctx, setLocal) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in _factCategories)
                StoryChip(
                  c,
                  selected: c == category,
                  onTap: () => setLocal(() => category = c),
                ),
            ],
          ),
          const SizedBox(height: 10),
          StoryField(controller: key, hint: 'What (e.g. Teodor\'s left hand)'),
          const SizedBox(height: 8),
          StoryField(controller: value, hint: 'Is (e.g. burned, bandaged)'),
          const SizedBox(height: 8),
          StoryField(controller: entity, hint: 'Who or where it belongs to'),
        ],
      ),
    ),
    actions: (ctx) => [
      StoryButton.ghost('Cancel', onPressed: () => Navigator.pop(ctx, false)),
      StoryButton.primary(
        f == null ? 'Add' : 'Save',
        onPressed: () => Navigator.pop(ctx, true),
      ),
    ],
  );
  if (ok != true || key.text.trim().isEmpty) return null;
  return (
    category: category,
    key: key.text.trim(),
    value: value.text.trim(),
    entity: entity.text.trim(),
  );
}

/// "Retire from which scene?": the chosen scene id, or null on Cancel.
Future<String?> showRetireFactScenePicker(
  BuildContext context,
  StoryProject p,
  ContinuityFact f,
) {
  final refs = p.orderedScenes.toList();
  return showStoryDialog<String>(
    context,
    title: 'Retire “${f.key}” from which scene?',
    width: 460,
    body: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final r in refs)
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => Navigator.pop(context, r.scene.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(
                      p.sceneLabel(r.act, r.index),
                      style: StudioType.mono(context),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      r.scene.title,
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
}
