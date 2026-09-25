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

part of 'time_service.dart';

/// Session load / seed / swipe-restore for [TimeService].
extension TimeServiceLoad on TimeService {
  /// Seed from a V2 card / ext-seed payload (design §3a). [storyStartDate]
  /// null means "the story begins the day the chat starts" — what every
  /// pre-calendar card implicitly meant; a fixed date carries its own era.
  /// [storyStartTime] ("HH:MM") lets an author pin the exact opening clock;
  /// otherwise the period's representative time applies.
  void _seedFromV2OrExt({
    required int dayCount,
    required String timeOfDay,
    String? storyStartDate,
    String? storyStartTime,
    bool? passageOfTimeEnabled,
  }) {
    final anchor = StoryClock.parse(storyStartDate);
    final safeDay = dayCount.clamp(1, 9999);
    // Fixed date: the story's Day N counts forward from ITS anchor. Relative
    // (null): "Day N" means the chat opens N days into the story with the
    // current scene TODAY — the pre-calendar meaning, preserved.
    final DateTime current;
    if (anchor != null) {
      _startDate = StoryClock.dateOnly(anchor);
      current = _startDate.add(Duration(days: safeDay - 1));
    } else {
      current = StoryClock.todayAnchor();
      _startDate = current.subtract(Duration(days: safeDay - 1));
    }
    final hhmm = StoryClock.parseHHMM(storyStartTime);
    _clock = hhmm != null
        ? DateTime.utc(
            current.year,
            current.month,
            current.day,
            hhmm.$1,
            hhmm.$2,
          )
        : StoryClock.representativeTime(current, timeOfDay);
    _turnsSinceClockMoved = 0;
    todayLine = null;
    _todayLineDayCount = null;
    if (passageOfTimeEnabled != null) {
      _passageOfTimeEnabled = passageOfTimeEnabled;
      _clockGateSource = 'porch_life';
    }
  }

  /// Load from a session row. Canonical columns win; legacy rows synthesize
  /// so the displayed weekday never jumps across the upgrade — and report that
  /// they did via [canonicalClockWasSynthesised], because a synthesis that is
  /// never written back is a synthesis that runs again tomorrow against a
  /// different "today".
  ///
  /// Only the both-columns-missing case reads the wall clock at all. The two
  /// half-populated cases derive the missing half from the half we HAVE, which
  /// is deterministic: a stored moment fixes Day 1 at [dayCount] days behind
  /// it, and a stored Day 1 fixes the moment at Day [dayCount] forward of it.
  /// The old code sent both of those through the today-anchored legacy path,
  /// which could hand a fixed-date story (Day 1 = 1887-06-01) a "current"
  /// moment in 2026 and call it Day 50,000.
  void loadTimeScalars({
    required String timeOfDay,
    required int dayCount,
    required int startDayOfWeek,
    String? storyClock,
    String? storyStartDate,
  }) {
    clearTodayLine();
    _clearCapturedClock();

    final clock = StoryClock.parse(storyClock);
    final anchor = StoryClock.parse(storyStartDate);
    final safeDay = dayCount < 1 ? 1 : dayCount;
    _canonicalClockWasSynthesised = clock == null || anchor == null;

    if (clock != null && anchor != null) {
      _clock = clock;
      _startDate = StoryClock.dateOnly(anchor);
    } else if (clock != null) {
      _clock = clock;
      _startDate = StoryClock.dateOnly(
        clock,
      ).subtract(Duration(days: safeDay - 1));
    } else if (anchor != null) {
      _startDate = StoryClock.dateOnly(anchor);
      _clock = StoryClock.representativeTime(
        _startDate.add(Duration(days: safeDay - 1)),
        timeOfDay,
      );
    } else {
      // Genuinely pre-calendar: period + day number and nothing else. Today is
      // the only anchor there is, and this branch keeps showing exactly what
      // these chats show now — the caller freezes it so it stops moving.
      final legacy = StoryClock.fromLegacy(
        timeOfDay: timeOfDay,
        dayCount: dayCount,
        startDayOfWeek: startDayOfWeek,
        today: StoryClock.todayAnchor(),
      );
      _clock = legacy.clock;
      _startDate = legacy.startDate;
    }
  }

  void _captureLiveClock({String? sessionId}) {
    _capturedClock = _clock;
    _capturedStartDate = _startDate;
    _capturedSessionId = sessionId;
  }

  void _restoreCapturedClock({String? sessionId}) {
    final captured = _capturedClock;
    if (captured == null) return;
    if (sessionId != null &&
        _capturedSessionId != null &&
        _capturedSessionId != sessionId) {
      return;
    }
    _clock = captured;
    final start = _capturedStartDate;
    if (start != null) _startDate = start;
  }

  void _clearCapturedClock() {
    _capturedClock = null;
    _capturedStartDate = null;
    _capturedSessionId = null;
  }

  void _rewindToBeforeIso(String? beforeIso) {
    final before = StoryClock.parse(beforeIso);
    if (before == null) return;
    _clock = DateTime.utc(
      before.year,
      before.month,
      before.day,
      before.hour,
      before.minute,
    );
  }
}
