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

int? _extractMinutes(String text) {
  final m = RegExp(r'"minutes_elapsed"\s*:\s*"?(-?\d+)').firstMatch(text);
  return m == null ? null : int.tryParse(m.group(1)!);
}

/// LLM minutes decide + the posture-only post-gen pass.
extension TimeServiceEval on TimeService {
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
          toolChoice: kSceneTimeTool,
          fireTextEval: fireLLMEval,
          onChunk: onChunk,
        )
      : fireLLMEval(buildPrompt(toolsMode: false), onChunk: onChunk);

  Future<void> _maybeApplyTodayEval(String text) async {
    if (!(getPlannerEnabled?.call() ?? false)) return;
    final parsed = TodayLineTag.parseEvalSentence(text);
    if (parsed != null) await onTodayEval?.call(parsed);
  }

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
  /// establishes IN their reply — they cross the room and sit on the
  /// windowsill — could not possibly be seen by a judge that ran before that
  /// reply existed, and the next turn's pre-generation judge simply
  /// re-derived a fresh guess and overwrote it. The prompt then asserted the
  /// stale position as fact. Maintainer ruling, verbatim: "spatial awareness
  /// check should run post character message, otherwise how could it check
  /// where they moved or what they are doing".
  ///
  /// So posture is now exactly the kind of fact Pockets and Afterglow are —
  /// something the REPLY changed — and it runs where they run, reading the
  /// text that was just written (chat_service_generation_postgen.dart).
  /// TIME now moves AFTER the reply, same family as posture: the prompt
  /// already announced the current clock, they wrote at that time, and this
  /// call decides what the NEXT speaker will be told. Pre-gen application
  /// made At work / Today lie (the strip jumped before they opened their mouth).
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
  Future<void> _evaluateTimeProgressAndPostureIfNeeded({
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
  }) async {
    // Realism context, and therefore skipped entirely in timeOnly mode.
    final emotionCtx = !timeOnly && getCharacterEmotion().isNotEmpty
        ? '$charName is currently feeling ${getCharacterEmotion()} (${getEmotionIntensity()}). '
        : '';
    final postureCtx = !timeOnly && getCurrentSpatialStance().isNotEmpty
        ? 'Recent position reference: $charName was "${getCurrentSpatialStance()}". '
        : '';

    if (postureOnly) {
      // Where they ended up. [recent] here is the window AFTER the reply was
      // appended, so the exchange this reads is the one the character just
      // wrote — the whole reason the pass moved. Deliberately NOT gated on
      // _passageOfTimeEnabled: a frozen clock does not freeze a room.
      String buildPosturePrompt({required bool toolsMode}) =>
          '${TimeService.postureQuestion(charName: charName, emotionCtx: emotionCtx, postureCtx: postureCtx, displayClock: displayClock)}'
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
          final posture = TimeService.parsePosture(text);
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
        if (!skipTodayEval) await _maybeApplyTodayEval(text);
        return;
      }
      final saidNewDay = extractJsonBool(text, 'new_day') ?? false;
      if (saidNewDay && !newDayCorroborated) logSuppressedNewDay();
      await _applyElapsed(
        minutes: _extractMinutes(text),
        newDay: saidNewDay && newDayCorroborated,
      );
      if (!skipTodayEval) await _maybeApplyTodayEval(text);
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
        '1. "minutes_elapsed": how many in-story minutes passed during the reply that was JUST written (integer, 0-${StoryClock.maxMinutesPerTurn}). '
        'This sets the clock the NEXT speaker will be told. '
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
          await _applyElapsed(
            minutes: _extractMinutes(text),
            newDay: saidNewDay && newDayCorroborated,
          );
        }
        if (!skipTodayEval) await _maybeApplyTodayEval(text);
      } else if (!skipOwnsClock) {
        await _applyElapsed(minutes: null, newDay: false);
      }
    } catch (e) {
      // Eval failed — deterministic drift so time never freezes (unless the
      // OOC skip already moved this turn's clock).
      if (!skipOwnsClock) {
        await _applyElapsed(minutes: null, newDay: false);
      }
      debugPrint('[Realism:Time] Eval error, drifted to $displayClock: $e');
    }

    debugPrint(
      '${timeOnly ? '[Clock:Standalone]' : '[Realism:Time]'} '
      'Time: $displayClock $displayShortDate (Day $dayCount)',
    );
  }
}
