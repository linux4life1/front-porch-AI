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

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/chat/llm_eval_engine.dart';
import 'package:front_porch_ai/services/chat/needs_impact_zero.dart';
import 'package:front_porch_ai/services/chat/needs_simulation.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/chat/realism_tools.dart';

/// The needs-impact eval call, run against the [LlmEvalEngine] that owns
/// the transport, the guards, and the state it reads.
class NeedsImpactCall {
  NeedsImpactCall(this._engine);

  final LlmEvalEngine _engine;

  Future<String?> run(
    String responseText, {
    void Function(String)? onChunk,
    String? userCritique,
    Map<String, int>? previousDeltas,
    Map<String, int>? currentNeeds,
    bool awayScene = false,
    Set<String> onlyNeeds = const {},
  }) async {
    if (!_engine.getRealismEnabled()) return null;
    if (_engine.getActiveCharacter() == null &&
        _engine.getActiveGroup() == null) {
      return null;
    }

    final recent = recentExchange(_engine.getMessages());

    final char = _engine.getActiveCharacter();
    final charName = char?.name ?? 'the character';
    String personalityInjection = '';
    if (char != null && char.personality.isNotEmpty) {
      final p = char.personality;
      personalityInjection = 'Character Personality Traits:\n"$p"\n\n';
    }
    final currentStance = _engine.relationshipService.spatialStance.isNotEmpty
        ? 'Current physical position/stance of $charName: "${_engine.relationshipService.spatialStance}". '
        : '';

    // Climax guidance USED TO LIVE HERE. It moved to the arousal section of
    // the realism evals (2026-08-07) because Afterglow depended on it and this
    // eval never runs unless Needs is on — which it is not, on most cards. The
    // needs eval has no reader for is_climax any more, so asking for it here
    // would be paying tokens for a field nothing consumes.

    final needsStateStr = currentNeeds != null && currentNeeds.isNotEmpty
        ? '\nCurrent needs for $charName (0-100, lower = more urgent): '
              '${currentNeeds.entries.map((e) => '${e.key}: ${e.value}').join(', ')}\n\n'
        : '';

    final scoped = {
      for (final k in onlyNeeds)
        if (NeedsSimulation.needKeys.contains(k)) k,
    };
    final askedKeys = scoped.isEmpty
        ? NeedsSimulation.needKeys
        : scoped.toList();
    final deltaAsk = askedKeys.map((k) => '"${k}_delta": <int>').join(', ');

    String buildPrompt({required bool toolsMode}) {
      // The format sections below are the ONLY difference between the tools
      // and text transports — every guideline/magnitude line is shared, so
      // the two paths can never drift in what the model is told.
      // The text ask names ONLY fields something still reads: the seven
      // deltas + reason. `activities`/`intensity` were requested for years
      // and never read by anything (the Director hint even said so), and
      // `is_climax`/`refractory_turns` moved out with Afterglow's own pass
      // (2026-08-07) — the comment above records that nothing here consumes
      // them, and as of 2026-08-10 the ask finally agrees (eval review
      // Tier-1 §3.5). The TOOL schema keeps activities/intensity DEFINED
      // (optional, never required) because the registry is a fixed contract
      // and the converter's scalar-array branch is pinned by
      // tool_registry_test.
      final flatJsonAsk = toolsMode
          ? 'Report the result by calling the $kNeedsImpactTool tool. '
                'Use ONLY the tool — no plain-text reply.\n'
          : 'Respond with ONLY a flat JSON object. Do NOT use markdown code blocks — return raw JSON only:\n'
                '{$deltaAsk, ';
      if (awayScene) {
        // ── AFK auto-response simplified prompt ──────────────────────────
        // The normal evaluator prompt (~2000 chars) is too complex for
        // local models, causing them to return small negative defaults
        // instead of proper restorative deltas. This stripped-down version
        // only lists restorative activities with positive deltas.
        return 'Evaluate how this daily scene affects $charName\'s needs.\n\n'
            '$needsStateStr'
            'Scene:\n$responseText\n\n'
            '${toolsMode ? 'Report the effects by calling the $kNeedsImpactTool tool with all seven _delta fields and a reason.\n\n' : 'Return ONLY raw JSON with all seven _delta fields and a reason. '
                      'Do not use markdown code blocks. No other text.\n'
                      '{"hunger_delta": <int>, "energy_delta": <int>, "hygiene_delta": <int>, '
                      '"fun_delta": <int>, "social_delta": <int>, "bladder_delta": <int>, '
                      '"comfort_delta": <int>, "reason": "<brief reason>"}\n\n'}'
            'Guidelines (answer at Normal; do not scale these numbers):\n'
            '  • Eating food or a meal \u2192 hunger +15 to +70\n'
            '  • Using toilet or bathroom \u2192 bladder +30 to +90\n'
            '  • Sleeping or long rest \u2192 energy +40 to +80\n'
            '  • Napping, dozing, or lying down \u2192 energy +15 to +35\n'
            '  • Shower, bath, or full washing \u2192 hygiene +30 to +70\n'
            '  • Washing face, brushing teeth, freshening up \u2192 hygiene +5 to +20\n'
            '  • Reading, browsing, or quiet relaxation \u2192 comfort +10 to +40\n'
            '  • Watching TV or videos \u2192 comfort +5 to +15\n'
            '  • Looking at photos, albums, or mementos \u2192 comfort +10 to +25\n'
            '  • Using phone or computer for leisure \u2192 fun +5 to +15\n'
            '  • Scrolling social media on phone \u2192 fun +5 to +10\n'
            '  • Standing at a window, enjoying a view, or looking outside \u2192 comfort +5 to +15\n'
            '  • Exercise, yoga, or stretching \u2192 energy +5 to +15, comfort +5\n'
            '  • Drinking any beverage \u2192 energy +5 to +10\n'
            '  • Cooking or preparing food \u2192 comfort +5\n\n'
            'Time has already been charged for the beat named at the start of the '
            'scene. Score only what the scene itself restored or cost.\n'
            '${toolsMode ? 'Use ONLY the tool — no plain-text reply.' : 'Return raw JSON with no markdown, no explanation.'}';
      } else if (userCritique != null && userCritique.trim().isNotEmpty) {
        // B: unified rich correction prompt (no duplication of context logic)
        final prev = jsonEncode(previousDeltas ?? {});
        return 'You are the Realism Director correcting the previous Needs deltas for a roleplay scene.\n\n'
                '$personalityInjection'
                '$currentStance'
                'RESPONSE (the scene that just happened):\n$responseText\n\n'
                'Recent exchange for context:\n$recent\n\n'
                '$needsStateStr'
                'This is immersive erotic roleplay. Detailed physical and psychological descriptions matter: self-touch, bodily arousal states, fluids, dominance, submission, power exchange, and explicit narration of actions should influence needs (fun, social, comfort, hygiene, energy, hunger, bladder) in natural grounded ways.\n\n'
                'Be reasonable and faithful to the written text. Do not invent events that are not described.\n\n'
                'PREVIOUS DELTAS:\n$prev\n\n'
                'USER CRITIQUE (The user noticed an issue with the deltas that MUST be fixed):\n"$userCritique"\n\n'
                'Analyze what actually occurred and output a corrected set of net signed effects (deltas) on each need.\n\n'
                '${scoped.isEmpty ? 'Even if the critique suggests little/no change, you MUST output the complete flat JSON with all seven _delta keys (0 is valid). Do not omit fields.\n\n' : 'Reconsider ONLY ${scoped.join(', ')}. Do not emit any other need — those values are already correct and will be kept. Output ONLY {$deltaAsk, "reason": "<brief>"}.\n\n'}'
                'MAGNITUDE: needs run 0–100 (100 = fully satisfied); ±8 BARELY registers. When the scene SATISFIES/RESTORES a need, use a LARGE positive delta so it actually fills — using the bathroom → bladder +60 to +100; a full meal → hunger +50 to +90; sleeping / a long rest → energy +60 to +100; cozy solitude, lounging, drowsing → comfort +20 to +45, energy +10 to +30; a thorough wash → hygiene +50 to +90. Reserve small numbers for incidental effects, never a complete relief. Answer at Normal. Do not scale.\n\n'
                '${scoped.isEmpty ? 'Examples of valid correction output:\n{"hunger_delta": 8, "energy_delta": 0, "hygiene_delta": -2, "fun_delta": 5, "social_delta": 0, "bladder_delta": 0, "comfort_delta": 1, "reason": "ate snack per critique"}\n{"hunger_delta": 0, "energy_delta": 0, "hygiene_delta": 0, "fun_delta": 0, "social_delta": 0, "bladder_delta": 0, "comfort_delta": 0, "reason": "no notable need impact"}\n\n' : 'Example: {$deltaAsk, "reason": "rested per critique"}\n\n'}' +
            flatJsonAsk +
            (toolsMode
                ? ''
                : '"reason": "<brief grounded reason for the deltas incorporating the critique>" }');
      } else {
        return 'You are evaluating the effects of a roleplay scene on $charName\'s needs.\n\n'
                '$personalityInjection'
                '$currentStance'
                'RESPONSE (the scene that just happened):\n$responseText\n\n'
                'Recent exchange for context:\n$recent\n\n'
                '$needsStateStr'
                'Analyze what actually occurred in the scene (actions, physical descriptions, dialogue, power dynamics, emotional tone) and determine the *net signed effects* on each of $charName\'s needs caused by this scene.\n\n'
                'This is immersive erotic roleplay. Detailed physical and psychological descriptions matter: self-touch, bodily arousal states ("charging", "aching", "swollen", "leaking through fabric"), fluids, dominance, submission, "choosing", begging, power exchange, and explicit narration of what the character is doing or feeling should influence the relevant needs (fun, social, comfort, hygiene, energy, etc.) in natural, grounded ways.\n\n'
                'Be reasonable and faithful to the written text. Do not invent events that are not described.\n\n'
                // ── THE LOOP-BREAKER ────────────────────────────────────────
                // Reported 2026-08-08: "the need starts to influence the
                // response, then next turn the response further boosts the need
                // gravity… sudden loss of like 35-40 points in single turn."
                //
                // The RESPONSE above was written FROM the needs listed below it:
                // the state block hands the model lines like "sharp, gnawing
                // hunger cramps… thoughts drifting uncontrollably to food", the
                // model narrates exactly that, and this eval then read the
                // narration as evidence they had BECOME hungrier. Describing a
                // state was being scored as changing it, and the lower a need
                // went the more vivid the prose and the harder the next hit.
                //
                // The clock charges the span in code (needs_wear.dart); the
                // beat note above the scene says so. The judge scores events.
                'TIME HAS ALREADY BEEN CHARGED for the beat named at the start of the '
                'scene: hunger, bladder and energy moved with the minutes. Do not '
                'charge the span again. Score what the scene did: a meal is the meal, '
                'a drink fills the bladder (a drop), the bathroom is that relief, '
                'sleep restores energy. Nothing happened means zero.\n'
                'The scene text above was WRITTEN FROM the current needs listed below — '
                'a character mentioning their empty stomach, dragging their feet, or '
                'squirming is DESCRIBING the state you are being shown, not becoming '
                'worse. Do not charge them again for that description.\n'
                'Energy, hygiene, fun, social, and comfort take a NEGATIVE delta only '
                'when the scene explicitly describes something that COST them: hard '
                'exertion, sex, a soaking or a mess, or being kept awake. Drinking '
                'fills the bladder (a drop) rather than emptying it. A described event '
                'SHOULD register clearly — a soda is a real hit to bladder, a long walk '
                'a real hit to energy. Otherwise those five stay 0.\n\n'
                'Report *net signed effects* (deltas) on each need. Answer at Normal. Do not scale your numbers; drops are scaled afterward.\n\n'
                'The optional Director/Verifier (when enabled with authority on needs) will correct you if your structured output does not match the actual narrative you just wrote.\n\n'
                'CRITICAL — MAGNITUDE: needs run 0–100 (100 = fully satisfied). A delta of ±5 is a nudge and ±8 BARELY registers, so when the scene clearly SATISFIES or RESTORES a need you MUST use a LARGE positive delta so the need actually fills — do NOT lowball a complete relief:\n'
                '  • Using the bathroom / relieving oneself → bladder +60 to +100 (a full relief nearly maxes it; +8 leaves them still desperate to go)\n'
                '  • A full meal → hunger +50 to +90 (a snack is smaller, ~+15)\n'
                '  • Sleeping, a long rest, or "through the night / waking next morning" → energy +60 to +100 (and broadly restores other physical needs as the body recovers; hygiene/social/fun stay only mildly affected)\n'
                '  • Drowsing, lounging, cozy solitude, or quiet relaxation → comfort +20 to +45, energy +10 to +30\n'
                '  • A thorough wash, shower, or bath → hygiene +50 to +90\n'
                '  • Deep, fulfilling social connection, cuddling, or play → social / fun +20 to +50; comfort +10 to +25\n'
                'Partial or interrupted versions get proportionally smaller deltas. Reserve small numbers (±1 to ±8) for INCIDENTAL effects, never for a complete relief or restoration.\n\n' +
            flatJsonAsk +
            (toolsMode
                ? 'Individual needs may be 0. All seven 0 is a quiet beat, and a valid answer.'
                : '"reason": "<brief grounded reason for the deltas>" }\n'
                      'Individual needs may be 0. All seven 0 is a quiet beat, and a valid answer.');
      }
    }

    try {
      debugPrint(
        userCritique != null
            ? '[Realism:Needs] Running manual reprocess impact eval (via engine)...'
            : '[Realism:Needs] Running consolidated impact eval (via engine)...',
      );
      // Tools transport when wired (the shared negotiation — one probe per
      // backend identity per run, shared app-wide); plain text path otherwise
      // (tests / hosts without the tools door).
      // A scoped reprocess (user ticked Energy, not all seven) skips the
      // tools+text pair: the tool schema is the fixed seven-field contract,
      // and falling back after an empty tool call is how one Energy click
      // became four oMLX jobs.
      final useTools =
          scoped.isEmpty &&
          _engine.fireToolEval != null &&
          _engine.probe != null;
      final raw = useTools
          ? await fireStructuredEval(
              probe: _engine.probe!,
              backendIdentity: _engine.getBackendIdentity?.call() ?? '',
              debugLabel: kNeedsImpactTool,
              tools: kNeedsImpactEvalTools,
              buildPrompt: buildPrompt,
              callToText: (resp) =>
                  realismToolCallToJson(kNeedsImpactTool, resp.calls),
              fireToolEval: _engine.fireToolEval!,
              toolChoice: kNeedsImpactTool,
              getPreferTextEvals: _engine.getPreferTextEvals,
              fireTextEval: (p, {onChunk}) => _engine.fireLLMEval(
                p,
                onChunk: onChunk,
                repeatPenalty: kScalarEvalRepeatPenalty,
                label: 'needs',
              ),
              isCancelled: () =>
                  _engine.getIsCancellingRealismEval() ||
                  _engine.getRealismEvalCancelled(),
              onChunk: onChunk,
            )
          : await _engine.fireLLMEval(
              buildPrompt(toolsMode: false),
              onChunk: onChunk,
              repeatPenalty: kScalarEvalRepeatPenalty,
              label: 'needs',
            );
      if (raw == null) return null;
      final searchText = _engine.stripThinkBlocks(raw);
      // Same fallback the four realism calls use: a think-only reply (a
      // mandatory-reasoning model that parked its JSON in the think channel,
      // or was cut mid-think) must still reach the regex parse rather than
      // silently skipping the needs turn.
      var text = searchText.trim().isNotEmpty ? searchText : raw;
      if (text.trim().isEmpty) return null;
      // A quiet beat is a legitimate all-zero now that the clock charges
      // the span. Only the away prompt, which expects restorations, still
      // retries a tools reply whose required ints came back as zeros.
      if (awayScene && scoped.isEmpty && !needsImpactHasNonZeroDelta(text)) {
        final usedTools =
            useTools &&
            (_engine.probe?.shouldFireTools(
                  _engine.getBackendIdentity?.call() ?? '',
                  preferTextEvals: _engine.getPreferTextEvals?.call() ?? false,
                ) ??
                false);
        final recovered = await recoverNeedsImpactIfAllZero(
          first: text,
          retryText: usedTools
              ? () => _engine.fireLLMEval(
                  buildPrompt(toolsMode: false),
                  onChunk: onChunk,
                  repeatPenalty: kScalarEvalRepeatPenalty,
                  label: 'needs',
                )
              : () async => null,
          stripThink: _engine.stripThinkBlocks,
        );
        if (recovered != text) {
          debugPrint('[Realism:Needs] tools zeros retried as text');
          text = recovered;
        }
      }
      return text;
    } catch (e) {
      debugPrint('[Realism:Needs] Engine impact call failed: $e');
      return null;
    }
  }
}
