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

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/chat/realism_tools.dart';
import 'package:front_porch_ai/services/chat/skip_language.dart';
import 'package:front_porch_ai/services/chat/story_clock.dart';
import 'package:front_porch_ai/services/chat/today_line_tag.dart';
import 'package:front_porch_ai/utils/utils.dart' show stripQuotedSpeech;

part 'time_service_eval.dart';
part 'time_service_apply.dart';

/// Plain (non-ChangeNotifier) domain service owning the chat-scoped passage-of-time
/// state — rewritten around a real datetime clock (design:
/// docs/design/story-calendar.md). Canonical state is two DateTimes:
/// [clock] (the story's current moment, minute granularity) and [startDate]
/// (Day 1's date). The six-period `timeOfDay`, `dayCount`, and the narrative
/// weekday are all pure derivations; every conversion/snap/synthesis lives in
/// the [StoryClock] leaf.
///
/// Advancement is announce-then-decide. Pre-turn the prompt says
/// "It is currently …" (OOC skip lands first so that line is honest). The
/// scene-time eval fires AFTER the reply, reports `minutes_elapsed` for the
/// beat that was just written, and that instant is what the NEXT speaker is
/// told — group bucket brigade, Scene Guests included. Continue does not
/// tick (same beat). Hard-clamped by [StoryClock.maxMinutesPerTurn], with
/// [StoryClock.failureDriftMinutes] as the deterministic floor on eval
/// failure and a [StoryClock.stallBackstopTurns]-turn backstop so time can
/// never freeze forever. The old 6-turn gate, its `hold_time` veto, and the
/// eligible/not-eligible prompt branching are gone.
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
/// Regen/swipe rewind the clock from the rejected reply's
/// `story_clock_before` stamp, then the post-reply eval decides again —
/// engine, standalone, and Scene Guest share that receipt. Without it a
/// swipe would double-advance.
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
  final FutureOr<void> Function()? onStoryDayChanged;

  /// When true, the scene-time eval (and one-shot text) asks for
  /// `today_sentence`. Default off so existing constructors stay valid.
  final bool Function()? getPlannerEnabled;

  /// Empty string = abandon; non-empty = set. Do not write [todayLine]
  /// from the eval — ChatService owns the hold via this callback.
  final FutureOr<void> Function(String line)? onTodayEval;

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

  Future<void> _ifDayChanged(int dayBefore) async {
    if (dayCount == dayBefore) return;
    clearTodayLine();
    await onStoryDayChanged?.call();
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
  final Object? fireToolEval;
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

  /// Class door so callers with only the [TimeService] type still reach eval.
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
    bool skipTodayEval = false,
  }) => _evaluateTimeProgressAndPostureIfNeeded(
    charName: charName,
    recent: recent,
    shortTermTierName: shortTermTierName,
    onChunk: onChunk,
    fireLLMEval: fireLLMEval,
    stripThinkBlocks: stripThinkBlocks,
    extractJsonBool: extractJsonBool,
    setSpatialStance: setSpatialStance,
    getCurrentSpatialStance: getCurrentSpatialStance,
    getCharacterEmotion: getCharacterEmotion,
    getEmotionIntensity: getEmotionIntensity,
    oneShotMode: oneShotMode,
    oneShotText: oneShotText,
    timeOnly: timeOnly,
    postureOnly: postureOnly,
    skipClockAdvance: skipClockAdvance,
    skipTodayEval: skipTodayEval,
  );

  /// Class door for the calendar set. Continue still does not tick.
  Future<void> setClockDirect(DateTime newClock) => _setClockDirect(newClock);

  // ── Public surface ────────────────────────────────────────────────────────

  DateTime get clock => _clock;
  DateTime get startDate => _startDate;
  String get timeOfDay => StoryClock.periodForHour(_clock.hour);

  /// Live clock as minutes from midnight. Presence matches this, not
  /// the period's representative hour.
  int get clockMinutes => _clock.hour * 60 + _clock.minute;
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
}
