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

/// Deterministic corroboration gate for the eval's `new_day` flag. The flag
/// bypasses [StoryClock.maxMinutesPerTurn] entirely (it's the only way the
/// clock can cross a night in one turn), and small eval models hallucinate
/// it — a scene full of "the beach where we met yesterday" talk produced
/// new_day=true at 6:30 PM and slammed the story to next morning. Honor the
/// flag only when the exchange actually contains sleep/wake/next-day
/// language; without it the turn still gets its clamped minutes_elapsed.
final RegExp _newDayCorroboration = RegExp(
  r'\b(sleep|slept|asleep|falls? asleep|wake|woke|waking|good.?night|'
  r'next (morning|day)|the following (morning|day)|overnight|'
  r'in the morning|calls? it a night|turn(s|ed|ing)? in for the night|'
  r'sunrise|daybreak|dawn broke)\b',
  caseSensitive: false,
);

/// Clamp, failure floor, new_day, OOC skip, and calendar writes.
extension TimeServiceApply on TimeService {
  // ── Manual control (chevrons + calendar dialog) ───────────────────────────

  /// Sidebar / web chevrons: ±[StoryClock.nudgeStepMinutes]. delta = +1
  /// (forward) or -1 (back). Signals god to patch the last msg
  /// realism_state so swipe/regen cannot revert it. Period snaps still
  /// exist for AFK ([advanceTimePeriods]); the strip needed minute fidelity
  /// once At work / Today read the live clock.
  Future<void> nudgeTimePeriod(int delta) async {
    final dayBefore = dayCount;
    final step = StoryClock.nudgeStepMinutes * (delta >= 0 ? 1 : -1);
    _clock = StoryClock.addMinutes(_clock, step);
    if (_clock.isBefore(_startDate)) _startDate = StoryClock.dateOnly(_clock);
    _turnsSinceClockMoved = 0;
    onPatchLastMessageRealismState(timeOfDay, dayCount, storyClockIso);
    await _ifDayChanged(dayBefore);
  }

  /// All-away skip banner: no reply to score, so no LLM. Same 5-minute
  /// floor the eval uses on failure. An OOC skip that already owned this
  /// turn is left alone (and consumes the flag, matching the eval).
  Future<void> applyFailureDrift() async {
    if (!_passageOfTimeEnabled) return;
    if (_oocSkipMovedClockThisTurn) {
      _oocSkipMovedClockThisTurn = false;
      return;
    }
    await _applyElapsed(minutes: null, newDay: false);
    onNotify();
  }

  /// Calendar dialog: set the story's current moment directly. Pulls the
  /// anchor back when the new moment predates Day 1 (the story now starts
  /// earlier). Same swipe-survival patch as a nudge.
  Future<void> _setClockDirect(DateTime newClock) async {
    final dayBefore = dayCount;
    _clock = DateTime.utc(
      newClock.year,
      newClock.month,
      newClock.day,
      newClock.hour,
      newClock.minute,
    );
    if (_clock.isBefore(_startDate)) _startDate = StoryClock.dateOnly(_clock);
    _turnsSinceClockMoved = 0;
    onPatchLastMessageRealismState(timeOfDay, dayCount, storyClockIso);
    await _ifDayChanged(dayBefore);
  }

  /// Post-reply: they named a time, so the live clock follows. Not a user
  /// nudge — swipe/regen still rewind from the previous snapshot.
  Future<void> applyReconciledClock(DateTime newClock) async {
    final dayBefore = dayCount;
    _clock = DateTime.utc(
      newClock.year,
      newClock.month,
      newClock.day,
      newClock.hour,
      newClock.minute,
    );
    if (_clock.isBefore(_startDate)) _startDate = StoryClock.dateOnly(_clock);
    _turnsSinceClockMoved = 0;
    await _ifDayChanged(dayBefore);
  }

  /// Calendar dialog: re-anchor "story begins on…". Shifts the clock by the
  /// same delta so elapsed days (and Day N) are preserved — the whole
  /// timeline slides together (design §3).
  void setStartDate(DateTime newStart) {
    final anchored = StoryClock.dateOnly(newStart);
    _clock = _clock.add(anchored.difference(_startDate));
    _startDate = anchored;
    _turnsSinceClockMoved = 0;
    onPatchLastMessageRealismState(timeOfDay, dayCount, storyClockIso);
  }

  /// Advance the clock by [count] period-steps (skip LLM eval).
  /// Used during AFK auto-response mode to simulate hours passing.
  /// Respects the passageOfTimeEnabled toggle.
  ///
  /// Owns the turn the same way an OOC skip does: the post-reply time
  /// eval must not add minutes on top of the AFK snap.
  void advanceTimePeriods(int count) {
    if (!_passageOfTimeEnabled) return;
    for (var i = 0; i < count; i++) {
      _clock = StoryClock.snapToNextPeriod(_clock);
    }
    if (count > 0) {
      _turnsSinceClockMoved = 0;
      _oocSkipMovedClockThisTurn = true;
    }
  }

  // ── OOC Time-Skip Detector ────────────────────────────────────────────────

  /// Scans the user message for OOC/narrative time-skip language and advances
  /// the clock by the inferred real duration. Fires on explicit OOC markers
  /// AND bare in-narrative skip phrasing ("we drive for several hours").
  /// Stamps the destination into pending metadata for the next delta chip.
  /// Respects the global passageOfTimeEnabled setting.
  ///
  /// ── WHY QUOTED SPEECH IS STRIPPED FIRST (2026-08-08) ─────────────────────
  ///
  /// A skip is something the NARRATION does. A time phrase inside quotes is
  /// something a character SAID, and saying a date is not travelling to it —
  /// the scene-time prompt already states the rule this detector was missing:
  /// "merely MENTIONING yesterday, tomorrow, or another day does NOT count".
  ///
  /// This was not theoretical. In one of the maintainer's own chats the line
  /// *"Mistress? will you give your donors a new video next week?"* matched
  /// `next week` and jumped the story from Day 1 to Day 8 — exactly seven days,
  /// same wall time — and a few turns later *"why wait till next week for the
  /// Gym video"* did it again, that time permanently. A third chat lost a full
  /// day to *"even though we just woke up a few hours ago"*, which matched
  /// `woke up` and fired [StoryClock.nextMorning]. In every case the skip then
  /// claimed the turn (`_oocSkipMovedClockThisTurn`), so the eval's own — and
  /// correct — verdict of a few minutes was discarded in its favour. That is
  /// the "day 28 / time 16" contradiction: the notes still describe the same
  /// afternoon the scene never left.
  ///
  /// The narrated cases are untouched, because narration is not in quotes. Over
  /// the 1,050 trigger phrases in that library, 1,043 sit outside quotes and
  /// still fire; the 7 inside were false, every one.
  ///
  /// Deliberately NOT applied to [_newDayCorroboration]: "goodnight" and "I'm
  /// going to sleep" are SPOKEN, so stripping quotes there would delete the
  /// evidence that a night was really crossed and quietly stop day rolls
  /// altogether. Opposite question, opposite answer.
  Future<void> detectOocTimeSkip(String text) async {
    if (!_passageOfTimeEnabled) {
      debugPrint(
        '[Realism:OOC] Time-skip requested but passageOfTimeEnabled=false, ignoring',
      );
      return;
    }

    final lower = stripQuotedSpeech(text).toLowerCase();
    if (!shouldDetectTimeSkip(lower)) return;

    final next = StoryClock.resolveSkipTarget(_clock, lower);

    final dayBefore = dayCount;
    _clock = next;
    _turnsSinceClockMoved = 0;
    _oocSkipMovedClockThisTurn = true;
    onSetPendingRealismMetadata(
      'time_skip_to',
      '$displayShortDate · $displayClock',
    );
    onNotify();
    debugPrint(
      '[Realism:OOC] Time-skip → $displayClock $displayShortDate (Day $dayCount)',
    );
    await _ifDayChanged(dayBefore);
  }

  // ── Per-turn time advance (delegated from the physical / one-shot evals) ──

  /// Apply one turn's elapsed time. [minutes] null means the eval failed —
  /// deterministic drift applies. Returns whether the clock moved.
  Future<bool> _applyElapsed({
    required int? minutes,
    required bool newDay,
  }) async {
    final dayBefore = dayCount;
    var moved = false;
    final m = (minutes ?? StoryClock.failureDriftMinutes).clamp(
      0,
      StoryClock.maxMinutesPerTurn,
    );
    if (m > 0) {
      _clock = _clock.add(Duration(minutes: m));
      moved = true;
    }
    // Corroborated next-day transition. The hour gate (17:00–05:00) was
    // dropped: a nap that becomes "we slept through to morning" at 2pm is
    // still a night crossed. Hallucinations are the corroboration regex's
    // job, not the wall clock's.
    if (newDay) {
      _clock = StoryClock.nextMorning(_clock);
      moved = true;
    }
    if (moved) {
      _turnsSinceClockMoved = 0;
    } else if (++_turnsSinceClockMoved >= StoryClock.stallBackstopTurns) {
      _clock = StoryClock.snapToNextPeriod(_clock);
      _turnsSinceClockMoved = 0;
      moved = true;
      debugPrint('[Realism:Time] Stall backstop — snapped to $timeOfDay');
    }
    await _ifDayChanged(dayBefore);
    return moved;
  }
}
