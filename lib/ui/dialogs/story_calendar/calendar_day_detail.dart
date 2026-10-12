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
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import '../journal_card_editor.dart';

/// Below the grid: a spinner while loading, a hint when no day is selected,
/// or the selected story day's journal memories.
class CalendarDayDetail extends StatelessWidget {
  final bool loading;
  final int? selectedDay;

  /// storyDay → that day's cards for the selected owner.
  final Map<int, List<JournalMemoryData>> cardsByDay;
  final String ownerName;
  final DateTime startDate;

  const CalendarDayDetail({
    super.key,
    required this.loading,
    required this.selectedDay,
    required this.cardsByDay,
    required this.ownerName,
    required this.startDate,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.porchAmberOf(context),
            ),
          ),
        ),
      );
    }
    final day = selectedDay;
    if (day == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          cardsByDay.isEmpty
              ? 'No dated memories yet — $ownerName\'s journal marks the '
                    'calendar as the story unfolds.'
              : 'Tap a marked day to read what $ownerName remembers from it.',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textTertiary(context),
          ),
        ),
      );
    }
    final cards = cardsByDay[day] ?? const [];
    final date = startDate.add(Duration(days: day - 1));
    return ListView(
      shrinkWrap: true,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            'DAY $day — ${StoryClock.formatDate(date, realYear: StoryClock.todayAnchor().year).toUpperCase()}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: AppColors.journalAccentOf(context),
            ),
          ),
        ),
        for (final card in cards)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerOf(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.borderOf(context).withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    journalCardEmoji(card),
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          card.content,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: AppColors.textPrimary(context),
                          ),
                        ),
                        if (journalFeelingLine(card) != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              journalFeelingLine(card)!,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontStyle: FontStyle.italic,
                                color: AppColors.textTertiary(context),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
