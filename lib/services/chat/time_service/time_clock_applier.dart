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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/chat/body_clock.dart';
import 'package:front_porch_ai/services/chat/skip_language.dart';
import 'package:front_porch_ai/services/chat/story_clock.dart';
import 'package:front_porch_ai/services/chat/time_service/time_clock_state.dart';
import 'package:front_porch_ai/utils/utils.dart' show stripQuotedSpeech;

/// Deterministic corroboration gate for the eval's `new_day` flag. The flag
/// bypasses [StoryClock.maxMinutesPerTurn] entirely (it's the only way the
/// clock can cross a night in one turn), and small eval models hallucinate
/// it — a scene full of "the beach where we met yesterday" talk produced
/// new_day=true at 6:30 PM and slammed the story to next morning. Honor the
/// flag only when the exchange actually contains sleep/wake/next-day
/// language; without it the turn still gets its clamped minutes_elapsed.
final RegExp newDayCorroboration = RegExp(
  r'\b(sleep|slept|asleep|falls? asleep|wake|woke|waking|good.?night|'
  r'next (morning|day)|the following (morning|day)|overnight|'
  r'in the morning|calls? it a night|turn(s|ed|ing)? in for the night|'
  r'sunrise|daybreak|dawn broke)\b',
  caseSensitive: false,
);

/// Clamp, failure floor, new_day, OOC skip, and calendar writes.
class TimeClockApplier {
  TimeClockApplier({
    required this.state,
    required this.isPassageOfTimeEnabled,
    required this.onNotify,
    required this.onSetPendingRealismMetadata,
    required this.onPatchLastMessageRealismState,
    required this.onDayChanged,
  });

  final TimeClockState state;

  /// Live Passage of Time gate (Porch Life, else the per-chat copy).
  final bool Function() isPassageOfTimeEnabled;
  final void Function() onNotify;
  final void Function(String key, dynamic value) onSetPendingRealismMetadata;
  final void Function(String timeOfDay, int dayCount, String storyClockIso)
  onPatchLastMessageRealismState;

  /// Clears the today line and fires the day-roll hook when the story day
  /// moved off [dayBefore].
  final Future<void> Function(int dayBefore) onDayChanged;

  // ── Manual control (chevrons + calendar dialog) ───────────────────────────

  /// Sidebar / web chevrons: ±[StoryClock.nudgeStepMinutes]. delta = +1
  /// (forward) or -1 (back). Signals god to patch the last msg
  /// realism_state so swipe/regen cannot revert it. Period snaps still
  /// exist for AFK ([advanceTimePeriods]); the strip needed minute fidelity
  /// once At work / Today read the live clock.
  Future<void> nudgeTimePeriod(int delta) async {
    final dayBefore = state.dayCount;
    final step = StoryClock.nudgeStepMinutes * (delta >= 0 ? 1 : -1);
    state.clock = StoryClock.addMinutes(state.clock, step);
    if (state.clock.isBefore(state.startDate)) {
      state.startDate = StoryClock.dateOnly(state.clock);
    }
    state.turnsSinceClockMoved = 0;
    onPatchLastMessageRealismState(
      state.timeOfDay,
      state.dayCount,
      state.storyClockIso,
    );
    await onDayChanged(dayBefore);
  }

  /// All-away skip banner: no reply to score, so no LLM. AFK uses the
  /// 5-minute step; a user send that lands here uses the 2-minute floor.
  /// An OOC skip that already owned this turn is left alone.
  Future<void> applyFailureDrift({int? minutes}) async {
    if (!isPassageOfTimeEnabled()) return;
    if (state.oocSkipMovedClockThisTurn) {
      state.oocSkipMovedClockThisTurn = false;
      return;
    }
    await applyElapsed(
      minutes: minutes ?? StoryClock.failureDriftMinutes,
      newDay: false,
    );
    onNotify();
  }

  /// Calendar dialog: set the story's current moment directly. Pulls the
  /// anchor back when the new moment predates Day 1 (the story now starts
  /// earlier). Same swipe-survival patch as a nudge.
  Future<void> setClockDirect(DateTime newClock) async {
    final dayBefore = state.dayCount;
    _setClockPullingStartDate(newClock);
    state.turnsSinceClockMoved = 0;
    onPatchLastMessageRealismState(
      state.timeOfDay,
      state.dayCount,
      state.storyClockIso,
    );
    await onDayChanged(dayBefore);
  }

  /// Regen of a skip/AFK reply: the rejected slot already moved
  /// the clock. Replay must not tick again.
  void reclaimSkipOwnership() {
    state.oocSkipMovedClockThisTurn = true;
  }

  /// Post-reply: they named a time, so the live clock follows.
  /// A counted chip (`5 min`, `1 hr`) is re-noted by the reconcile
  /// delta. Next morning and skip labels stay as they are.
  Future<void> applyReconciledClock(DateTime newClock) async {
    final dayBefore = state.dayCount;
    final oldClock = state.clock;
    final labelMins = minutesFromTimePassed(state.bodyTimeLabel);
    _setClockPullingStartDate(newClock);
    state.turnsSinceClockMoved = 0;
    state.namedReconcileExact = true;
    final delta = state.clock.difference(oldClock).inMinutes;
    // Whatever the beat still owes: its whole span when this runs before
    // the wear (the post-reply clock advance), nothing when the wear already
    // took it (the post-gen restamp). The correction adds its own delta to
    // that, never replaces it, so a skip's night is still worn after a
    // reply that names the morning hour.
    final owed = state.bodyWearMinutes;
    final offScreen = state.bodyBeatOffScreen;
    if (labelMins != null) {
      final adjusted = labelMins + delta;
      state.noteBodyBeat(
        minutes: adjusted < 0 ? 0 : adjusted,
        nextMorning: false,
        isSkip: false,
        offScreen: false,
      );
    }
    final stillOwed = owed + delta;
    state.bodyWearMinutes = stillOwed < 0 ? 0 : stillOwed;
    state.bodyBeatOffScreen = offScreen;
    await onDayChanged(dayBefore);
  }

  /// Live clock, plus the Day-1 pull-back already used by the calendar
  /// set and a named-clock reconcile. Rewind/swipe/import reuse this
  /// instead of inventing a floor helper.
  void _setClockPullingStartDate(DateTime newClock) {
    state.clock = DateTime.utc(
      newClock.year,
      newClock.month,
      newClock.day,
      newClock.hour,
      newClock.minute,
    );
    if (state.clock.isBefore(state.startDate)) {
      state.startDate = StoryClock.dateOnly(state.clock);
    }
  }

  /// Calendar dialog: re-anchor "story begins on…". Shifts the clock by the
  /// same delta so elapsed days (and Day N) are preserved — the whole
  /// timeline slides together (design §3).
  void setStartDate(DateTime newStart) {
    final anchored = StoryClock.dateOnly(newStart);
    state.clock = state.clock.add(anchored.difference(state.startDate));
    state.startDate = anchored;
    state.turnsSinceClockMoved = 0;
  }

  /// Advance the clock by [count] period-steps (skip LLM eval).
  /// Used during AFK auto-response mode to simulate hours passing.
  /// Respects the passageOfTimeEnabled toggle.
  ///
  /// Owns the turn the same way an OOC skip does: the post-reply time
  /// eval must not add minutes on top of the AFK snap.
  void advanceTimePeriods(int count) {
    if (!isPassageOfTimeEnabled()) return;
    final before = state.clock;
    for (var i = 0; i < count; i++) {
      state.clock = StoryClock.snapToNextPeriod(state.clock);
    }
    if (count > 0) {
      state.turnsSinceClockMoved = 0;
      state.oocSkipMovedClockThisTurn = true;
      final jumped = state.clock.difference(before).inMinutes;
      state.noteBodyBeat(
        minutes: jumped < 0 ? 0 : jumped,
        nextMorning: false,
        isSkip: false,
        offScreen: true,
      );
      // Same skip ownership as detectOocTimeSkip: the post-reply eval
      // must not add minutes, and the tick takes the time_skip_to
      // branch so the chip names this snap instead of a 0-span
      // "same moment" (before is stamped after the clock already moved).
      onSetPendingRealismMetadata(
        'time_skip_to',
        '${state.displayShortDate} · ${state.displayClock}',
      );
      final label = state.bodyTimeLabel;
      if (label != null && label.isNotEmpty) {
        onSetPendingRealismMetadata('time_passed', label);
      }
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
  /// claimed the turn (`oocSkipMovedClockThisTurn`), so the eval's own — and
  /// correct — verdict of a few minutes was discarded in its favour. That is
  /// the "day 28 / time 16" contradiction: the notes still describe the same
  /// afternoon the scene never left.
  ///
  /// The narrated cases are untouched, because narration is not in quotes. Over
  /// the 1,050 trigger phrases in that library, 1,043 sit outside quotes and
  /// still fire; the 7 inside were false, every one.
  ///
  /// Deliberately NOT applied to [newDayCorroboration]: "goodnight" and "I'm
  /// going to sleep" are SPOKEN, so stripping quotes there would delete the
  /// evidence that a night was really crossed and quietly stop day rolls
  /// altogether. Opposite question, opposite answer.
  ///
  /// Returns the minutes skipped, 0 when [text] skipped nothing.
  Future<int> detectOocTimeSkip(String text) async {
    if (!isPassageOfTimeEnabled()) {
      debugPrint(
        '[Realism:OOC] Time-skip requested but passageOfTimeEnabled=false, ignoring',
      );
      return 0;
    }

    final lower = stripQuotedSpeech(text).toLowerCase();
    if (!shouldDetectTimeSkip(lower)) return 0;

    final next = StoryClock.resolveSkipTarget(state.clock, lower);

    final dayBefore = state.dayCount;
    final skipped = next.difference(state.clock).inMinutes;
    state.clock = next;
    state.turnsSinceClockMoved = 0;
    state.oocSkipMovedClockThisTurn = true;
    final destination = '${state.displayShortDate} · ${state.displayClock}';
    state.noteBodyBeat(
      minutes: skipped,
      nextMorning: isNightSkip(lower),
      isSkip: true,
      offScreen: true,
      skipDestination: destination,
    );
    onSetPendingRealismMetadata('time_skip_to', destination);
    if (state.bodyBeatLongSkip) {
      onSetPendingRealismMetadata(kLongSkipMinutesMeta, skipped);
    }
    onNotify();
    debugPrint(
      '[Realism:OOC] Time-skip → ${state.displayClock} ${state.displayShortDate} (Day ${state.dayCount})',
    );
    await onDayChanged(dayBefore);
    return skipped;
  }

  /// Regen of a long skip's reply: the clock already sits at [destination],
  /// so only the body beat is noted again, and the replayed reply lands the
  /// bodies the same way the first one did.
  void renoteLongSkip({required int minutes, required String destination}) {
    state.noteBodyBeat(
      minutes: minutes,
      nextMorning: false,
      isSkip: true,
      offScreen: true,
      skipDestination: destination,
    );
    onSetPendingRealismMetadata(kLongSkipMinutesMeta, minutes);
  }

  // ── Per-turn time advance (delegated from the physical / one-shot evals) ──

  /// Apply one turn's elapsed time. Null, garbage, 0, or negative on a
  /// normal send fail-closed to [StoryClock.conversationalFloorMinutes]
  /// unless [continuousInstant] or [newDay]. Clock apply never wears
  /// Needs. Returns whether the clock moved.
  Future<bool> applyElapsed({
    required int? minutes,
    required bool newDay,
    bool continuousInstant = false,
  }) async {
    final dayBefore = state.dayCount;
    final clockBefore = state.clock;
    var moved = false;
    final namedHolds =
        state.namedReconcileExact &&
        !newDay &&
        !continuousInstant &&
        (minutes == null || minutes <= 0);
    final m = StoryClock.resolvedElapsedMinutes(
      minutes: minutes,
      newDay: newDay,
      continuousInstant: continuousInstant || namedHolds,
    );
    if (m > 0 || newDay) state.namedReconcileExact = false;
    if (m > 0) {
      state.clock = state.clock.add(Duration(minutes: m));
      moved = true;
    }
    // Corroborated next-day transition. The hour gate (17:00–05:00) was
    // dropped: a nap that becomes "we slept through to morning" at 2pm is
    // still a night crossed. Hallucinations are the corroboration regex's
    // job, not the wall clock's.
    if (newDay) {
      state.clock = StoryClock.nextMorning(state.clock);
      moved = true;
    }
    var stalled = false;
    DateTime? stallFrom;
    if (moved) {
      state.turnsSinceClockMoved = 0;
    } else if (++state.turnsSinceClockMoved >= StoryClock.stallBackstopTurns) {
      stallFrom = state.clock;
      state.clock = StoryClock.snapToNextPeriod(state.clock);
      state.turnsSinceClockMoved = 0;
      moved = true;
      stalled = true;
      debugPrint(
        '[Realism:Time] Stall backstop — snapped to ${state.timeOfDay}',
      );
    }
    if (!stalled) {
      // A night crossed is the whole jump, not the minutes the eval named.
      state.noteBodyBeat(
        minutes: newDay ? state.clock.difference(clockBefore).inMinutes : m,
        nextMorning: newDay,
        isSkip: false,
        offScreen: newDay,
      );
    } else {
      state.noteBodyBeat(
        minutes: state.clock.difference(stallFrom!).inMinutes,
        nextMorning: false,
        isSkip: false,
        offScreen: false,
      );
    }
    debugPrint('[Realism:Time] committed $m min');
    await onDayChanged(dayBefore);
    return moved;
  }
}
