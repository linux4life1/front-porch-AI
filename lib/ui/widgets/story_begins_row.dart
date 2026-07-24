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

import 'package:front_porch_ai/services/chat/story_clock.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Story Calendar authoring row (story-calendar.md §3a): "Story begins…" —
/// the day the chat starts (default, what every pre-calendar card meant) or
/// a fixed date at any year for period settings — plus an optional exact
/// opening clock behind the friendly time-of-day picker.
///
/// THE shared widget for every surface that authors a starting time seed:
/// RealismFormSection (manual creator / AI creator Realism step / edit page),
/// the group creation wizard's global scene time, the group dynamics editor,
/// and the group settings dialog.
class StoryBeginsRow extends StatelessWidget {
  /// ISO date ("YYYY-MM-DD"); null = "the day the chat starts".
  final String? storyStartDate;
  final ValueChanged<String?> onStoryStartDateChanged;

  /// "HH:MM" exact opening clock; null = the period's default time.
  final String? storyStartTime;
  final ValueChanged<String?>? onStoryStartTimeChanged;

  const StoryBeginsRow({
    super.key,
    required this.storyStartDate,
    required this.onStoryStartDateChanged,
    this.storyStartTime,
    this.onStoryStartTimeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    final anchor = StoryClock.parse(storyStartDate);
    final hhmm = StoryClock.parseHHMM(storyStartTime);

    Widget chip({
      required IconData icon,
      required String label,
      required bool isSet,
      required VoidCallback onTap,
      required VoidCallback onClear,
    }) => Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerOf(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSet
                  ? amber.withValues(alpha: 0.55)
                  : AppColors.borderOf(context),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 13, color: amber),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isSet
                        ? AppColors.textPrimary(context)
                        : AppColors.textTertiary(context),
                  ),
                ),
              ),
              if (isSet)
                GestureDetector(
                  onTap: onClear,
                  child: Icon(
                    Icons.close,
                    size: 13,
                    color: AppColors.iconSecondary(context),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return Row(
      children: [
        chip(
          icon: Icons.flag_outlined,
          label: anchor == null
              ? 'Story begins: the day the chat starts'
              : 'Story begins ${StoryClock.formatShortDate(anchor)}, '
                    '${anchor.year}',
          isSet: anchor != null,
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: anchor == null
                  ? DateTime(now.year, now.month, now.day)
                  : DateTime(anchor.year, anchor.month, anchor.day),
              firstDate: DateTime(1),
              lastDate: DateTime(9999, 12, 31),
              helpText: 'The story begins on…',
            );
            if (picked == null) return;
            onStoryStartDateChanged(
              StoryClock.serializeDate(
                DateTime.utc(picked.year, picked.month, picked.day),
              ),
            );
          },
          onClear: () => onStoryStartDateChanged(null),
        ),
        if (onStoryStartTimeChanged != null) ...[
          const SizedBox(width: 10),
          chip(
            icon: Icons.schedule,
            label: hhmm == null
                ? 'Opens at: time-of-day default'
                : 'Opens at ${StoryClock.formatClock(DateTime.utc(2000, 1, 1, hhmm.$1, hhmm.$2))}',
            isSet: hhmm != null,
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(
                  hour: hhmm?.$1 ?? 9,
                  minute: hhmm?.$2 ?? 0,
                ),
                helpText: 'The story opens at…',
              );
              if (picked == null) return;
              onStoryStartTimeChanged!(
                '${picked.hour.toString().padLeft(2, '0')}:'
                '${picked.minute.toString().padLeft(2, '0')}',
              );
            },
            onClear: () => onStoryStartTimeChanged!(null),
          ),
        ],
      ],
    );
  }
}
