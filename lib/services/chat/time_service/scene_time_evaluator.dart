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
import 'package:front_porch_ai/services/chat/story_clock.dart';
import 'package:front_porch_ai/services/chat/time_service/reply_jump.dart';
import 'package:front_porch_ai/services/chat/time_service/time_clock_applier.dart';
import 'package:front_porch_ai/services/chat/time_service/time_clock_state.dart';
import 'package:front_porch_ai/services/chat/today_line_tag.dart';

int? _extractMinutes(String text) {
  final m = RegExp(r'"minutes_elapsed"\s*:\s*"?(-?\d+)').firstMatch(text);
  return m == null ? null : int.tryParse(m.group(1)!);
}

String? _extractScenePlace(String text) {
  final v = judgedStringField(text, 'scene_place')?.trim();
  if (v == null || v.isEmpty || v.toLowerCase() == 'same') return null;
  return v;
}

bool _extractContinuousInstant(
  String text,
  bool? Function(String, String) extractJsonBool,
) => extractJsonBool(text, 'continuous_instant') ?? false;

/// LLM minutes decide + the posture-only post-gen pass.
class SceneTimeEvaluator {
  SceneTimeEvaluator({
    required this.state,
    required this.applier,
    required this.isPassageOfTimeEnabled,
    required this.getClockGateSource,
    this.getPorchLifePassageOfTime,
    this.getPlannerEnabled,
    this.onTodayEval,
    this.fireToolEval,
    this.probe,
    this.getBackendIdentity,
    this.getScenePlaceOffer,
    this.onScenePlace,
    this.onNewPlace,
  });

  final TimeClockState state;
  final TimeClockApplier applier;
  final bool Function() isPassageOfTimeEnabled;
  final String Function() getClockGateSource;
  final bool Function()? getPorchLifePassageOfTime;
  final bool Function()? getPlannerEnabled;
  final FutureOr<void> Function(String line)? onTodayEval;
  final Object? fireToolEval;
  final ToolTransportProbe? probe;
  final String Function()? getBackendIdentity;

  /// Slice 6: the places a suggested scene move may name THIS turn —
  /// [id] for the wire, [label] for the prompt. Null/empty when the
  /// Scene suggestions switch is off, the Setting has no relatives, or
  /// the turn belongs to Director/AFK play; when empty the prompt never
  /// asks and `scene_place` is inert. Served from the ONE reach law
  /// (`world_chain.reachablePlaces`) — this file never re-decides.
  final List<({String id, String label})>? Function()? getScenePlaceOffer;

  /// Called with the offered place id when the judge reports an arrival
  /// there. The evaluator NEVER moves the scene or touches the clock
  /// slots (design: the service only flags; the user confirms).
  final void Function(String id)? onScenePlace;

  /// Slice 7: the scene_place == "new" flag — a NAMED place the reply
  /// arrived at that is not in the library. (name, one-line descriptor)
  /// out to the mint dialog; nothing mints here.
  final void Function(String name, String descriptor)? onNewPlace;

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
  /// step. It ignores [isPassageOfTimeEnabled] entirely: where a character is
  /// standing has nothing to do with whether the story clock ticks.
  ///
  /// In oneShotMode the fused one-shot JSON (passed as [oneShotText]) carries
  /// minutes_elapsed/new_day, so no call fires here; this method only applies
  /// the clock math (strict one-shot parity: same clamp, floor, and backstop
  /// against the same clock). One-shot no longer carries posture either — it
  /// is a PRE-generation optimisation and posture is no longer a
  /// pre-generation question.
  ///
  /// [timeOnly] drops scene framing (mood, stance, tension) when the
  /// Realism Engine is off. Everything AFTER the eval is shared:
  /// [_extractMinutes], [newDayCorroboration], [TimeClockApplier.applyElapsed].
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
    bool sceneMovesAllowed = true,
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
          '${SceneTimeEvaluator.postureQuestion(charName: charName, emotionCtx: emotionCtx, postureCtx: postureCtx, displayClock: state.displayClock)}'
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
          final posture = SceneTimeEvaluator.parsePosture(text);
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
    if (!isPassageOfTimeEnabled()) {
      debugPrint(
        '[Clock] running=false source=${getClockGateSource()} '
        'porchLife=${getPorchLifePassageOfTime?.call()} '
        'reason=porch_life_off',
      );
      return;
    }
    if (skipClockAdvance) {
      debugPrint('[Realism:Time] follow-up speaker — clock already moved');
      return;
    }

    final newDayCorroborated = newDayCorroboration.hasMatch(recent);

    // Snapshot the offer ONCE per call: the ids the model may answer
    // with are exactly the ids that were in front of it. A Setting that
    // changes mid-call can never validate against a stale list.
    final sceneOffer = (sceneMovesAllowed && !postureOnly)
        ? getScenePlaceOffer?.call()
        : null;
    final scenePlaceOn = sceneOffer != null && sceneOffer.isNotEmpty;
    void maybeOfferSceneMove(String text) {
      if (!scenePlaceOn) return;
      final said = _extractScenePlace(text);
      if (said == null) return;
      if (said.toLowerCase() == 'new') {
        // Slice 7: only a NAMED arrival qualifies; the pair rides out
        // to the mint dialog, which is where the tap happens.
        final name = judgedStringField(text, 'new_place_name')?.trim() ?? '';
        final desc =
            judgedStringField(text, 'new_place_descriptor')?.trim() ?? '';
        if (name.isEmpty) {
          debugPrint(
            '[Realism:Scene] scene_place "new" without a name — ignored '
            '(unnamed side streets never qualify)',
          );
          return;
        }
        onNewPlace?.call(name, desc);
        return;
      }
      if (onScenePlace == null) return;
      for (final p in sceneOffer) {
        if (p.id.toLowerCase() == said.toLowerCase()) {
          onScenePlace!(p.id);
          return;
        }
      }
      // A name that is not an offered id is exactly a hallucinated move:
      // same treatment as absent. Logged for the smoke to grep.
      debugPrint(
        '[Realism:Scene] scene_place "$said" is not an offered id — ignored',
      );
    }

    void logSuppressedNewDay() => debugPrint(
      '[Realism:Time] new_day=true suppressed — no sleep/wake language '
      'in the recent exchange (hallucination guard)',
    );

    // A jump of hours or days the reply narrates is lived off-screen, like
    // a skip; a night the judge also called wakes the bodies rested.
    // Otherwise the clamped minutes.
    Future<void> applyVerdict(String text) async {
      final saidNewDay = extractJsonBool(text, 'new_day') ?? false;
      final jump = ReplyJump.read(text, recent);
      if (jump != null) {
        await applier.applyReplyJump(
          jump,
          slept: saidNewDay && newDayCorroborated,
        );
        // This eval was the turn's one clock authority; nothing to hand on.
        state.oocSkipMovedClockThisTurn = false;
        maybeOfferSceneMove(text);
        return;
      }
      if (saidNewDay && !newDayCorroborated) logSuppressedNewDay();
      await applier.applyElapsed(
        minutes: _extractMinutes(text),
        newDay: saidNewDay && newDayCorroborated,
        continuousInstant: _extractContinuousInstant(text, extractJsonBool),
      );
      maybeOfferSceneMove(text);
    }

    // One clock authority per turn (chip/clock parity): when an OOC or
    // narrative skip already moved the clock for this exchange, this eval
    // must not count the same exchange again — the double-advance is how a
    // "Time skip: 11:50 PM" chip ended up under a 1:05 AM sidebar clock.
    // The flag suppresses minutes, new_day and the failure drift — nothing
    // else. (It used to add "posture still evaluates", which stopped being
    // true when posture left this call for its own post-generation pass
    // above; a skipped turn's position now comes from that pass, which never
    // reaches this branch.)
    final skipOwnsClock = state.oocSkipMovedClockThisTurn;
    state.oocSkipMovedClockThisTurn = false;

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
      await applyVerdict(text);
      if (!skipTodayEval) await _maybeApplyTodayEval(text);
      debugPrint(
        '[Realism:Time] One-shot elapsed applied → ${state.displayClock} (Day ${state.dayCount})',
      );
      return;
    }

    // One minutes_elapsed / new_day rubric, engine on or off.
    final plannerToday = getPlannerEnabled?.call() ?? false;
    // Rules stay 1-5-6 in order whichever optional ones are on.
    final sceneRuleNumber = plannerToday ? 6 : 5;
    // Built out-of-line: Dart forbids nesting single-quoted strings inside
    // a single-quoted interpolation, and this rule carries both quote
    // kinds (a numbered rule wrapping double-quoted place ids).
    var sceneRule = '';
    if (scenePlaceOn) {
      final ids = sceneOffer.map((p) => '"${p.id}" (${p.label})').join(', ');
      sceneRule =
          '$sceneRuleNumber. "scene_place": where the reply LEAVES the '
          'scene. Answer "same" unless the narration actually ARRIVES at '
          'one of these places: $ids. Answer "new" (plus "new_place_name" '
          'with its exact name and a one-line "new_place_descriptor") '
          'only when they arrive at a NAMED place NOT in that list — an '
          'unnamed side street is "same". A plan to go somewhere, or a '
          'mention of it, is "same". The characters must BE there by the '
          'end of the reply.\n';
    }
    final timeRules =
        '1. "minutes_elapsed": how many in-story minutes passed during the completed reply that was JUST written (integer, 1-${StoryClock.maxMinutesPerTurn} for a finished spoken exchange). '
        'This sets the clock the NEXT speaker will be told. '
        'Most conversational exchanges take 2-15 minutes; if unsure, use 5. Activities (a meal, a walk, a task, travel) take longer. '
        'Do NOT report 0 for a finished spoken reply.\n'
        '2. "continuous_instant": true ONLY when the scene is one continuous instant (mid-action, mid-sentence, the same moment with no time passing). '
        'A completed spoken reply is never a continuous instant. When true, minutes_elapsed is ignored and the clock stays still.\n'
        '3. "new_day": true ONLY if the conversation explicitly transitioned to the next day (slept, woke up, scene break). false otherwise. '
        'Merely MENTIONING yesterday, tomorrow, or another day does NOT count — the characters must actually cross a night.\n'
        '4. "days_elapsed": ONLY when the reply just written explicitly narrates a jump of one or more whole days ("a week later", "three days passed"), the number of days skipped (1-365). Otherwise 0. Mentioning a date or a plan is not a jump. With a jump, "lands_at": the time of day it lands at if the reply says (dawn, morning, late_morning, afternoon, evening, night, or 24-hour HH:MM), else blank. '
        '"hours_elapsed": ONLY when the reply explicitly narrates a jump of hours, not days ("six hours later", "they slept the night through"), the whole hours skipped (1-23). Otherwise 0.\n'
        '${plannerToday ? '5. "today_sentence": one sentence of what they are doing or planning today. '
                  'Empty or "none" abandons the current hold. Omit to keep it.\n' : ''}'
        '$sceneRule';

    // One time prompt. Engine-on adds scene framing; timeOnly asks bare.
    String buildPrompt({required bool toolsMode}) =>
        'You are evaluating how much story time just passed'
        '${timeOnly ? '' : ' for $charName'}.\n\n'
        '${timeOnly ? '' : '$emotionCtx$postureCtx'
                  'Relationship tension: $shortTermTierName.\n'}'
        'Current story time: ${state.displayClock} on ${state.narrativeWeekday}, Day ${state.dayCount}.\n\n'
        '$timeRules\n'
        'Recent conversation:\n$recent\n\n'
        '${toolsMode ? 'Report by calling the $kSceneTimeTool tool with "minutes_elapsed", "continuous_instant", "new_day", "days_elapsed", and "hours_elapsed"${plannerToday ? ' and "today_sentence"' : ''}${scenePlaceOn ? ', "scene_place", "new_place_name" and "new_place_descriptor"' : ''}. Use ONLY the tool — no plain-text reply.' : 'Respond with ONLY a flat JSON object containing "minutes_elapsed", "continuous_instant", "new_day", "days_elapsed", and "hours_elapsed"${plannerToday ? ' and "today_sentence"' : ''}${scenePlaceOn ? ', "scene_place", "new_place_name" and "new_place_descriptor"' : ''}. '
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
          maybeOfferSceneMove(text);
        } else {
          await applyVerdict(text);
        }
        if (!skipTodayEval) await _maybeApplyTodayEval(text);
      } else if (!skipOwnsClock) {
        await applier.applyElapsed(minutes: null, newDay: false);
      }
    } catch (e) {
      // Same fail-closed floor as a missing key or garbage JSON.
      if (!skipOwnsClock) {
        await applier.applyElapsed(minutes: null, newDay: false);
      }
      debugPrint(
        '[Realism:Time] Eval error, drifted to ${state.displayClock}: $e',
      );
    }

    debugPrint(
      '[Realism:Time] Time: ${state.displayClock} ${state.displayShortDate} (Day ${state.dayCount})',
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
