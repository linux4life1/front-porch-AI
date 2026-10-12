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
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// The continuity ledger: one row per fact with its category, "from 3.3",
/// and a ⋯ menu to edit, retire or forget it.
class StoryContinuityLedger extends StatelessWidget {
  final StoryProject project;
  final ValueChanged<ContinuityFact> onEdit;
  final ValueChanged<ContinuityFact> onRetire;
  final ValueChanged<ContinuityFact> onForget;

  const StoryContinuityLedger({
    super.key,
    required this.project,
    required this.onEdit,
    required this.onRetire,
    required this.onForget,
  });

  @override
  Widget build(BuildContext context) {
    final p = project;
    if (p.continuity.isEmpty) {
      return StoryEmptyState(
        title: 'No facts yet',
        detail: p.engineMode == StoryEngineMode.studio
            ? 'Studio records hard facts after every scene: scars, objects, '
                  'promises, places. Add one yourself with Add fact.'
            : 'The Quick engine does not keep a ledger. Switch the story to '
                  'Studio under Setup, or add facts yourself.',
      );
    }
    final live = p.continuity.where((f) => !f.isRetired).toList();
    final retired = p.continuity.where((f) => f.isRetired).toList();
    return StoryCard(
      children: [
        for (final f in live) _factRow(context, f),
        for (final f in retired) _factRow(context, f),
      ],
    );
  }

  Widget _factRow(BuildContext context, ContinuityFact f) {
    final p = project;
    final muted = StudioColors.mutedOf(context);
    final from = f.sceneId.isEmpty ? '' : p.sceneLabelById(f.sceneId);
    final until = f.isRetired ? p.sceneLabelById(f.retiredSceneId) : '';
    return Row(
      children: [
        StoryChip(
          f.isRetired ? 'Retired' : f.category,
          tone: f.isRetired ? '' : 'honey',
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: f.key,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: ' · ${f.value}'),
                if (f.entity.isNotEmpty)
                  TextSpan(
                    text: '  (${f.entity})',
                    style: TextStyle(color: muted),
                  ),
              ],
            ),
            style:
                StudioType.ui(
                  context,
                  size: 12.5,
                  color: f.isRetired ? muted : StudioColors.inkOf(context),
                ).copyWith(
                  decoration: f.isRetired ? TextDecoration.lineThrough : null,
                ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          f.isRetired
              ? '$from → $until'
              : (from.isEmpty ? 'always' : 'from $from'),
          style: StudioType.mono(context, size: 11.5),
        ),
        StoryMenuButton(
          key: ValueKey('fact-menu-${f.key}'),
          entries: [
            StoryMenuEntry('Edit…', onSelect: () => onEdit(f)),
            if (!f.isRetired)
              StoryMenuEntry('Retire from scene…', onSelect: () => onRetire(f)),
            StoryMenuEntry(
              'Forget…',
              danger: true,
              divider: true,
              onSelect: () => onForget(f),
            ),
          ],
        ),
      ],
    );
  }
}
