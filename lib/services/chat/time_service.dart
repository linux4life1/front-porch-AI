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
import 'package:front_porch_ai/services/llm_service.dart' show LlmToolResponse;

/// Plain (non-ChangeNotifier) domain service owning the chat-scoped passage-of-time
/// state machine: deterministic 6-turn clock, automatic LLM-vetoable advances
/// (hold_time / new_day / posture side-effect), manual nudge (chevrons), OOC
/// time-skip detection/language parsing, legacy startDayOfWeek resolution,
/// narrative weekday computation, and all reset/seed/load/restore helpers.
///
/// ChatService owns the instance via a private late final (declared after the
/// other leaf services per plan) and delegates. Cross-state (pendingRealismMetadata
/// for OOC/nudge delta chips, last-message realism_state snapshot patching for
/// nudge survival across swipe/regen/reload, save/notify) is accessed exclusively
/// via 4 granular callbacks supplied at construction. This keeps the extracted
/// service testable, avoids cycles with realism_state / pending / messages, and
/// is friendly to future extractions (prompt builders in step 8, etc.).
/// (Granular callbacks chosen over a full parent interface ref for this leaf
/// extraction per the Stage 3 precedent in needs/chaos/relationship/expression
/// and updated plan guidance in docs/refactoring-guide.md.)
///
/// Time is *chat-scoped* (shared across group members, not per-speaker like
/// relationship/needs scalars). Group vs 1:1 parity is preserved: owner swaps
/// the active speaker via _loadGroupRealismIntoScalars / impersonation before
/// evals (time clock/advance sees the impersonated charName for prompts only;
/// the _timeOfDay/_dayCount/_turns scalars are single per-chat). No per-speaker
/// time storage existed originally.
///
/// Boundaries kept in god (per plan for step 5 / step 8):
/// - Full time injection text builder is thin wrapper here (_getTimeInjection
///   remains in ChatService for now; the real prompt_* builders move in step 8).
/// - OOC feeding realism cross (pending metadata stamp) is manual via cb +
///   integrations (no auto cross in leaf).
/// - UI coordination for nudge chevrons (the public nudge entry + save/notify)
///   stays thin in god.
/// - Pre-turn time advance (the LLM hold eval inside physical) is delegated
///   via evaluateTimeProgressAndPostureIfNeeded (called from existing
///   _evaluatePhysicalStateCall, and from the one-shot eval with
///   oneShotMode: true — clock tick + hold/new_day eval only, posture rides
///   the fused JSON; this keeps the One-shot vs Normal Path Parity contract
///   for time deltas, which the old posture-only bypass silently broke by
///   never ticking the clock).
/// - Capture/restore sites, drift save sites, and the ~10 "keep reset blocks
///   in sync" sites call service helpers (reset/seed/load/restore) + tightened
///   comments now list /time alongside needs/chaos/relationship/expression.
///
/// @Deprecated shims on ChatService (exactly 5): timeOfDay, dayCount,
/// passageOfTimeEnabled, narrativeWeekday, setPassageOfTimeEnabled.
///
/// 0 new private methods added to ChatService as part of this step (thins +
/// delegations + call-site updates only; deletions of moved code are mandatory
/// part of the task). Reset helpers on service support the documented keep-sync
/// sites without god privates or duplication.
///
/// time injection only thin wrapper here; full builders in step 8.
/// OOC feeding realism cross only manual + integrations.
/// aug exercising only passive/qualified (resets hit by pre-existing startNew/setActive etc).
/// oneShot vs normal time parity: both paths tick the clock and run the
/// hold/new_day eval when an advance is due (oneShotMode skips only the
/// posture-only calls — posture rides the fused one-shot JSON).
class TimeService {
  final VoidCallback onNotify;
  final Future<void> Function() onSaveChat;

  // Granular cbs for cross-state side effects without cycles or owning god state.
  // onSetPendingRealismMetadata: used by OOC detect (and nudge survival path) to
  // stamp 'time_skip_to' / 'time_nudged' into _pendingRealismMetadata for delta rows.
  // onNudgePatchLastMessageRealismState: signals that time state changed via manual
  // nudge; god receives the fresh (tod, day) and closes over _messages + _capture
  // to patch the last msg's realism_state snapshot (swipe/regen survival).
  // Values passed at call time to avoid textual self-ref in late final initializer.
  final void Function(String key, dynamic value) onSetPendingRealismMetadata;
  final void Function(String timeOfDay, int dayCount)
  onNudgePatchLastMessageRealismState;

  // Owned state (moved verbatim from ChatService).
  String _timeOfDay = 'morning';
  int _dayCount = 1;
  int _startDayOfWeek =
      DateTime.now().weekday; // 1=Mon ... 7=Sun, set when session starts
  int _turnsSinceLastTimeAdvance = 0; // deterministic pacing counter
  bool _passageOfTimeEnabled = true; // toggle for automatic time advancement

  /// How many AI turns must pass before time is eligible to advance.
  /// 6 turns ≈ a meaningful scene chunk without forcing constant time-skips.
  static const int turnsPerTimePeriod = 6;

  // Tools transport for the scene-time/posture evals (nullable — tests and
  // any host without the tools door stay on the text path; the god wires the
  // same shared probe/door the other structured evals use).
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
    required this.onNudgePatchLastMessageRealismState,
    this.fireToolEval,
    this.probe,
    this.getBackendIdentity,
  });

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

  // ── Public surface (for @Deprecated shims in ChatService + direct test/UI callers) ──────

  String get timeOfDay => _timeOfDay;
  int get dayCount => _dayCount;
  bool get passageOfTimeEnabled => _passageOfTimeEnabled;

  /// The current narrative day of the week (e.g. 'Monday'), computed from
  /// the session's anchor weekday plus elapsed in-story days.
  String get narrativeWeekday {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final idx = (_startDayOfWeek - 1 + (_dayCount - 1)) % 7;
    return days[idx];
  }

  /// Internal anchor (persisted); exposed for captureRealismState snapshot only.
  /// Not part of the public @Dep surface.
  int get startDayOfWeekAnchor => _startDayOfWeek;

  /// Anchor the narrative weekday to the real-world day when realism first turns on for this session
  /// (only if not already anchored). Called from god's setRealismEnabled (keeps the toggle logic
  /// thin; no new god private).
  void ensureStartDayOfWeekAnchored() {
    if (_startDayOfWeek < 1 || _startDayOfWeek > 7) {
      _startDayOfWeek = DateTime.now().weekday;
    }
  }

  /// Resolves the persisted startDayOfWeek (1-7) or computes a stable anchor for legacy rows (0).
  /// For legacy sessions the computed anchor makes the *current* Day N display the real-world
  /// weekday of the moment we first load it after the v28 migration. This keeps the narrative
  /// weekday from jumping on the very next app restart and makes the transition seamless.
  int resolveStartDayOfWeek(int persisted, int currentDayCount) {
    if (persisted >= 1 && persisted <= 7) return persisted;

    // Legacy or unset (0): anchor so that narrative weekday for the loaded dayCount matches "today".
    // Formula: start = ((today-1 - (dayCount-1)) mod 7) + 1
    final today = DateTime.now().weekday;
    final delta = currentDayCount - 1;
    final start = ((today - 1 - delta) % 7 + 7) % 7 + 1;
    debugPrint(
      '[TimeService] Legacy/ unset startDayOfWeek resolved: persisted=$persisted, dayCount=$currentDayCount '
      '→ start=$start (so Day $currentDayCount will show weekday of today=$today)',
    );
    return start;
  }

  // ── Mutation for control / loads (side-effect free; wrapper in ChatService does save/notify) ──

  void setPassageOfTimeEnabled(bool enabled) {
    _passageOfTimeEnabled = enabled;
  }

  // Direct scalar sets / load helpers for the documented "keep reset blocks in sync" sites
  // (startNewChat, setActiveCharacter, setActiveGroup, _loadLastSession, ext-seed paths,
  // delete flows, empty session, etc.). Callers apply global ceiling on passage before passing.
  void resetForFreshChat() {
    _dayCount = 1;
    _timeOfDay = 'morning';
    _startDayOfWeek = DateTime.now().weekday;
    _turnsSinceLastTimeAdvance = 0;
    _passageOfTimeEnabled = true;
  }

  void seedFromV2OrExt({
    required int dayCount,
    required String timeOfDay,
    required bool passageOfTimeEnabled,
  }) {
    _dayCount = dayCount.clamp(1, 9999);
    _timeOfDay = timeOfDay;
    _startDayOfWeek = DateTime.now()
        .weekday; // anchor narrative weekday for the fresh session
    _passageOfTimeEnabled = passageOfTimeEnabled;
    _turnsSinceLastTimeAdvance = 0;
  }

  void loadTimeScalars({
    required String timeOfDay,
    required int dayCount,
    required int startDayOfWeek,
    required bool passageOfTimeEnabled,
  }) {
    _timeOfDay = timeOfDay;
    _dayCount = dayCount;
    _startDayOfWeek = resolveStartDayOfWeek(startDayOfWeek, dayCount);
    _passageOfTimeEnabled = passageOfTimeEnabled;
    // turns left as-is or 0 on fresh; loads preserve pacing from persisted state
  }

  // For swipe/regen paths that restore prior realism_state (respect nudge flag).
  void restoreTimeForSwipeOrRegen(
    Map<String, dynamic> previousState, {
    bool wasNudged = false,
  }) {
    if (_passageOfTimeEnabled && !wasNudged) {
      _timeOfDay = previousState['timeOfDay'] as String? ?? _timeOfDay;
      _dayCount = previousState['dayCount'] as int? ?? _dayCount;
    }
  }

  // For _restoreRealismStateFromMessage + 1:1<->group conversion carry.
  void restoreTimeFromRealismState(Map<String, dynamic> state) {
    // Restore the scene time REGARDLESS of passage-of-time. A fixed time-of-day
    // (e.g. "evening, Day 1") is meaningful even with auto-advance OFF, and must
    // survive 1:1<->group conversion + per-speaker state replay. The old
    // `if (_passageOfTimeEnabled)` gate — combined with the carry restoring time
    // BEFORE the passage flag is re-applied — reset a fixed time to the morning/
    // Day 1 default on conversion. (Auto-advance is a separate behavior; not
    // restoring here never advances time, it only kept the stale default.)
    _timeOfDay = state['timeOfDay'] as String? ?? _timeOfDay;
    _dayCount = state['dayCount'] as int? ?? _dayCount;
    _startDayOfWeek = state['startDayOfWeek'] as int? ?? _startDayOfWeek;
  }

  // ── Nudge (manual chevron) ────────────────────────────────────────────────

  /// Called by the sidebar chevron buttons (via thin god wrapper that does the
  /// realism guard + save/notify). delta = +1 (forward) or -1 (back).
  /// Mutates time state and signals god (via ctor cb) to patch the last msg
  /// realism_state so that _restoreRealismStateFromMessage / swipe cannot revert it.
  void nudgeTimePeriod(int delta) {
    final validTimes = [
      'dawn',
      'morning',
      'late_morning',
      'afternoon',
      'evening',
      'night',
    ];
    int idx = validTimes.indexOf(_timeOfDay);
    int next = idx + delta;
    if (next < 0) {
      next = validTimes.length - 1;
      _dayCount = (_dayCount - 1).clamp(1, 9999);
    } else if (next >= validTimes.length) {
      next = 0;
      _dayCount++;
    }
    _timeOfDay = validTimes[next];
    _turnsSinceLastTimeAdvance = 0; // reset clock after manual nudge

    onNudgePatchLastMessageRealismState(_timeOfDay, _dayCount);
  }

  /// Advance the clock by [count] time periods (skip LLM eval).
  /// Used during AFK auto-response mode to simulate hours passing.
  /// Respects the passageOfTimeEnabled toggle. Rolls over days naturally.
  void advanceTimePeriods(int count) {
    if (!_passageOfTimeEnabled) return;
    if (count <= 0) return;

    const validTimes = [
      'dawn', 'morning', 'late_morning', 'afternoon', 'evening', 'night',
    ];
    int idx = validTimes.indexOf(_timeOfDay);
    for (int i = 0; i < count; i++) {
      idx++;
      if (idx >= validTimes.length) {
        idx = 0;
        _dayCount++;
      }
    }
    _timeOfDay = validTimes[idx];
    _turnsSinceLastTimeAdvance = 0;
  }

  // ── OOC Time-Skip Detector ────────────────────────────────────────────────

  /// Scans the user message for OOC/narrative time-skip language and advances
  /// the clock by the inferred number of periods. Stamps the skip into
  /// pending via cb (god wires to _pendingRealismMetadata) so it appears in
  /// the next AI message's delta row.
  ///
  /// NOTE: Respects the global passageOfTimeEnabled setting. If disabled,
  /// this function does nothing even if OOC markers are present.
  ///
  /// time injection only thin wrapper here; full in step8.
  /// OOC feeding realism cross only manual + integrations.
  void detectOocTimeSkip(String text) {
    // Respect global passage of time setting
    if (!_passageOfTimeEnabled) {
      debugPrint(
        '[Realism:OOC] Time-skip requested but passageOfTimeEnabled=false, ignoring',
      );
      return;
    }

    final lower = text.toLowerCase();

    // Only fire on OOC-style markers or explicit timeskip language
    final hasOocMarker = RegExp(
      r'\(ooc[:\s]|\[ooc|\*ooc\b|ooc:',
    ).hasMatch(lower);
    final hasSkipPhrase = RegExp(
      r'\b(time.?skip|fast.?forward|skip ahead|several hours|a few hours|hours? later|'
      r'the next (morning|day|evening|afternoon|night|dawn)|'
      r'next (morning|day|evening|afternoon|night|dawn)|'
      r'hours? pass|time passes|the following (morning|day)|'
      r'wake up the next|woke up|the next day)\b',
    ).hasMatch(lower);

    if (!hasOocMarker && !hasSkipPhrase) return;

    // Estimate period count from duration language
    int periods = 1;

    if (RegExp(
      r'\b(all day|entire day|full day|day passes|the (whole|entire) day)\b',
    ).hasMatch(lower)) {
      periods = 4;
    } else if (RegExp(
      r'\b(next (morning|day)|the following (morning|day)|wake up|woke up|overnight)\b',
    ).hasMatch(lower)) {
      _dayCount++;
      _timeOfDay = 'dawn';
      _turnsSinceLastTimeAdvance = 0;
      onSetPendingRealismMetadata('time_skip_to', 'Dawn · Day $_dayCount');
      onNotify();
      debugPrint('[Realism:OOC] Next-day transition → Day $_dayCount, dawn');
      return;
    } else if (RegExp(
      r'\b(several hours|many hours|a long time|hours? pass)\b',
    ).hasMatch(lower)) {
      periods = 3;
    } else if (RegExp(
      r'\b(a few hours|couple.{0,5}hours|2.{0,5}hours|two hours)\b',
    ).hasMatch(lower)) {
      periods = 2;
    } else if (RegExp(
      r'\b(an hour|1 hour|one hour|a while|some time)\b',
    ).hasMatch(lower)) {
      periods = 1;
    } else if (hasOocMarker) {
      periods = 1;
    }

    if (periods <= 0) return;

    final validTimes = [
      'dawn',
      'morning',
      'late_morning',
      'afternoon',
      'evening',
      'night',
    ];
    int idx = validTimes.indexOf(_timeOfDay);
    for (int i = 0; i < periods; i++) {
      idx++;
      if (idx >= validTimes.length) {
        idx = 0;
        _dayCount++;
      }
    }
    _timeOfDay = validTimes[idx];
    _turnsSinceLastTimeAdvance = 0;
    onSetPendingRealismMetadata('time_skip_to', _displayTimeLabel(_timeOfDay));
    onNotify();
    debugPrint(
      '[Realism:OOC] Time-skip: +$periods period(s) → $_timeOfDay (Day $_dayCount)',
    );
  }

  String _displayTimeLabel(String raw) {
    return raw
        .split('_')
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  // ── Prompt injection (thin; full builders move in step 8) ─────────────────

  /// Returns the scene time injection block for the LLM prompt.
  /// Thin wrapper only — the authoritative prompt_* builders live in step 8
  /// prompt_injection/ subtree. Kept here so existing _getTimeInjection call
  /// sites (and regen paths) continue to work with zero behavior change.
  String buildTimeInjection() {
    final timeLabel = _timeOfDay.replaceAll('_', ' ');
    final cap =
        timeLabel.substring(0, 1).toUpperCase() + timeLabel.substring(1);
    // Compute narrative weekday from session start day + elapsed days
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final narrativeDayIndex = (_startDayOfWeek - 1 + (_dayCount - 1)) % 7;
    final weekdayName = days[narrativeDayIndex];
    return '[Scene Time: $cap, $weekdayName (Day $_dayCount)\n'
        ' Describe appropriate lighting, atmosphere, and environmental details.]\n';
  }

  // ── Pre-turn time advance (delegated from physical eval) ──────────────────

  /// Performs the deterministic time clock tick + (when eligible) the LLM
  /// "hold_time / new_day / posture" eval that can advance _timeOfDay / _dayCount.
  /// Also handles the non-eligible posture-only LLM path and the passage-disabled
  /// posture-only path (so the god physical method can thin to a single delegation
  /// point without new private methods).
  ///
  /// All LLM interaction, think stripping, JSON extraction, and spatial stance
  /// side effects go through the provided callbacks (no direct god field access).
  /// Verbatim logic from original _evaluatePhysicalStateCall time block.
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
  }) async {
    // oneShotMode: called from the fused one-shot eval, whose JSON already
    // carries posture — so the posture-only LLM paths are skipped and only the
    // deterministic clock tick + the advance-eligible hold/new_day eval run
    // (one extra call per [turnsPerTimePeriod] turns). Without this, one-shot
    // mode never ticked the clock at all and time froze forever — violating
    // the strict One-shot vs Normal Path Parity contract for Time.
    // ── Time-based evaluation (only if passage of time is enabled) ───────────
    if (!_passageOfTimeEnabled) {
      if (oneShotMode) return; // posture already set from the fused JSON
      // ── Passage of time disabled — only evaluate posture ───────────────────
      final currentPostureCtx = getCurrentSpatialStance().isNotEmpty
          ? 'Recent position reference: $charName was "${getCurrentSpatialStance()}". '
          : '';
      String buildPosturePrompt({required bool toolsMode}) =>
          '$currentPostureCtx'
          'Current time: $_timeOfDay.\n\n'
          'What is $charName\'s current physical position and stance? Use "none" if unclear.\n'
          '- Match the posture to the current scene context and emotional state.\n'
          '- If the conversation implies a location or activity change, update accordingly.\n'
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
          debugPrint(
            '[Realism:Physical] Posture-only match: ${postureMatch?.group(0)}',
          );
          if (postureMatch != null) {
            final p = postureMatch.group(1)!.trim();
            setSpatialStance(p);
          }
        }
      } catch (_) {}
      debugPrint(
        '[Realism:Physical] Posture: ${getCurrentSpatialStance()} | Time: $_timeOfDay (Day $_dayCount) | Passage of time: disabled',
      );
      return;
    }

    final validTimes = [
      'dawn',
      'morning',
      'late_morning',
      'afternoon',
      'evening',
      'night',
    ];
    final currentIndex = validTimes.indexOf(_timeOfDay);

    // ── Deterministic Time Clock ───────────────────────────────────────────
    // Increment every AI turn. Time only advances when the threshold is reached —
    // the LLM can only veto (hold) the advance, never skip multiple periods.
    _turnsSinceLastTimeAdvance++;
    final bool timeEligible = _turnsSinceLastTimeAdvance >= turnsPerTimePeriod;

    if (timeEligible) {
      final currentPostureCtx = getCurrentSpatialStance().isNotEmpty
          ? 'Recent position reference: $charName was "${getCurrentSpatialStance()}".\n'
          : '';
      String buildHoldPrompt({required bool toolsMode}) =>
          'You are evaluating physical state for $charName.\n\n'
          '$currentPostureCtx'
          'Current time: $_timeOfDay (Day $_dayCount). Time is advancing to the next period.\n'
          'Enough turns have passed that time should advance from "$_timeOfDay" to the next period.\n'
          '1. "hold_time": true ONLY if the scene is visibly mid-action (e.g. mid-fight, actively doing something). false otherwise — let time advance normally.\n'
          '2. "new_day": true ONLY if the conversation explicitly transitioned to the next day (slept, woke up, scene break). Only valid when current time is "night".\n'
          '3. "posture": $charName\'s current physical position and location (brief grounded phrase). Use "none" if unclear.\n'
          '   - If the scene/location has changed (new setting, time passed, scene break), update to match the new context.\n'
          '   - If time advanced significantly or a new day started, characters naturally shift positions.\n'
          '   - Maintain continuity only within the SAME scene — do NOT anchor them to a position from a previous scene.\n'
          '   - Avoid sudden jumps without setup, but DO update when the narrative context clearly shifted.\n\n'
          'Recent conversation:\n$recent\n\n'
          '${toolsMode ? 'Report by calling the $kSceneTimeTool tool with "hold_time", "new_day", and "posture". Use ONLY the tool — no plain-text reply.' : 'Respond with ONLY a flat JSON object containing "hold_time", "new_day", and "posture". '
                'Do NOT use markdown code blocks — return raw JSON only.'}';
      try {
        final raw = await _fireSceneTimeEval(
          buildHoldPrompt,
          fireLLMEval: fireLLMEval,
          onChunk: onChunk,
        );
        if (raw != null) {
          final text = stripThinkBlocks(raw).isNotEmpty
              ? stripThinkBlocks(raw)
              : raw;
          final shouldHold = extractJsonBool(text, 'hold_time') ?? false;

          if (!shouldHold) {
            if (currentIndex < validTimes.length - 1) {
              _timeOfDay = validTimes[currentIndex + 1];
            } else {
              _timeOfDay = validTimes[0];
              _dayCount++;
              debugPrint('[Realism:Time] Day rolled over! Day $_dayCount');
            }
            _turnsSinceLastTimeAdvance = 0;
            debugPrint(
              '[Realism:Time] Advanced to $_timeOfDay (Day $_dayCount)',
            );
          } else {
            debugPrint(
              '[Realism:Time] Held — scene mid-action, time stays at $_timeOfDay',
            );
          }

          // Explicit new-day override (e.g. woke up after night)
          final isNewDay = extractJsonBool(text, 'new_day') ?? false;
          if (isNewDay && _timeOfDay == 'night' && !shouldHold) {
            // already handled by rollover above
          } else if (isNewDay &&
              currentIndex >= validTimes.indexOf('evening')) {
            _dayCount++;
            _timeOfDay = validTimes[0];
            _turnsSinceLastTimeAdvance = 0;
            debugPrint(
              '[Realism:Time] Explicit new-day transition. Day $_dayCount',
            );
          }

          final postureMatch = RegExp(
            r'"posture"\s*:\s*"([^"]+)"',
          ).firstMatch(text);
          debugPrint(
            '[Realism:Physical] Posture match: ${postureMatch?.group(0)}',
          );
          if (postureMatch != null) {
            final p = postureMatch.group(1)!.trim();
            setSpatialStance(p);
          }
        }
      } catch (e) {
        // Eval failed — still advance so time never freezes
        if (currentIndex < validTimes.length - 1) {
          _timeOfDay = validTimes[currentIndex + 1];
        } else {
          _timeOfDay = validTimes[0];
          _dayCount++;
        }
        _turnsSinceLastTimeAdvance = 0;
        debugPrint(
          '[Realism:Time] Eval error, auto-advanced to $_timeOfDay: $e',
        );
      }
    } else if (oneShotMode) {
      // Not yet eligible — the fused one-shot JSON already set posture; the
      // clock tick above is all this turn needs. No extra LLM call.
    } else {
      // Not yet eligible — grab posture only
      final emotionCtx = getCharacterEmotion().isNotEmpty
          ? '$charName is currently feeling ${getCharacterEmotion()} (${getEmotionIntensity()}). '
          : '';
      final currentPostureCtx = getCurrentSpatialStance().isNotEmpty
          ? 'Recent position reference: $charName was "${getCurrentSpatialStance()}". '
          : '';
      final posturePrompt =
          '$emotionCtx${currentPostureCtx}Relationship tension: $shortTermTierName. Current time: $_timeOfDay.\n\n'
          'What is $charName\'s current physical position and stance? Use "none" if unclear.\n'
          '- Match the posture to the current scene context and emotional state.\n'
          '- If the conversation implies a location or activity change, update accordingly.\n'
          '- Within the same scene, maintain natural continuity (don\'t jump locations).\n'
          '- Across scene breaks or time jumps, update to the new context.\n\n'
          'Recent conversation:\n$recent\n\n'
          'Respond with ONLY valid JSON. Do NOT use markdown code blocks — return raw JSON only.\n'
          'Example: {"posture": "standing by the window"} or {"posture": "none"}';

      try {
        final raw = await fireLLMEval(posturePrompt, onChunk: onChunk);
        if (raw != null) {
          final text = stripThinkBlocks(raw).isNotEmpty
              ? stripThinkBlocks(raw)
              : raw;
          final postureMatch = RegExp(
            r'"posture"\s*:\s*"([^"]+)"',
          ).firstMatch(text);
          debugPrint(
            '[Realism:Physical] ELSE branch posture match: ${postureMatch?.group(0)}',
          );
          if (postureMatch != null) {
            final p = postureMatch.group(1)!.trim();
            setSpatialStance(p);
          }
        }
      } catch (_) {}
    }

    debugPrint(
      '[Realism:Physical] Posture: ${getCurrentSpatialStance()} | Time: $_timeOfDay (Day $_dayCount) | TurnsToNext: ${turnsPerTimePeriod - _turnsSinceLastTimeAdvance}',
    );
  }
}
