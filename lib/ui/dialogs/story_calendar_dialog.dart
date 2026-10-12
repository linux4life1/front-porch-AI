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
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/calendar_today_hold.dart';
import 'package:provider/provider.dart';

import 'story_calendar/story_calendar.dart';

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

  void _shiftMonth(int delta) => setState(
    () => _visibleMonth = DateTime.utc(
      _visibleMonth.year,
      _visibleMonth.month + delta,
      1,
    ),
  );

  void _selectOwner(List<ChatParticipant> owners, String id) {
    setState(() {
      _ownerId = id;
      _ownerName = owners.firstWhere((p) => p.id == id).name;
      _selectedDay = null;
      _loading = true;
    });
    _load();
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

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    final time = _chat.timeService;
    final owners = _chat.cast.where((p) => !p.isLite).toList();
    final canEdit =
        StoryClock.isRunning(passageOfTimeEnabled: time.passageOfTimeEnabled) &&
        !_chat.isGenerating;

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
                  plannerOn = Provider.of<StorageService>(
                    context,
                  ).realismSettings.plannerEnabled;
                } catch (_) {}
                return CalendarTodayHold(
                  enabled: plannerOn,
                  text: _chat.todaySentence,
                  onAbandon: _chat.abandonToday,
                );
              },
            ),
            const SizedBox(height: 10),
            CalendarMonthNav(
              visibleMonth: _visibleMonth,
              onPrevious: () => _shiftMonth(-1),
              onNext: () => _shiftMonth(1),
            ),
            const SizedBox(height: 6),
            CalendarMonthGrid(
              visibleMonth: _visibleMonth,
              amber: amber,
              startDate: _startDate,
              currentDate: _currentDate,
              memoryDays: _cardsByDay.keys.toSet(),
              todaySentence: _chat.todaySentence,
              selectedDay: _selectedDay,
              onSelectDay: (day) => setState(() => _selectedDay = day),
            ),
            if (owners.length > 1) ...[
              const SizedBox(height: 6),
              CalendarOwnerPicker(
                owners: owners,
                ownerId: _ownerId,
                onChanged: (id) => _selectOwner(owners, id),
              ),
            ],
            Flexible(
              child: CalendarDayDetail(
                loading: _loading,
                selectedDay: _selectedDay,
                cardsByDay: _cardsByDay,
                ownerName: _ownerName,
                startDate: _startDate,
              ),
            ),
            const SizedBox(height: 8),
            CalendarAnchorControls(
              startDate: _startDate,
              canEdit: canEdit,
              onPickStartDate: _pickStartDate,
              onPickCurrentDateTime: _pickCurrentDateTime,
            ),
          ],
        ),
      ),
    );
  }
}
