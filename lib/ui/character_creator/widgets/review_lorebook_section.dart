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
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Lorebook cherry-pick section of the review step: per-entry checkboxes to
/// include/exclude generated world lore. Faithful restoration of the
/// pre-refactor god-file UI (lines 6972–7103).
class ReviewLorebookSection extends StatelessWidget {
  final CreatorState state;

  const ReviewLorebookSection({super.key, required this.state});

  Color _accent(BuildContext context) => AppColors.porchAmberOf(context);

  @override
  Widget build(BuildContext context) {
    final lorebook = state.generatedCard?.lorebook;
    if (lorebook == null || lorebook.entries.isEmpty) {
      return const SizedBox.shrink();
    }

    final enabledCount = state.lorebookEntryEnabled.values
        .where((v) => v)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: AppColors.borderOf(context), height: 32),
        Row(
          children: [
            Icon(Icons.menu_book, color: _accent(context), size: 18),
            const SizedBox(width: 8),
            Text(
              'World Lore Entries',
              style: TextStyle(
                color: _accent(context),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              '$enabledCount/${lorebook.entries.length} enabled',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Uncheck entries you don\'t want included in the saved character.',
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(lorebook.entries.length, (i) {
          final entry = lorebook.entries[i];
          final enabled = state.lorebookEntryEnabled[i] ?? true;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: enabled
                  ? AppColors.surfaceContainerOf(context)
                  : AppColors.backgroundOf(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: enabled
                    ? _accent(context).withValues(alpha: 0.3)
                    : AppColors.borderOf(context).withValues(alpha: 0.2),
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
                            color: AppColors.textPrimary(context),
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
                            color: AppColors.textSecondary(context),
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
