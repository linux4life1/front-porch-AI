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
    required bool passageOfTimeEnabled,
    String? storyStartDate,
    String? storyStartTime,
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
    _passageOfTimeEnabled = passageOfTimeEnabled;
    _turnsSinceClockMoved = 0;
    todayLine = null;
    _todayLineDayCount = null;
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
    required bool passageOfTimeEnabled,
    String? storyClock,
    String? storyStartDate,
  }) {
    // Load-bearing: this was declared `required` and then never assigned, so a
    // chat's saved setting was read out of the database, handed to us, and
    // dropped. Because TimeService outlives a single chat, the value left over
    // from whatever came before stayed in place — and since entering a chat
    // runs resetForFreshChat() first (which forces true), a saved `false` could
    // never survive a reopen, and the next save wrote `true` back over it. The
    // setting was not merely ignored; it was destroyed.
    _passageOfTimeEnabled = passageOfTimeEnabled;
    clearTodayLine();

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

  // For swipe/regen paths that restore prior realism_state (respect nudge flag).
  void restoreTimeForSwipeOrRegen(
    Map<String, dynamic> previousState, {
    bool wasNudged = false,
  }) {
    if (_passageOfTimeEnabled && !wasNudged) {
      restoreTimeFromRealismState(previousState);
    }
  }

  /// Restore from a realism_state snapshot (message metadata, 1:1<->group
  /// conversion carry). Restores REGARDLESS of passage-of-time — a fixed
  /// scene time is meaningful even with auto-advance off. Prefers the
  /// canonical keys; legacy snapshots synthesize.
  void restoreTimeFromRealismState(Map<String, dynamic> state) {
    final clock = StoryClock.parse(state['storyClock'] as String?);
    final anchor = StoryClock.parse(state['storyStartDate'] as String?);
    if (clock != null) {
      _clock = clock;
      if (anchor != null) _startDate = StoryClock.dateOnly(anchor);
      return;
    }
    final tod = state['timeOfDay'] as String?;
    // .fpchat / JSON may carry 9.0 — accept num (fork walk-back hasClock uses num).
    final dc = (state['dayCount'] as num?)?.toInt();
    if (tod == null && dc == null) return;
    if (anchor != null) _startDate = StoryClock.dateOnly(anchor);
    // A pre-calendar snapshot says only "Day N, period P". Read it against
    // THIS story's Day 1 — the anchor we are already holding — not against the
    // real-world calendar. Today-anchoring it meant swiping one old message
    // dragged the entire timeline onto whatever date the user happened to be
    // swiping on, which is the same wandering date as the load path, except it
    // struck mid-conversation and contradicted every message above it.
    final day = (dc ?? dayCount) < 1 ? 1 : (dc ?? dayCount);
    _clock = StoryClock.representativeTime(
      _startDate.add(Duration(days: day - 1)),
      tod ?? timeOfDay,
    );
  }
}
