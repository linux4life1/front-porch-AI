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

import 'package:front_porch_ai/services/chat/body_clock.dart';
import 'package:front_porch_ai/services/chat/story_clock.dart';

/// The chat-scoped clock state the time service owns: the canonical
/// [clock] / [startDate] pair, the per-turn authority flags, the body beat
/// the last commit left to wear, and the session load / seed / swipe
/// restore that writes them. Mutated only by the time service and its
/// collaborators; everything else reads through the service.
class TimeClockState {
  DateTime clock = StoryClock.representativeTime(
    StoryClock.todayAnchor(),
    'morning',
  );
  DateTime startDate = StoryClock.todayAnchor();
  bool passageOfTimeEnabled = true;
  String clockGateSource = 'porch_life';
  bool? clockGateLeftover;
  int turnsSinceClockMoved = 0; // stall backstop counter (not a pacing gate)
  bool canonicalClockWasSynthesised = false;
  // One clock authority per turn: set when detectOocTimeSkip moves the clock,
  // consumed by the per-turn eval so it can't re-count the same exchange.
  bool oocSkipMovedClockThisTurn = false;
  // Named wall-clock is exact. A later 0 / missing minutes_elapsed
  // must not land the 2-minute floor on that pair (follow-up,
  // backfill, reopen).
  bool namedReconcileExact = false;
  DateTime? _capturedClock;
  DateTime? _capturedStartDate;
  String? _capturedSessionId;

  /// Story minutes the body wears for the beat just committed: the minutes
  /// the clock moved, whatever kind of beat it was. Zero for the same moment.
  int bodyWearMinutes = 0;

  /// The minutes still to wear, taken once: a turn that notes no new beat
  /// must not wear the last one again.
  int takeBodyWearMinutes() {
    final minutes = bodyWearMinutes;
    bodyWearMinutes = 0;
    return minutes;
  }

  /// True when the beat was lived off-screen (a skip, next morning, time
  /// away): wear then stops at the skip floors, not the on-screen stop.
  bool bodyBeatOffScreen = false;

  /// Chip text for that beat. Null when the skip chip already says it.
  String? _timePassedLabel;
  String? get bodyTimeLabel => _timePassedLabel;

  /// Words the needs judge scores. Cleared with the chip label so Continue
  /// cannot charge the same span again. A skip has no tick chip, so this
  /// keeps "Next morning" or the destination the clock stamped.
  String? _needsSpanLabel;
  String? get needsSpanLabel => _needsSpanLabel;

  void clearBodyBeat() {
    bodyWearMinutes = 0;
    bodyBeatOffScreen = false;
    _timePassedLabel = null;
    _needsSpanLabel = null;
  }

  /// [minutes] is how far the clock moved; [offScreen] marks a span the
  /// characters lived away from the scene (a skip, a night, time away).
  void noteBodyBeat({
    required int minutes,
    required bool nextMorning,
    required bool isSkip,
    required bool offScreen,
    String? skipDestination,
  }) {
    bodyWearMinutes = minutes < 0 ? 0 : minutes;
    bodyBeatOffScreen = offScreen;
    _timePassedLabel = timePassedLabel(
      minutes: minutes,
      nextMorning: nextMorning,
      isSkip: isSkip,
    );
    _needsSpanLabel = needsSpanForBeat(
      minutes: minutes,
      nextMorning: nextMorning,
      isSkip: isSkip,
      skipDestination: skipDestination,
    );
  }

  // ── Derivations ───────────────────────────────────────────────────────────

  String get timeOfDay => StoryClock.periodForHour(clock.hour);
  int get dayCount => StoryClock.dayCountFor(clock, startDate);
  String get narrativeWeekday => StoryClock.weekdayName(clock);
  String get storyClockIso => StoryClock.serializeClock(clock);
  String get displayClock => StoryClock.formatClock(clock);
  String get displayShortDate => StoryClock.formatShortDate(clock);

  /// Clock-side half of a fresh chat; the service clears its own today line.
  void resetForFreshChat() {
    startDate = StoryClock.todayAnchor();
    clock = StoryClock.representativeTime(startDate, 'morning');
    turnsSinceClockMoved = 0;
    oocSkipMovedClockThisTurn = false;
    namedReconcileExact = false;
    passageOfTimeEnabled = true;
    clearBodyBeat();
    // A brand-new chat has nothing to write back — its clock reaches the row
    // through the ordinary save. Leaving a previous chat's `true` standing here
    // would ask the loader to patch a row this service no longer describes.
    canonicalClockWasSynthesised = false;
    clearCapturedClock();
  }

  // ── Session load / seed / swipe-restore ───────────────────────────────────

  /// Seed from a V2 card / ext-seed payload (design §3a). [storyStartDate]
  /// null means "the story begins the day the chat starts" — what every
  /// pre-calendar card implicitly meant; a fixed date carries its own era.
  /// [storyStartTime] ("HH:MM") lets an author pin the exact opening clock;
  /// otherwise the period's representative time applies.
  void seedFromV2OrExt({
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
      startDate = StoryClock.dateOnly(anchor);
      current = startDate.add(Duration(days: safeDay - 1));
    } else {
      final loaded = StoryClock.dateOnly(startDate);
      final today = StoryClock.todayAnchor();
      final liveDay = StoryClock.dateOnly(clock);
      if (loaded != today) {
        // Existing chat already has a persisted start. Do not
        // re-anchor to today on open, fork, or greeting re-seed.
        current = loaded.add(Duration(days: safeDay - 1));
      } else if (liveDay != today) {
        // Start still reads as today but live already left it —
        // this is an existing chat, not a new-chat seed.
        current = clock;
      } else {
        current = today;
        startDate = current.subtract(Duration(days: safeDay - 1));
      }
    }
    final hhmm = StoryClock.parseHHMM(storyStartTime);
    clock = hhmm != null
        ? DateTime.utc(
            current.year,
            current.month,
            current.day,
            hhmm.$1,
            hhmm.$2,
          )
        : StoryClock.representativeTime(current, timeOfDay);
    turnsSinceClockMoved = 0;
    if (passageOfTimeEnabled != null) {
      this.passageOfTimeEnabled = passageOfTimeEnabled;
      clockGateSource = 'porch_life';
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
    clearCapturedClock();
    namedReconcileExact = false;

    final parsedClock = StoryClock.parse(storyClock);
    final anchor = StoryClock.parse(storyStartDate);
    final safeDay = dayCount < 1 ? 1 : dayCount;
    canonicalClockWasSynthesised = parsedClock == null || anchor == null;

    if (parsedClock != null && anchor != null) {
      clock = parsedClock;
      startDate = StoryClock.dateOnly(anchor);
    } else if (parsedClock != null) {
      clock = parsedClock;
      startDate = StoryClock.dateOnly(
        parsedClock,
      ).subtract(Duration(days: safeDay - 1));
    } else if (anchor != null) {
      startDate = StoryClock.dateOnly(anchor);
      clock = StoryClock.representativeTime(
        startDate.add(Duration(days: safeDay - 1)),
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
      clock = legacy.clock;
      startDate = legacy.startDate;
    }
  }

  void captureLiveClock({String? sessionId}) {
    _capturedClock = clock;
    _capturedStartDate = startDate;
    _capturedSessionId = sessionId;
  }

  void restoreCapturedClock({String? sessionId}) {
    final captured = _capturedClock;
    if (captured == null) return;
    if (sessionId != null &&
        _capturedSessionId != null &&
        _capturedSessionId != sessionId) {
      return;
    }
    clock = captured;
    final start = _capturedStartDate;
    if (start != null) startDate = start;
  }

  void clearCapturedClock() {
    _capturedClock = null;
    _capturedStartDate = null;
    _capturedSessionId = null;
  }

  void rewindToBeforeIso(String? beforeIso) {
    final before = StoryClock.parse(beforeIso);
    if (before == null) return;
    clock = DateTime.utc(
      before.year,
      before.month,
      before.day,
      before.hour,
      before.minute,
    );
  }
}
