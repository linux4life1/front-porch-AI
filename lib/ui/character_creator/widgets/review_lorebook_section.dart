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

import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/creator_text_card.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// Lorebook cherry-pick section of the review step: per-entry checkboxes to
/// include/exclude generated world lore. Faithful restoration of the
/// pre-refactor god-file UI (lines 6972–7103).
class ReviewLorebookSection extends StatelessWidget {
  final CreatorState state;

  const ReviewLorebookSection({super.key, required this.state});

  Color _accent(BuildContext context) => StudioColors.amberOf(context);

  @override
  Widget build(BuildContext context) {
    final lorebook = state.generatedCard?.lorebook;
    if (lorebook == null || lorebook.entries.isEmpty) {
      return const SizedBox.shrink();
    }

    final enabledCount = state.lorebookEntryEnabled.values
        .where((v) => v)
        .length;

    return CreatorCardShell(
      title: 'Lorebook',
      subtitle: '$enabledCount/${lorebook.entries.length} entries kept',
      children: [
        Text(
          'Uncheck entries you don\'t want included in the saved character.',
          style: TextStyle(color: StudioColors.mutedOf(context), fontSize: 12),
        ),
        ...List.generate(lorebook.entries.length, (i) {
          final entry = lorebook.entries[i];
          final enabled = state.lorebookEntryEnabled[i] ?? true;
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: StudioColors.bgOf(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: enabled
                    ? StudioColors.lineOf(context)
                    : StudioColors.lineOf(context).withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: enabled,
                  activeColor: _accent(context),
                  onChanged: (val) {
                    state.lorebookEntryEnabled[i] = val ?? true;
                    state.notify();
                  },
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Opacity(
                    opacity: enabled ? 1.0 : 0.4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.name,
                          style: TextStyle(
                            color: StudioColors.inkOf(context),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Keys: ${entry.key}',
                          style: TextStyle(
                            color: _accent(context),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          entry.content,
                          style: TextStyle(
                            color: StudioColors.proseOf(context),
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
