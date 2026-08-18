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

import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/chat/realism_tools.dart';
import 'package:front_porch_ai/services/chat/story_clock.dart';
import 'package:front_porch_ai/services/chat/today_line_tag.dart';
import 'package:front_porch_ai/services/services.dart' show LlmToolResponse;
import 'package:front_porch_ai/utils/utils.dart' show stripQuotedSpeech;

/// Plain (non-ChangeNotifier) domain service owning the chat-scoped passage-of-time
/// state — rewritten around a real datetime clock (design:
/// docs/design/story-calendar.md). Canonical state is two DateTimes:
/// [clock] (the story's current moment, minute granularity) and [startDate]
/// (Day 1's date). The six-period `timeOfDay`, `dayCount`, and the narrative
/// weekday are all pure derivations; every conversion/snap/synthesis lives in
/// the [StoryClock] leaf.
///
/// Advancement is continuous and per-turn: the scene-time eval (which fires
/// every turn, BEFORE generation, so the character knows what time it is
/// while writing) reports `minutes_elapsed` for the latest exchange,
/// hard-clamped by
/// [StoryClock.maxMinutesPerTurn], with [StoryClock.failureDriftMinutes] as
/// the deterministic floor on eval failure and a
/// [StoryClock.stallBackstopTurns]-turn backstop that snaps to the next
/// period so time can never freeze forever. The old 6-turn gate, its
/// `hold_time` veto, and the eligible/not-eligible prompt branching are gone.
///
/// ── PASSAGE OF TIME AND THE REALISM ENGINE: THE SEAM, AND WHERE IT IS ────
///
/// SUPERSEDES the 2026-08-02 "cannot be decoupled" ruling that stood here.
/// That ruling rested on a misreading: the maintainer said passage of time
/// requires MODEL USAGE ("the fallback deterministic passage of time is not
/// usable as is but an emergency 'oh shit'"), which was recorded as requiring
/// the ENGINE. Those are different claims. Time needs an eval; it does not
/// need bond, trust, emotion or arousal. Decoupled 2026-08-06.
///
/// What was true then and is still true — reason 1 of the old four, and the
/// reason this class fires a model call at all:
///
///   THE QUALITY OF TIME *IS* AN LLM EVAL. How far the clock moves comes from
///   [_fireSceneTimeEval] asking a model how long the latest exchange took.
///   Remove that and the only thing left is [StoryClock.failureDriftMinutes],
///   which is a FAILURE fallback, not a time model: a two-line greeting and a
///   two-hour dinner would advance the clock by the same fixed constant. Time
///   would keep ticking and stop meaning anything. The deterministic drift
///   below is therefore NEVER a mode, never surfaced, never a reason to claim
///   the clock works without a model — it is the cushion for one failed call.
///
/// What the other three turned out to be:
///
/// 2. FUSED WITH POSTURE — a cost, not a barrier, and this file already
///    disproved it: the posture-ONLY branch below has always existed.
///    `timeOnly` is that same shape mirrored. (Since 2026-08-08 the fusion is
///    gone outright — posture moved to its own POST-generation pass, see
///    [evaluateTimeProgressAndPostureIfNeeded] — so the time call now asks
///    one question in every mode.)
/// 3. ONE-SHOT HAS NO TIME CALL TO EXTRACT — true and irrelevant. One-shot is
///    a REALISM optimization; with the engine off there is no fused JSON to
///    lift a field out of. The paths never intersect, so one-shot parity is
///    untouched by construction.
/// 4. "THE WIRE FORMAT IS `realism_state`, so this needs a migration" — this
///    was simply wrong. The clock's store of record is the session row
///    (`sessions.story_clock` / `story_start_date` / `passage_of_time_enabled`),
///    written and read unconditionally, engine or no engine.
///    `realism_state` is the per-message swipe/regen REWIND snapshot, not
///    persistence. No migration exists to perform.
///
/// The standalone clock is opt-in (`standaloneClockEnabled`, default off)
/// because it costs one model call per turn — see that flag for why the
/// existing Passage-of-Time default could not be treated as consent.
///
/// Deliberately NOT changed: nothing rewinds the standalone clock on
/// swipe/regen, and nothing needs to. The engine path rewinds because it
/// re-runs its eval and would otherwise double-advance; the standalone eval
/// fires once per user turn from sendMessage and never re-fires on a
/// regenerate, so the clock already sits at exactly one advance for the turn.
/// Adding a rewind there would be a bug, not a parity fix.
///
/// The OOC time-skip path ([detectOocTimeSkip]) is pure regex and stands on
/// its own — but it is a narrow fast path over enumerated phrasings and does
/// not cover a model narrating a long journey in words nobody listed. It is
/// not a substitute for the eval.
///
/// Time remains *chat-scoped* (shared across group members, not per-speaker).
/// Cross-state (pending chip metadata, last-message realism_state patching
/// for nudge/set survival across swipe/regen/reload, save/notify) is accessed
/// exclusively via the granular callbacks supplied at construction — same
/// extraction contract as the other chat/ leaves.
///
/// Legacy wire formats (`timeOfDay`/`dayCount`/`startDayOfWeek` in session
/// rows, realism_state snapshots, group blobs, and V2 card extensions) are
/// written as derivations and read as seeds.
///
/// THE STORY DATE IS NOT ALLOWED TO FOLLOW THE REAL CALENDAR (2026-08-08).
/// Every legacy read used to resolve through [StoryClock.fromLegacy] against
/// `todayAnchor()`, and none of them wrote the answer back — so the same chat
/// reported a different date on Monday and on Saturday while its journal and
/// recap still named the first one. That is a contradiction we hand the model
/// in its own prompt, and it is the single largest one the conflict-sentence
/// mining found (day 28 · time 16 of 461). `fromLegacy` now has exactly ONE
/// caller: [loadTimeScalars]'s branch for a row with neither canonical column,
/// which flags itself via [canonicalClockWasSynthesised] so the loader freezes
/// the result into the row on the spot. Everything else derives from state we
/// already hold. Do not reintroduce a wall-clock read on a load or restore
/// path: `DateTime.now()` belongs to a NEW chat's start date and nowhere else.
class TimeService {
  final VoidCallback onNotify;
  final Future<void> Function() onSaveChat;

  // onSetPendingRealismMetadata: OOC skips stamp 'time_skip_to' for delta chips.
  // onPatchLastMessageRealismState: manual nudge / calendar set changed time —
  // god patches the last msg's realism_state snapshot (swipe/regen survival)
  // with the derived period/day AND the canonical clock.
  final void Function(String key, dynamic value) onSetPendingRealismMetadata;
  final void Function(String timeOfDay, int dayCount, String storyClockIso)
  onPatchLastMessageRealismState;

  /// Fires when the story day actually rolls. ChatService journals
  /// the held today sentence here — not in a getter.
  final void Function()? onStoryDayChanged;

  /// When true, the scene-time eval (and one-shot text) asks for
  /// `today_sentence`. Default off so existing constructors stay valid.
  final bool Function()? getPlannerEnabled;

  /// Empty string = abandon; non-empty = set. Do not write [todayLine]
  /// from the eval — ChatService owns the hold via this callback.
  final void Function(String line)? onTodayEval;

  // Owned state — the whole subsystem.
  DateTime _clock = StoryClock.representativeTime(
    StoryClock.todayAnchor(),
    'morning',
  );
  DateTime _startDate = StoryClock.todayAnchor();
  bool _passageOfTimeEnabled = true;
  int _turnsSinceClockMoved = 0; // stall backstop counter (not a pacing gate)
  bool _canonicalClockWasSynthesised = false;
  // One clock authority per turn: set when detectOocTimeSkip moves the clock,
  // consumed by the per-turn eval so it can't re-count the same exchange.
  bool _oocSkipMovedClockThisTurn = false;
  String? todayLine;
  int? _todayLineDayCount;

  void clearTodayLine() {
    todayLine = null;
    _todayLineDayCount = null;
  }

  void _ifDayChanged(int dayBefore) {
    if (dayCount == dayBefore) return;
    clearTodayLine();
    onStoryDayChanged?.call();
  }

  String? get visibleTodayLine {
    final line = todayLine?.trim();
    if (line == null || line.isEmpty) return null;
    if (_todayLineDayCount != null && _todayLineDayCount != dayCount) {
      todayLine = null;
      _todayLineDayCount = null;
      return null;
    }
    return line;
  }

  // Tools transport for the scene-time and posture evals (nullable — tests and
  // any host without the tools door stay on the text path).
  final Future<LlmToolResponse?> Function(
    String prompt,
    List<Map<String, dynamic>> tools,
  )?
  fireToolEval;
  final ToolTransportProbe? probe;
  final String Function()? getBackendIdentity;

  TimeService({
    required this.onNotify,
    required this.onSaveChat,
    required this.onSetPendingRealismMetadata,
    required this.onPatchLastMessageRealismState,
    this.onStoryDayChanged,
    this.fireToolEval,
    this.probe,
    this.getBackendIdentity,
    this.getPlannerEnabled,
    this.onTodayEval,
  });

  // ── Public surface ────────────────────────────────────────────────────────

  DateTime get clock => _clock;
  DateTime get startDate => _startDate;
  String get timeOfDay => StoryClock.periodForHour(_clock.hour);
  int get dayCount => StoryClock.dayCountFor(_clock, _startDate);

  /// The set-aside-clothing day: flips at the story MORNING (08:00), not
  /// midnight, so a scene running past 00:00 keeps its outfit recoverable.
  /// See [StoryClock.morningDayCountFor].
  int get morningAnchoredDayCount =>
      StoryClock.morningDayCountFor(_clock, _startDate);
  bool get passageOfTimeEnabled => _passageOfTimeEnabled;
  String get narrativeWeekday => StoryClock.weekdayName(_clock);

  /// Derived legacy anchor — still written to the session row / snapshots so
  /// external readers (Character Card Forge, older apps via The Stoop) keep
  /// seeing a consistent value.
  int get startDayOfWeekAnchor => _startDate.weekday;

  String get storyClockIso => StoryClock.serializeClock(_clock);
  String get storyStartDateIso => StoryClock.serializeDate(_startDate);

  /// True when the last [loadTimeScalars] had to INVENT part of the canonical
  /// clock because the session row predates the Story Calendar (v38). The
  /// caller MUST write [storyClockIso] / [storyStartDateIso] back to the row.
  ///
  /// THE BUG THIS EXISTS TO END. The v38 ladder note says legacy rows
  /// "synthesize on first load" — but nothing ever persisted that synthesis, so
  /// it ran again on EVERY load, and its only anchor is
  /// [StoryClock.todayAnchor], the real-world calendar. The in-story date
  /// therefore followed the day you happened to open the chat: opened on a
  /// Monday it reported Monday; reopened on the Saturday it reported Saturday,
  /// while the journal cards and the "Where we are" recap written earlier still
  /// named the old one. The model then spends its reasoning deciding which of
  /// our own answers to believe ("Saturday August 8th (Day 1) — wait, earlier it
  /// was Monday, but the notes say Saturday").
  ///
  /// It was not a rare corner: 96 of the 109 sessions in the maintainer's own
  /// library still had NULL `story_clock`/`story_start_date`, because the
  /// columns are only written by a full chat save — opening a chat, reading it
  /// and closing it never froze the date, so those chats wandered indefinitely.
  bool get canonicalClockWasSynthesised => _canonicalClockWasSynthesised;

  /// "9:40 PM" / "Tue, Mar 3" / "Tuesday, March 3rd(, 1887)" for the UI.
  String get displayClock => StoryClock.formatClock(_clock);
  String get displayShortDate => StoryClock.formatShortDate(_clock);
  String get displayDate =>
      StoryClock.formatDate(_clock, realYear: StoryClock.todayAnchor().year);

  /// Fire one scene-time or posture eval through the shared tools-vs-text
  /// negotiation (or straight text when the tools door isn't wired).
  /// [tools] selects the posture schema or the time-only one; both carry the
  /// same tool NAME, so everything downstream is one code path.
  Future<String?> _fireSceneTimeEval(
    String Function({required bool toolsMode}) buildPrompt, {
    required Future<String?> Function(
      String prompt, {
      void Function(String)? onChunk,
    })
    fireLLMEval,
    void Function(String)? onChunk,
    List<Map<String, dynamic>>? tools,
  }) => fireToolEval != null && probe != null
      ? fireStructuredEval(
          probe: probe!,
          backendIdentity: getBackendIdentity?.call() ?? '',
          debugLabel: kSceneTimeTool,
          tools: tools ?? kSceneTimeEvalTools,
          buildPrompt: buildPrompt,
          callToText: (resp) =>
              realismToolCallToJson(kSceneTimeTool, resp.calls),
          fireToolEval: fireToolEval!,
          fireTextEval: fireLLMEval,
          onChunk: onChunk,
        )
      : fireLLMEval(buildPrompt(toolsMode: false), onChunk: onChunk);

  // ── Mutation for control / loads (side-effect free; wrappers do save/notify) ──

  void setPassageOfTimeEnabled(bool enabled) {
    _passageOfTimeEnabled = enabled;
  }

  void resetForFreshChat() {
    _startDate = StoryClock.todayAnchor();
    _clock = StoryClock.representativeTime(_startDate, 'morning');
    _turnsSinceClockMoved = 0;
    _oocSkipMovedClockThisTurn = false;
    _passageOfTimeEnabled = true;
    // A brand-new chat has nothing to write back — its clock reaches the row
    // through the ordinary save. Leaving a previous chat's `true` standing here
    // would ask the loader to patch a row this service no longer describes.
    _canonicalClockWasSynthesised = false;
    todayLine = null;
    _todayLineDayCount = null;
  }

  /// Seed from a V2 card / ext-seed payload (design §3a). [storyStartDate]
  /// null means "the story begins the day the chat starts" — what every
  /// pre-calendar card implicitly meant; a fixed date carries its own era.
  /// [storyStartTime] ("HH:MM") lets an author pin the exact opening clock;
  /// otherwise the period's representative time applies.
  void seedFromV2OrExt({
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

  // ── Manual control (chevrons + calendar dialog) ───────────────────────────

  /// Sidebar chevrons: snap to the previous/next period's representative
  /// time. delta = +1 (forward) or -1 (back). Signals god to patch the last
  /// msg realism_state so swipe/regen cannot revert it.
  void nudgeTimePeriod(int delta) {
    final dayBefore = dayCount;
    _clock = delta >= 0
        ? StoryClock.snapToNextPeriod(_clock)
        : StoryClock.snapToPreviousPeriod(_clock);
    if (_clock.isBefore(_startDate)) _startDate = StoryClock.dateOnly(_clock);
    _turnsSinceClockMoved = 0;
    _ifDayChanged(dayBefore);
    onPatchLastMessageRealismState(timeOfDay, dayCount, storyClockIso);
  }

  /// Calendar dialog: set the story's current moment directly. Pulls the
  /// anchor back when the new moment predates Day 1 (the story now starts
  /// earlier). Same swipe-survival patch as a nudge.
  void setClockDirect(DateTime newClock) {
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
    _ifDayChanged(dayBefore);
    onPatchLastMessageRealismState(timeOfDay, dayCount, storyClockIso);
  }

  /// Post-reply: she named a time, so the live clock follows. Not a user
  /// nudge — swipe/regen still rewind from the previous snapshot.
  void applyReconciledClock(DateTime newClock) {
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
    _ifDayChanged(dayBefore);
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
  void advanceTimePeriods(int count) {
    if (!_passageOfTimeEnabled) return;
    for (var i = 0; i < count; i++) {
      _clock = StoryClock.snapToNextPeriod(_clock);
    }
    if (count > 0) _turnsSinceClockMoved = 0;
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
  void detectOocTimeSkip(String text) {
    if (!_passageOfTimeEnabled) {
      debugPrint(
        '[Realism:OOC] Time-skip requested but passageOfTimeEnabled=false, ignoring',
      );
      return;
    }

    final lower = stripQuotedSpeech(text).toLowerCase();

    final hasOocMarker = RegExp(
      r'\(ooc[:\s]|\[ooc|\*ooc\b|ooc:',
    ).hasMatch(lower);
    final hasSkipPhrase = RegExp(
      r'\b(time.?skip|fast.?forward|skip ahead|several hours|a few hours|hours? later|'
      r'the next (morning|day|evening|afternoon|night|dawn)|'
      r'next (morning|day|evening|afternoon|night|dawn)|'
      r'hours? pass|time passes|the following (morning|day)|'
      r'wake up the next|woke up|the next day|'
      r'(a|one) week (later|passes)|next week|weeks? later|'
      r'(a|one) month (later|passes)|next month)\b',
    ).hasMatch(lower);

    if (!hasOocMarker && !hasSkipPhrase) return;

    // An OOC marker alone is not a time skip. Without actual time language
    // ("skip an hour", "a while later") the note is direction/flavor — a
    // bare "(OOC: ...)" used to advance the clock a silent +1h per note.
    final hasDurationHint = RegExp(
      r'\b(an? hour|half an hour|\d+\s*(minutes?|hours?|days?|weeks?)|'
      r'a while|some ?time|later|skip|fast.?forward|advance|pass(es|ing)?)\b',
    ).hasMatch(lower);
    if (!hasSkipPhrase && !hasDurationHint) return;

    // Most specific duration language first.
    DateTime next;
    if (RegExp(
      r'\b(a|one)? ?month (later|passes)|next month\b',
    ).hasMatch(lower)) {
      // The 1st of the following month, mid-morning (design §7).
      next = DateTime.utc(_clock.year, _clock.month + 1, 1, 9);
    } else if (RegExp(
      r'\b((a|one) week (later|passes)|next week|weeks? later)\b',
    ).hasMatch(lower)) {
      next = _clock.add(const Duration(days: 7));
    } else if (RegExp(
      r'\b(next (morning|day)|the following (morning|day)|wake up|woke up|overnight|the next day)\b',
    ).hasMatch(lower)) {
      next = StoryClock.nextMorning(_clock);
    } else if (RegExp(
      r'\b(all day|entire day|full day|day passes|the (whole|entire) day)\b',
    ).hasMatch(lower)) {
      next = _clock.add(const Duration(hours: 8));
    } else if (RegExp(
      r'\b(several hours|many hours|a long time|hours? pass)\b',
    ).hasMatch(lower)) {
      next = _clock.add(const Duration(hours: 3));
    } else if (RegExp(
      r'\b(a few hours|couple.{0,5}hours|2.{0,5}hours|two hours)\b',
    ).hasMatch(lower)) {
      next = _clock.add(const Duration(hours: 2));
    } else {
      // "an hour", "a while", "some time", or a bare OOC marker.
      next = _clock.add(const Duration(hours: 1));
    }

    final dayBefore = dayCount;
    _clock = next;
    _turnsSinceClockMoved = 0;
    _ifDayChanged(dayBefore);
    _oocSkipMovedClockThisTurn = true;
    onSetPendingRealismMetadata(
      'time_skip_to',
      '$displayShortDate · $displayClock',
    );
    onNotify();
    debugPrint(
      '[Realism:OOC] Time-skip → $displayClock $displayShortDate (Day $dayCount)',
    );
  }

  // ── Per-turn time advance (delegated from the physical / one-shot evals) ──

  /// Apply one turn's elapsed time. [minutes] null means the eval failed —
  /// deterministic drift applies. Returns whether the clock moved.
  bool _applyElapsed({required int? minutes, required bool newDay}) {
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
    // Explicit next-day transition — valid from evening onward (incl. the
    // small hours past midnight, which ARE "that night" narratively).
    if (newDay && (_clock.hour >= 17 || _clock.hour < 5)) {
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
    _ifDayChanged(dayBefore);
    return moved;
  }

  static int? _extractMinutes(String text) {
    final m = RegExp(r'"minutes_elapsed"\s*:\s*"?(-?\d+)').firstMatch(text);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  void _maybeApplyTodayEval(String text) {
    if (!(getPlannerEnabled?.call() ?? false)) return;
    final parsed = TodayLineTag.parseEvalSentence(text);
    if (parsed != null) onTodayEval?.call(parsed);
  }

  /// The posture question alone — shared VERBATIM between the standalone
  /// post-generation posture pass above and the fused reply-facts prompt
  /// (ReplyFactsEval), so the two transports can never drift in what they
  /// ask. Do not re-inline into either caller; the fusion parity test pins
  /// both.
  static String postureQuestion({
    required String charName,
    String emotionCtx = '',
    String postureCtx = '',
    required String displayClock,
  }) =>
      '$emotionCtx$postureCtx'
      'Current time: $displayClock.\n\n'
      'What is $charName\'s current physical position and stance? Use "none" if unclear.\n'
      '- Match the posture to the current scene context and emotional state.\n'
      '- Within the same scene, maintain natural continuity (don\'t jump locations).\n'
      '- Across scene breaks or time jumps, update to the new context.\n\n';

  /// The ONE posture parser — used by the standalone pass above and by the
  /// fused reply-facts consumption in the post-generation phase, so a change
  /// to what counts as an answer can never apply to one transport and not
  /// the other.
  static String? parsePosture(String text) {
    final m = RegExp(r'"posture"\s*:\s*"([^"]+)"').firstMatch(text);
    return m?.group(1)?.trim();
  }

  /// Deterministic corroboration gate for the eval's `new_day` flag. The flag
  /// bypasses [StoryClock.maxMinutesPerTurn] entirely (it's the only way the
  /// clock can cross a night in one turn), and small eval models hallucinate
  /// it — a scene full of "the beach where we met yesterday" talk produced
  /// new_day=true at 6:30 PM and slammed the story to next morning. Honor the
  /// flag only when the exchange actually contains sleep/wake/next-day
  /// language; without it the turn still gets its clamped minutes_elapsed.
  static final RegExp _newDayCorroboration = RegExp(
    r'\b(sleep|slept|asleep|falls? asleep|wake|woke|waking|good.?night|'
    r'next (morning|day)|the following (morning|day)|overnight|'
    r'in the morning|calls? it a night|turn(s|ed|ing)? in for the night|'
    r'sunrise|daybreak|dawn broke)\b',
    caseSensitive: false,
  );

  /// Per-turn scene-time evaluation (design §2) and — in [postureOnly] mode —
  /// the post-generation posture pass.
  ///
  /// ── WHY POSTURE IS A SEPARATE CALL, AFTER GENERATION (2026-08-08) ────────
  ///
  /// Posture used to ride this same call, fused with minutes_elapsed/new_day,
  /// fired BEFORE the reply was written. That defeated the whole point of the
  /// feature. Spatial stance exists so a character does not teleport around a
  /// room between turns: the position is injected imperatively into the next
  /// reply ("Position: X — ground actions in this",
  /// prompt_injection/behavioral_injection.dart). But a position a character
  /// establishes IN her reply — she crosses the room and sits on the
  /// windowsill — could not possibly be seen by a judge that ran before that
  /// reply existed, and the next turn's pre-generation judge simply
  /// re-derived a fresh guess and overwrote it. The prompt then asserted the
  /// stale position as fact. Maintainer ruling, verbatim: "spatial awareness
  /// check should run post character message, otherwise how could it check
  /// where she moved or what she is doing".
  ///
  /// So posture is now exactly the kind of fact Pockets and Afterglow are —
  /// something the REPLY changed — and it runs where they run, reading the
  /// text that was just written (chat_service_generation_postgen.dart).
  /// TIME did not move: the clock must advance before the reply so the
  /// character knows what time it is while writing it.
  ///
  /// [postureOnly] is that pass. It is the SAME branch that used to serve
  /// "passage of time is off, so ask about posture alone" — promoted to a
  /// flag instead of being reachable only through a disabled clock, so there
  /// is one posture prompt in the app rather than two that must be kept in
  /// step. It ignores [_passageOfTimeEnabled] entirely: where a character is
  /// standing has nothing to do with whether the story clock ticks.
  ///
  /// In oneShotMode the fused one-shot JSON (passed as [oneShotText]) carries
  /// minutes_elapsed/new_day, so no call fires here; this method only applies
  /// the clock math (strict one-shot parity: same clamp, floor, and backstop
  /// against the same clock). One-shot no longer carries posture either — it
  /// is a PRE-generation optimisation and posture is no longer a
  /// pre-generation question.
  ///
  /// [timeOnly] is the standalone clock: the Realism Engine is OFF and the
  /// user opted the clock in anyway, so the prompt drops the scene framing
  /// (mood, last known position, relationship tension) that nothing reads
  /// with the engine off. Everything AFTER the eval is the shared code below:
  /// the same [_extractMinutes], the same [_newDayCorroboration] guard, the
  /// same [_applyElapsed] clamp/floor/backstop against the same clock. That
  /// sharing is what makes engine-on and standalone advance identically for
  /// an identical verdict, rather than by promise.
  Future<void> evaluateTimeProgressAndPostureIfNeeded({
    required String charName,
    required String recent,
    required String shortTermTierName,
    required void Function(String)? onChunk,
    required Future<String?> Function(
      String prompt, {
      void Function(String)? onChunk,
    })
    fireLLMEval,
    required String Function(String) stripThinkBlocks,
    required bool? Function(String, String) extractJsonBool,
    required void Function(String) setSpatialStance,
    required String Function() getCurrentSpatialStance,
    required String Function() getCharacterEmotion,
    required String Function() getEmotionIntensity,
    bool oneShotMode = false,
    String? oneShotText,
    bool timeOnly = false,
    bool postureOnly = false,
    bool skipClockAdvance = false,
  }) async {
    // Realism context, and therefore skipped entirely in timeOnly mode.
    final emotionCtx = !timeOnly && getCharacterEmotion().isNotEmpty
        ? '$charName is currently feeling ${getCharacterEmotion()} (${getEmotionIntensity()}). '
        : '';
    final postureCtx = !timeOnly && getCurrentSpatialStance().isNotEmpty
        ? 'Recent position reference: $charName was "${getCurrentSpatialStance()}". '
        : '';

    if (postureOnly) {
      // Where she ended up. [recent] here is the window AFTER the reply was
      // appended, so the exchange this reads is the one the character just
      // wrote — the whole reason the pass moved. Deliberately NOT gated on
      // _passageOfTimeEnabled: a frozen clock does not freeze a room.
      String buildPosturePrompt({required bool toolsMode}) =>
          '${postureQuestion(charName: charName, emotionCtx: emotionCtx, postureCtx: postureCtx, displayClock: displayClock)}'
          'Recent conversation:\n$recent\n\n'
          '${toolsMode ? 'Report by calling the $kSceneTimeTool tool with "posture". Use ONLY the tool — no plain-text reply.' : 'Respond with ONLY valid JSON. Do NOT use markdown code blocks — return raw JSON only.\n'
                    'Example: {"posture": "standing by the window"} or {"posture": "none"}'}';
      try {
        final raw = await _fireSceneTimeEval(
          buildPosturePrompt,
          fireLLMEval: fireLLMEval,
          onChunk: onChunk,
        );
        if (raw != null) {
          final text = stripThinkBlocks(raw).isNotEmpty
              ? stripThinkBlocks(raw)
              : raw;
          final posture = parsePosture(text);
          if (posture != null) {
            setSpatialStance(posture);
          }
        }
      } catch (_) {}
      debugPrint('[Realism:Posture] ${getCurrentSpatialStance()} (post-reply)');
      return;
    }

    // Nothing to advance. Posture no longer falls back to this call — it has
    // its own post-generation pass above — so a frozen clock now costs the
    // user nothing at all rather than one posture request per turn.
    if (!_passageOfTimeEnabled) return;
    if (skipClockAdvance) {
      debugPrint('[Realism:Time] follow-up speaker — clock already moved');
      return;
    }

    final newDayCorroborated = _newDayCorroboration.hasMatch(recent);
    void logSuppressedNewDay() => debugPrint(
      '[Realism:Time] new_day=true suppressed — no sleep/wake language '
      'in the recent exchange (hallucination guard)',
    );

    // One clock authority per turn (chip/clock parity): when an OOC or
    // narrative skip already moved the clock for this exchange, this eval
    // must not count the same exchange again — the double-advance is how a
    // "Time skip: 11:50 PM" chip ended up under a 1:05 AM sidebar clock.
    // The flag suppresses minutes, new_day and the failure drift — nothing
    // else. (It used to add "posture still evaluates", which stopped being
    // true when posture left this call for its own post-generation pass
    // above; a skipped turn's position now comes from that pass, which never
    // reaches this branch.)
    final skipOwnsClock = _oocSkipMovedClockThisTurn;
    _oocSkipMovedClockThisTurn = false;

    if (oneShotMode) {
      // The fused JSON already carries minutes_elapsed/new_day. Clock math
      // only — no LLM call. (Posture is NOT in it any more; it has its own
      // post-generation pass.)
      final text = oneShotText ?? '';
      if (skipOwnsClock) {
        debugPrint(
          '[Realism:Time] OOC skip owns this turn — one-shot clock '
          'movement suppressed',
        );
        _maybeApplyTodayEval(text);
        return;
      }
      final saidNewDay = extractJsonBool(text, 'new_day') ?? false;
      if (saidNewDay && !newDayCorroborated) logSuppressedNewDay();
      _applyElapsed(
        minutes: _extractMinutes(text),
        newDay: saidNewDay && newDayCorroborated,
      );
      _maybeApplyTodayEval(text);
      debugPrint(
        '[Realism:Time] One-shot elapsed applied → $displayClock (Day $dayCount)',
      );
      return;
    }

    // The two minutes_elapsed / new_day rules are written once and shared, so
    // the standalone clock cannot be tuned apart from the engine's by someone
    // editing one copy.
    final plannerToday = getPlannerEnabled?.call() ?? false;
    final timeRules =
        '1. "minutes_elapsed": how many in-story minutes passed during the LATEST exchange below (integer, 0-${StoryClock.maxMinutesPerTurn}). '
        'Most conversational exchanges take 2-15 minutes; activities (a meal, a walk, a task, travel) take longer. '
        'Use 0 ONLY when the scene is a continuous instant (mid-action, mid-sentence).\n'
        '2. "new_day": true ONLY if the conversation explicitly transitioned to the next day (slept, woke up, scene break). false otherwise. '
        'Merely MENTIONING yesterday, tomorrow, or another day does NOT count — the characters must actually cross a night.\n'
        '${plannerToday ? '3. "today_sentence": one sentence of what they are doing or planning today. '
                  'Empty or "none" abandons the current hold. Omit to keep it.\n' : ''}';

    // ONE time prompt for both drivers. The engine adds its scene framing
    // (mood, last known position, relationship tension); the standalone clock
    // asks the question bare, because with the engine off nothing reads those
    // scalars and paying tokens to restate them spends a user's budget on
    // context nobody consumes. Neither asks for posture any more — see the
    // ruling on this method: posture is about the reply that has not been
    // written yet at this point in the turn.
    String buildPrompt({required bool toolsMode}) =>
        'You are evaluating how much story time just passed'
        '${timeOnly ? '' : ' for $charName'}.\n\n'
        '${timeOnly ? '' : '$emotionCtx$postureCtx'
                  'Relationship tension: $shortTermTierName.\n'}'
        'Current story time: $displayClock on $narrativeWeekday, Day $dayCount.\n\n'
        '$timeRules\n'
        'Recent conversation:\n$recent\n\n'
        '${toolsMode ? 'Report by calling the $kSceneTimeTool tool with "minutes_elapsed" and "new_day"${plannerToday ? ' and "today_sentence"' : ''}. Use ONLY the tool — no plain-text reply.' : 'Respond with ONLY a flat JSON object containing "minutes_elapsed" and "new_day"${plannerToday ? ' and "today_sentence"' : ''}. '
                  'Do NOT use markdown code blocks — return raw JSON only.'}';

    try {
      final raw = await _fireSceneTimeEval(
        buildPrompt,
        fireLLMEval: fireLLMEval,
        onChunk: onChunk,
        tools: plannerToday
            ? kSceneTimeOnlyEvalToolsWithToday
            : kSceneTimeOnlyEvalTools,
      );
      if (raw != null) {
        final text = stripThinkBlocks(raw).isNotEmpty
            ? stripThinkBlocks(raw)
            : raw;
        if (skipOwnsClock) {
          debugPrint(
            '[Realism:Time] OOC skip owns this turn — eval clock '
            'movement suppressed',
          );
        } else {
          final saidNewDay = extractJsonBool(text, 'new_day') ?? false;
          if (saidNewDay && !newDayCorroborated) logSuppressedNewDay();
          _applyElapsed(
            minutes: _extractMinutes(text),
            newDay: saidNewDay && newDayCorroborated,
          );
        }
        _maybeApplyTodayEval(text);
      } else if (!skipOwnsClock) {
        _applyElapsed(minutes: null, newDay: false);
      }
    } catch (e) {
      // Eval failed — deterministic drift so time never freezes (unless the
      // OOC skip already moved this turn's clock).
      if (!skipOwnsClock) {
        _applyElapsed(minutes: null, newDay: false);
      }
      debugPrint('[Realism:Time] Eval error, drifted to $displayClock: $e');
    }

    debugPrint(
      '${timeOnly ? '[Clock:Standalone]' : '[Realism:Time]'} '
      'Time: $displayClock $displayShortDate (Day $dayCount)',
    );
  }
}
