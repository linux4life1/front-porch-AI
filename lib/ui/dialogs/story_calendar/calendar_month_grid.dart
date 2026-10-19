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
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The month grid: the current story date glows [amber], in-story days with
/// memories (and today, when it holds a plan) carry a dot, and tapping a
/// marked day toggles its selection.
class CalendarMonthGrid extends StatelessWidget {
  /// First of the shown month (UTC).
  final DateTime visibleMonth;
  final Color amber;
  final DateTime startDate;
  final DateTime currentDate;

  /// Story days holding memories for the selected diary owner.
  final Set<int> memoryDays;
  final String? todaySentence;
  final int? selectedDay;
  final ValueChanged<int?> onSelectDay;

  const CalendarMonthGrid({
    super.key,
    required this.visibleMonth,
    required this.amber,
    required this.startDate,
    required this.currentDate,
    required this.memoryDays,
    required this.todaySentence,
    required this.selectedDay,
    required this.onSelectDay,
  });

  @override
  Widget build(BuildContext context) {
    final firstWeekday = visibleMonth.weekday; // 1=Mon
    final daysInMonth = DateTime.utc(
      visibleMonth.year,
      visibleMonth.month + 1,
      0,
    ).day;

    final cells = <Widget>[
      for (final label in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
        Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: AppColors.textTertiary(context),
            ),
          ),
        ),
      for (var i = 1; i < firstWeekday; i++) const SizedBox.shrink(),
      for (var d = 1; d <= daysInMonth; d++)
        _dayCell(
          context,
          DateTime.utc(visibleMonth.year, visibleMonth.month, d),
        ),
    ];

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 2,
      crossAxisSpacing: 2,
      childAspectRatio: 1.25,
      children: cells,
    );
  }

  Widget _dayCell(BuildContext context, DateTime date) {
    final isCurrent = date == currentDate;
    final inStory = !date.isBefore(startDate) && !date.isAfter(currentDate);
    final storyDay = StoryClock.dayCountFor(date, startDate);
    final hasMemories = inStory && memoryDays.contains(storyDay);
    final hasPlan = isCurrent && ((todaySentence ?? '').trim().isNotEmpty);
    final selected = inStory && selectedDay == storyDay;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: hasMemories ? () => onSelectDay(selected ? null : storyDay) : null,
      child: Container(
        decoration: BoxDecoration(
          color: isCurrent
              ? amber
              : selected
              ? amber.withValues(alpha: 0.18)
              : null,
          borderRadius: BorderRadius.circular(8),
          border: selected && !isCurrent
              ? Border.all(color: amber.withValues(alpha: 0.6))
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                color: isCurrent
                    ? AppColors.onAccentOf(context)
                    : inStory
                    ? AppColors.textPrimary(context)
                    : AppColors.textTertiary(context).withValues(alpha: 0.45),
              ),
            ),
            SizedBox(
              height: 5,
              child: (hasMemories || hasPlan)
                  ? Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isCurrent
                            ? AppColors.onAccentOf(context)
                            : amber,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
