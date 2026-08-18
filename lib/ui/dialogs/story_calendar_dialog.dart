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
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/calendar_today_hold.dart';
import 'package:provider/provider.dart';
import 'journal_card_editor.dart';

/// The Story Calendar (docs/design/story-calendar.md §6): a month grid over
/// the chat's real dates. The current story date glows porch amber, days
/// holding journal memories for the selected diary owner carry a dot, and
/// tapping a marked day lists that day's memories below the grid. The gear
/// affordances re-anchor "story begins on…" or set the current date & time
/// directly (both ride the same swipe-survival patch as a manual nudge).
class StoryCalendarDialog extends StatefulWidget {
  final ChatService chatService;

  const StoryCalendarDialog({super.key, required this.chatService});

  static Future<void> show(
    BuildContext context, {
    required ChatService chatService,
  }) => showDialog(
    context: context,
    builder: (_) => StoryCalendarDialog(chatService: chatService),
  );

  @override
  State<StoryCalendarDialog> createState() => _StoryCalendarDialogState();
}

class _StoryCalendarDialogState extends State<StoryCalendarDialog> {
  ChatService get _chat => widget.chatService;

  late DateTime _visibleMonth; // first of the shown month (UTC)
  String? _ownerId;
  String _ownerName = '';

  /// storyDay → that day's cards for the selected owner.
  Map<int, List<JournalMemoryData>> _cardsByDay = const {};
  int? _selectedDay;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final clock = _chat.timeService.clock;
    _visibleMonth = DateTime.utc(clock.year, clock.month, 1);
    final owners = _chat.cast.where((p) => !p.isLite).toList();
    if (owners.isNotEmpty) {
      _ownerId = owners.first.id;
      _ownerName = owners.first.name;
    }
    _load();
  }

  Future<void> _load() async {
    final sessionId = _chat.currentSessionId;
    final ownerId = _ownerId;
    if (sessionId == null || ownerId == null) {
      setState(() => _loading = false);
      return;
    }
    final cards = await _chat.journalStore.cardsFor(sessionId, ownerId);
    final byDay = <int, List<JournalMemoryData>>{};
    for (final card in cards) {
      final (day, _) = JournalStore.stampOf(card);
      if (day == null) continue;
      byDay.putIfAbsent(day, () => []).add(card);
    }
    if (!mounted) return;
    setState(() {
      _cardsByDay = byDay;
      _loading = false;
    });
  }

  DateTime get _startDate => _chat.timeService.startDate;
  DateTime get _currentDate => StoryClock.dateOnly(_chat.timeService.clock);

  int _dayFor(DateTime date) => StoryClock.dayCountFor(date, _startDate);

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    final time = _chat.timeService;
    final owners = _chat.cast.where((p) => !p.isLite).toList();
    final canEdit = _chat.realismEnabled && !_chat.isGenerating;

    return Dialog(
      backgroundColor: AppColors.cardOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 420,
        constraints: const BoxConstraints(maxHeight: 640),
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('📅', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Story Calendar',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: AppColors.iconSecondary(context),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            Text(
              '${time.displayClock} · ${time.displayDate} '
              '(Day ${time.dayCount})',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary(context),
              ),
            ),
            ListenableBuilder(
              listenable: _chat,
              builder: (context, _) {
                var plannerOn = false;
                try {
                  plannerOn = Provider.of<StorageService>(context)
                      .realismSettings
                      .plannerEnabled;
                } catch (_) {}
                return CalendarTodayHold(
                  enabled: plannerOn,
                  text: _chat.todaySentence,
                  onAbandon: _chat.abandonToday,
                );
              },
            ),
            const SizedBox(height: 10),
            _monthNav(context),
            const SizedBox(height: 6),
            _grid(context, amber),
            if (owners.length > 1) ...[
              const SizedBox(height: 6),
              _ownerPicker(context, owners),
            ],
            Flexible(child: _dayDetail(context)),
            const SizedBox(height: 8),
            _anchorControls(context, canEdit),
          ],
        ),
      ),
    );
  }

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
          onPressed: () => setState(
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
          onPressed: () => setState(
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
    final hasPlan = isCurrent &&
        ((_chat.todaySentence ?? '').trim().isNotEmpty);
    final selected = inStory && _selectedDay == storyDay;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: hasMemories
          ? () => setState(() => _selectedDay = selected ? null : storyDay)
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
              setState(() {
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
    setState(() {
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
    setState(() {
      final c = _chat.timeService.clock;
      _visibleMonth = DateTime.utc(c.year, c.month, 1);
      _selectedDay = null;
    });
  }
}
