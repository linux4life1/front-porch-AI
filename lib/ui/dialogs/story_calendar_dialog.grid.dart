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

part of 'story_calendar_dialog.dart';

extension _StoryCalendarGrid on _StoryCalendarDialogState {
  Widget _monthNav(BuildContext context) {
    return Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(
            Icons.chevron_left,
            size: 18,
            color: AppColors.iconSecondary(context),
          ),
          onPressed: () => rebuildState(
            () => _visibleMonth = DateTime.utc(
              _visibleMonth.year,
              _visibleMonth.month - 1,
              1,
            ),
          ),
        ),
        Expanded(
          child: Text(
            '${StoryClock.monthName(_visibleMonth)} ${_visibleMonth.year}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary(context),
            ),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(
            Icons.chevron_right,
            size: 18,
            color: AppColors.iconSecondary(context),
          ),
          onPressed: () => rebuildState(
            () => _visibleMonth = DateTime.utc(
              _visibleMonth.year,
              _visibleMonth.month + 1,
              1,
            ),
          ),
        ),
      ],
    );
  }

  Widget _grid(BuildContext context, Color amber) {
    final firstWeekday = _visibleMonth.weekday; // 1=Mon
    final daysInMonth = DateTime.utc(
      _visibleMonth.year,
      _visibleMonth.month + 1,
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
          DateTime.utc(_visibleMonth.year, _visibleMonth.month, d),
          amber,
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

  Widget _dayCell(BuildContext context, DateTime date, Color amber) {
    final isCurrent = date == _currentDate;
    final inStory = !date.isBefore(_startDate) && !date.isAfter(_currentDate);
    final storyDay = _dayFor(date);
    final hasMemories = inStory && _cardsByDay.containsKey(storyDay);
    final hasPlan =
        isCurrent && ((_chat.todaySentence ?? '').trim().isNotEmpty);
    final selected = inStory && _selectedDay == storyDay;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: hasMemories
          ? () => rebuildState(() => _selectedDay = selected ? null : storyDay)
          : null,
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
                    ? AppColors.onChaosAccent
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
                        color: isCurrent ? AppColors.onChaosAccent : amber,
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
