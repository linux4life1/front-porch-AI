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

extension _StoryCalendarDetail on _StoryCalendarDialogState {
  Widget _ownerPicker(BuildContext context, List owners) {
    return Row(
      children: [
        Text(
          'Memories: ',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textTertiary(context),
          ),
        ),
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: owners.any((p) => p.id == _ownerId)
                ? _ownerId
                : owners.first.id as String,
            isDense: true,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary(context),
            ),
            dropdownColor: AppColors.surfaceContainerOf(context),
            items: [
              for (final p in owners)
                DropdownMenuItem<String>(value: p.id, child: Text(p.name)),
            ],
            onChanged: (id) {
              if (id == null) return;
              rebuildState(() {
                _ownerId = id;
                _ownerName = owners.firstWhere((p) => p.id == id).name;
                _selectedDay = null;
                _loading = true;
              });
              _load();
            },
          ),
        ),
      ],
    );
  }

  Widget _dayDetail(BuildContext context) {
    if (_loading) {
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
    final day = _selectedDay;
    if (day == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          _cardsByDay.isEmpty
              ? 'No dated memories yet — $_ownerName\'s journal marks the '
                    'calendar as the story unfolds.'
              : 'Tap a marked day to read what $_ownerName remembers from it.',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textTertiary(context),
          ),
        ),
      );
    }
    final cards = _cardsByDay[day] ?? const [];
    final date = _startDate.add(Duration(days: day - 1));
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

  Widget _anchorControls(BuildContext context, bool canEdit) {
    final startLabel = StoryClock.formatShortDate(_startDate);
    return Row(
      children: [
        Expanded(
          child: TextButton.icon(
            onPressed: canEdit ? _pickStartDate : null,
            icon: Icon(
              Icons.flag_outlined,
              size: 14,
              color: AppColors.porchAmberOf(context),
            ),
            label: Text(
              'Story begins $startLabel',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: canEdit
                    ? AppColors.textSecondary(context)
                    : AppColors.textTertiary(context),
              ),
            ),
          ),
        ),
        Expanded(
          child: TextButton.icon(
            onPressed: canEdit ? _pickCurrentDateTime : null,
            icon: Icon(
              Icons.schedule,
              size: 14,
              color: AppColors.porchAmberOf(context),
            ),
            label: Text(
              'Set date & time',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: canEdit
                    ? AppColors.textSecondary(context)
                    : AppColors.textTertiary(context),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(_startDate.year, _startDate.month, _startDate.day),
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
      helpText: 'The story begins on…',
    );
    if (picked == null || !mounted) return;
    await _chat.setStoryStartDate(
      DateTime.utc(picked.year, picked.month, picked.day),
    );
    rebuildState(() {
      final clock = _chat.timeService.clock;
      _visibleMonth = DateTime.utc(clock.year, clock.month, 1);
      _selectedDay = null;
    });
  }

  Future<void> _pickCurrentDateTime() async {
    final clock = _chat.timeService.clock;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime(clock.year, clock.month, clock.day),
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
      helpText: 'Current story date',
    );
    if (pickedDate == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: clock.hour, minute: clock.minute),
      helpText: 'Current story time',
    );
    if (!mounted) return;
    await _chat.setStoryClock(
      DateTime.utc(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime?.hour ?? clock.hour,
        pickedTime?.minute ?? clock.minute,
      ),
    );
    rebuildState(() {
      final c = _chat.timeService.clock;
      _visibleMonth = DateTime.utc(c.year, c.month, 1);
      _selectedDay = null;
    });
  }
}
