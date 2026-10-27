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
import 'package:front_porch_ai/services/chat/story_clock.dart';
import 'package:front_porch_ai/services/chat/time_service/time_clock_state.dart';
import 'package:front_porch_ai/services/chat/time_skip/skip_verdict.dart';

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

/// Clamp, failure floor, new_day, the player's skip, and calendar writes.
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
  /// moved off [dayBefore]. [manual] marks the chevrons and the calendar
  /// dialog: a roll made by hand, outside any turn, as opposed to one a
  /// reply, a skip or time away produced on the way to a reply.
  final Future<void> Function(int dayBefore, {bool manual}) onDayChanged;

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
    await onDayChanged(dayBefore, manual: true);
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
    final before = state.clock;
    _setClockPullingStartDate(newClock);
    // Days moved by hand were lived; the next reply's bodies show it.
    state.noteLivedJump(state.clock.difference(before).inMinutes);
    state.turnsSinceClockMoved = 0;
    onPatchLastMessageRealismState(
      state.timeOfDay,
      state.dayCount,
      state.storyClockIso,
    );
    await onDayChanged(dayBefore, manual: true);
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
      // Same skip ownership as applyUserSkip: the post-reply eval
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

  // ── The player's skip ─────────────────────────────────────────────────────

  /// Moves the clock for a skip the player asked for: [verdict] from the
  /// skip reader (time_skip/skip_reader.dart) or an exact `/skip`. The
  /// reader decides what the line means; this only lands it. Owns the turn,
  /// so the post-reply time judge adds nothing on top. Stamps the
  /// destination and the span on the reply so regen replays the same skip.
  ///
  /// Returns the minutes skipped, 0 when [verdict] skipped nothing.
  Future<int> applyUserSkip(SkipVerdict verdict) async {
    if (!isPassageOfTimeEnabled()) {
      debugPrint('[Realism:Skip] passageOfTimeEnabled=false, ignoring');
      return 0;
    }
    final before = state.clock;
    final next = verdict.landing(before);
    if (next == null || !next.isAfter(before)) return 0;

    final dayBefore = state.dayCount;
    final skipped = next.difference(before).inMinutes;
    final rested = verdict.slept && skipped >= kRestedSleepMinutes;
    state.clock = next;
    state.turnsSinceClockMoved = 0;
    state.oocSkipMovedClockThisTurn = true;
    final destination = '${state.displayShortDate} · ${state.displayClock}';
    state.noteBodyBeat(
      minutes: skipped,
      nextMorning: rested && next.hour >= 4 && next.hour < 13,
      isSkip: true,
      offScreen: true,
      skipDestination: destination,
      slept: rested,
    );
    onSetPendingRealismMetadata('time_skip_to', destination);
    onSetPendingRealismMetadata(kSkipMinutesMeta, skipped);
    if (rested) onSetPendingRealismMetadata(kSkipSleptMeta, true);
    if (state.bodyBeatLongSkip) {
      onSetPendingRealismMetadata(kLongSkipMinutesMeta, skipped);
    }
    onNotify();
    debugPrint(
      '[Realism:Skip] → ${state.displayClock} ${state.displayShortDate} '
      '(Day ${state.dayCount})',
    );
    await onDayChanged(dayBefore);
    return skipped;
  }

  /// Regen of a skip's reply: the clock already sits at [destination], so
  /// only the body beat is noted again, and the replayed reply wears (or
  /// lands, for a day or more) the bodies the same way the first one did.
  void renoteSkip(int minutes, {String? destination, bool slept = false}) {
    state.noteBodyBeat(
      minutes: minutes,
      nextMorning: false,
      isSkip: true,
      offScreen: true,
      skipDestination: destination,
      slept: slept,
    );
    onSetPendingRealismMetadata(kSkipMinutesMeta, minutes);
    if (slept) onSetPendingRealismMetadata(kSkipSleptMeta, true);
    if (state.bodyBeatLongSkip) {
      onSetPendingRealismMetadata(kLongSkipMinutesMeta, minutes);
    }
  }

  // ── Skips the reply narrates ──────────────────────────────────────────────

  int _replySkipMinutes = 0;

  /// Minutes a skip the reply narrated moved the clock, taken once: the
  /// post-reply pass settles the scene when this is a day or more.
  int takeReplySkipMinutes() {
    final minutes = _replySkipMinutes;
    _replySkipMinutes = 0;
    return minutes;
  }

  /// The judge's `days_elapsed`: a jump of days the reply narrated,
  /// landing at its `lands_at` ([until]) else in the morning.
  Future<int> applyJudgedDays(int days, {String until = ''}) => _applyLivedSkip(
    SkipVerdict(
      minutes: days.clamp(1, 365) * kLongSkipMinutes,
      until: until,
    ).landing(state.clock)!,
  );

  Future<int> _applyLivedSkip(DateTime next) async {
    if (!next.isAfter(state.clock)) return 0;
    final dayBefore = state.dayCount;
    final skipped = next.difference(state.clock).inMinutes;
    state.clock = next;
    state.turnsSinceClockMoved = 0;
    state.oocSkipMovedClockThisTurn = true;
    state.namedReconcileExact = false;
    state.noteBodyBeat(
      minutes: skipped,
      nextMorning: false,
      isSkip: true,
      offScreen: true,
      skipDestination: '${state.displayShortDate} · ${state.displayClock}',
    );
    _replySkipMinutes += skipped;
    onNotify();
    debugPrint(
      '[Realism:Time] Reply skip → ${state.displayClock} '
      '${state.displayShortDate} (Day ${state.dayCount})',
    );
    await onDayChanged(dayBefore);
    return skipped;
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
