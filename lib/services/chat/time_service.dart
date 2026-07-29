// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Software Foundation, either version 3 of the License, or
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
import 'package:front_porch_ai/services/llm_service.dart' show LlmToolResponse;

/// Plain (non-ChangeNotifier) domain service owning the chat-scoped passage-of-time
/// state — rewritten around a real datetime clock (design:
/// docs/design/story-calendar.md). Canonical state is two DateTimes:
/// [clock] (the story's current moment, minute granularity) and [startDate]
/// (Day 1's date). The six-period `timeOfDay`, `dayCount`, and the narrative
/// weekday are all pure derivations; every conversion/snap/synthesis lives in
/// the [StoryClock] leaf.
///
/// Advancement is continuous and per-turn: the scene-time eval (which already
/// fires every turn — it used to carry posture alone on non-eligible turns)
/// reports `minutes_elapsed` for the latest exchange, hard-clamped by
/// [StoryClock.maxMinutesPerTurn], with [StoryClock.failureDriftMinutes] as
/// the deterministic floor on eval failure and a
/// [StoryClock.stallBackstopTurns]-turn backstop that snaps to the next
/// period so time can never freeze forever. The old 6-turn gate, its
/// `hold_time` veto, and the eligible/not-eligible prompt branching are gone.
///
/// Time remains *chat-scoped* (shared across group members, not per-speaker).
/// Cross-state (pending chip metadata, last-message realism_state patching
/// for nudge/set survival across swipe/regen/reload, save/notify) is accessed
/// exclusively via the granular callbacks supplied at construction — same
/// extraction contract as the other chat/ leaves.
///
/// Legacy wire formats (`timeOfDay`/`dayCount`/`startDayOfWeek` in session
/// rows, realism_state snapshots, group blobs, and V2 card extensions) are
/// written as derivations and read as seeds via [StoryClock.fromLegacy] — the
/// single successor to the old per-consumer `resolveStartDayOfWeek` trick.
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

  // Owned state — the whole subsystem.
  DateTime _clock = StoryClock.representativeTime(
    StoryClock.todayAnchor(),
    'morning',
  );
  DateTime _startDate = StoryClock.todayAnchor();
  bool _passageOfTimeEnabled = true;
  int _turnsSinceClockMoved = 0; // stall backstop counter (not a pacing gate)
  // One clock authority per turn: set when detectOocTimeSkip moves the clock,
  // consumed by the per-turn eval so it can't re-count the same exchange.
  bool _oocSkipMovedClockThisTurn = false;

  // Tools transport for the scene-time/posture eval (nullable — tests and
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
    this.fireToolEval,
    this.probe,
    this.getBackendIdentity,
  });

  // ── Public surface ────────────────────────────────────────────────────────

  DateTime get clock => _clock;
  DateTime get startDate => _startDate;
  String get timeOfDay => StoryClock.periodForHour(_clock.hour);
  int get dayCount => StoryClock.dayCountFor(_clock, _startDate);
  bool get passageOfTimeEnabled => _passageOfTimeEnabled;
  String get narrativeWeekday => StoryClock.weekdayName(_clock);

  /// Derived legacy anchor — still written to the session row / snapshots so
  /// external readers (Character Card Forge, older apps via The Stoop) keep
  /// seeing a consistent value.
  int get startDayOfWeekAnchor => _startDate.weekday;

  String get storyClockIso => StoryClock.serializeClock(_clock);
  String get storyStartDateIso => StoryClock.serializeDate(_startDate);

  /// "9:40 PM" / "Tue, Mar 3" / "Tuesday, March 3rd(, 1887)" for the UI.
  String get displayClock => StoryClock.formatClock(_clock);
  String get displayShortDate => StoryClock.formatShortDate(_clock);
  String get displayDate =>
      StoryClock.formatDate(_clock, realYear: StoryClock.todayAnchor().year);

  /// Fire one scene-time/posture eval through the shared tools-vs-text
  /// negotiation (or straight text when the tools door isn't wired).
  Future<String?> _fireSceneTimeEval(
    String Function({required bool toolsMode}) buildPrompt, {
    required Future<String?> Function(
      String prompt, {
      void Function(String)? onChunk,
    })
    fireLLMEval,
    void Function(String)? onChunk,
  }) => fireToolEval != null && probe != null
      ? fireStructuredEval(
          probe: probe!,
          backendIdentity: getBackendIdentity?.call() ?? '',
          debugLabel: kSceneTimeTool,
          tools: kSceneTimeEvalTools,
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
  }

  /// Load from a session row. Canonical columns win; legacy rows synthesize
  /// so the displayed weekday never jumps across the upgrade.
  void loadTimeScalars({
    required String timeOfDay,
    required int dayCount,
    required int startDayOfWeek,
    required bool passageOfTimeEnabled,
    String? storyClock,
    String? storyStartDate,
  }) {
    final clock = StoryClock.parse(storyClock);
    final anchor = StoryClock.parse(storyStartDate);
    if (clock != null && anchor != null) {
      _clock = clock;
      _startDate = StoryClock.dateOnly(anchor);
    } else {
      final legacy = StoryClock.fromLegacy(
        timeOfDay: timeOfDay,
        dayCount: dayCount,
        startDayOfWeek: startDayOfWeek,
        today: StoryClock.todayAnchor(),
      );
      _clock = clock ?? legacy.clock;
      _startDate = anchor != null
          ? StoryClock.dateOnly(anchor)
          : legacy.startDate;
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
    final dc = state['dayCount'] as int?;
    if (tod == null && dc == null) return;
    final legacy = StoryClock.fromLegacy(
      timeOfDay: tod ?? timeOfDay,
      dayCount: dc ?? dayCount,
      startDayOfWeek: state['startDayOfWeek'] as int? ?? 0,
      today: StoryClock.todayAnchor(),
    );
    _clock = legacy.clock;
    _startDate = anchor != null
        ? StoryClock.dateOnly(anchor)
        : legacy.startDate;
  }

  // ── Manual control (chevrons + calendar dialog) ───────────────────────────

  /// Sidebar chevrons: snap to the previous/next period's representative
  /// time. delta = +1 (forward) or -1 (back). Signals god to patch the last
  /// msg realism_state so swipe/regen cannot revert it.
  void nudgeTimePeriod(int delta) {
    _clock = delta >= 0
        ? StoryClock.snapToNextPeriod(_clock)
        : StoryClock.snapToPreviousPeriod(_clock);
    if (_clock.isBefore(_startDate)) _startDate = StoryClock.dateOnly(_clock);
    _turnsSinceClockMoved = 0;
    onPatchLastMessageRealismState(timeOfDay, dayCount, storyClockIso);
  }

  /// Calendar dialog: set the story's current moment directly. Pulls the
  /// anchor back when the new moment predates Day 1 (the story now starts
  /// earlier). Same swipe-survival patch as a nudge.
  void setClockDirect(DateTime newClock) {
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
  void detectOocTimeSkip(String text) {
    if (!_passageOfTimeEnabled) {
      debugPrint(
        '[Realism:OOC] Time-skip requested but passageOfTimeEnabled=false, ignoring',
      );
      return;
    }

    final lower = text.toLowerCase();

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
  }

  // ── Per-turn time advance (delegated from the physical / one-shot evals) ──

  /// Apply one turn's elapsed time. [minutes] null means the eval failed —
  /// deterministic drift applies. Returns whether the clock moved.
  bool _applyElapsed({required int? minutes, required bool newDay}) {
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
    return moved;
  }

  static int? _extractMinutes(String text) {
    final m = RegExp(r'"minutes_elapsed"\s*:\s*"?(-?\d+)').firstMatch(text);
    return m == null ? null : int.tryParse(m.group(1)!);
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

  /// Per-turn scene-time + posture evaluation (design §2). In the multi-call
  /// path this fires ONE eval per turn asking minutes_elapsed / new_day /
  /// posture — the same call that previously carried posture alone on
  /// non-eligible turns. In oneShotMode the fused one-shot JSON (passed as
  /// [oneShotText]) already carries all three fields, so no call fires here;
  /// this method only applies the clock math (strict one-shot parity: same
  /// clamp, floor, and backstop against the same clock).
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
  }) async {
    final emotionCtx = getCharacterEmotion().isNotEmpty
        ? '$charName is currently feeling ${getCharacterEmotion()} (${getEmotionIntensity()}). '
        : '';
    final postureCtx = getCurrentSpatialStance().isNotEmpty
        ? 'Recent position reference: $charName was "${getCurrentSpatialStance()}". '
        : '';

    if (!_passageOfTimeEnabled) {
      if (oneShotMode) return; // posture already set from the fused JSON
      // Passage disabled — posture only, time untouched.
      String buildPosturePrompt({required bool toolsMode}) =>
          '$emotionCtx$postureCtx'
          'Current time: $displayClock.\n\n'
          'What is $charName\'s current physical position and stance? Use "none" if unclear.\n'
          '- Match the posture to the current scene context and emotional state.\n'
          '- Within the same scene, maintain natural continuity (don\'t jump locations).\n'
          '- Across scene breaks or time jumps, update to the new context.\n\n'
          'Recent conversation:\n$recent\n\n'
          '${toolsMode ? 'Report by calling the $kSceneTimeTool tool (only the "posture" field matters here). Use ONLY the tool — no plain-text reply.' : 'Respond with ONLY valid JSON. Do NOT use markdown code blocks — return raw JSON only.\n'
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
          final postureMatch = RegExp(
            r'"posture"\s*:\s*"([^"]+)"',
          ).firstMatch(text);
          if (postureMatch != null) {
            setSpatialStance(postureMatch.group(1)!.trim());
          }
        }
      } catch (_) {}
      debugPrint(
        '[Realism:Physical] Posture: ${getCurrentSpatialStance()} | Time: $displayClock (Day $dayCount) | Passage of time: disabled',
      );
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
    // Posture still evaluates; no minutes, no new_day, no failure drift.
    final skipOwnsClock = _oocSkipMovedClockThisTurn;
    _oocSkipMovedClockThisTurn = false;

    if (oneShotMode) {
      // The fused JSON already carries minutes_elapsed/new_day (and posture,
      // parsed by the one-shot applier). Clock math only — no LLM call.
      if (skipOwnsClock) {
        debugPrint(
          '[Realism:Time] OOC skip owns this turn — one-shot clock '
          'movement suppressed',
        );
        return;
      }
      final text = oneShotText ?? '';
      final saidNewDay = extractJsonBool(text, 'new_day') ?? false;
      if (saidNewDay && !newDayCorroborated) logSuppressedNewDay();
      _applyElapsed(
        minutes: _extractMinutes(text),
        newDay: saidNewDay && newDayCorroborated,
      );
      debugPrint(
        '[Realism:Time] One-shot elapsed applied → $displayClock (Day $dayCount)',
      );
      return;
    }

    String buildPrompt({required bool toolsMode}) =>
        'You are evaluating scene time and physical state for $charName.\n\n'
        '$emotionCtx$postureCtx'
        'Relationship tension: $shortTermTierName.\n'
        'Current story time: $displayClock on $narrativeWeekday, Day $dayCount.\n\n'
        '1. "minutes_elapsed": how many in-story minutes passed during the LATEST exchange below (integer, 0-${StoryClock.maxMinutesPerTurn}). '
        'Most conversational exchanges take 2-15 minutes; activities (a meal, a walk, a task, travel) take longer. '
        'Use 0 ONLY when the scene is a continuous instant (mid-action, mid-sentence).\n'
        '2. "new_day": true ONLY if the conversation explicitly transitioned to the next day (slept, woke up, scene break). false otherwise. '
        'Merely MENTIONING yesterday, tomorrow, or another day does NOT count — the characters must actually cross a night.\n'
        '3. "posture": $charName\'s current physical position and location (brief grounded phrase). Use "none" if unclear.\n'
        '   - If the scene/location has changed (new setting, time passed, scene break), update to match the new context.\n'
        '   - Maintain continuity only within the SAME scene — do NOT anchor them to a position from a previous scene.\n\n'
        'Recent conversation:\n$recent\n\n'
        '${toolsMode ? 'Report by calling the $kSceneTimeTool tool with "minutes_elapsed", "new_day", and "posture". Use ONLY the tool — no plain-text reply.' : 'Respond with ONLY a flat JSON object containing "minutes_elapsed", "new_day", and "posture". '
                  'Do NOT use markdown code blocks — return raw JSON only.'}';

    try {
      final raw = await _fireSceneTimeEval(
        buildPrompt,
        fireLLMEval: fireLLMEval,
        onChunk: onChunk,
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
        final postureMatch = RegExp(
          r'"posture"\s*:\s*"([^"]+)"',
        ).firstMatch(text);
        if (postureMatch != null) {
          setSpatialStance(postureMatch.group(1)!.trim());
        }
      } else if (!skipOwnsClock) {
        _applyElapsed(minutes: null, newDay: false);
      }
    } catch (e) {
      // Eval failed — deterministic drift so time never freezes (unless the
      // OOC skip already moved this turn's clock).
      if (!skipOwnsClock) _applyElapsed(minutes: null, newDay: false);
      debugPrint('[Realism:Time] Eval error, drifted to $displayClock: $e');
    }

    debugPrint(
      '[Realism:Physical] Posture: ${getCurrentSpatialStance()} | Time: $displayClock $displayShortDate (Day $dayCount)',
    );
  }
}
