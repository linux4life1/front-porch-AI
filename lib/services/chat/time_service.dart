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
part 'time_service_load.dart';

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

  /// Class door for V2 / ext-seed. Callers that only have the [TimeService]
  /// type (tests via `chat.timeService`, goldens) cannot see the load
  /// extension — same class-door rule as [setClockDirect].
  void seedFromV2OrExt({
    required int dayCount,
    required String timeOfDay,
    required bool passageOfTimeEnabled,
    String? storyStartDate,
    String? storyStartTime,
  }) => _seedFromV2OrExt(
    dayCount: dayCount,
    timeOfDay: timeOfDay,
    passageOfTimeEnabled: passageOfTimeEnabled,
    storyStartDate: storyStartDate,
    storyStartTime: storyStartTime,
  );

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
