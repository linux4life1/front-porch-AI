// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Eval-canon extract: think-strip, JSON scalars, the recent-exchange
// window, and the needs-impact call that consumes them. Fire / retry /
// cancel stay on LlmEvalEngine. Do not fold StoryJson.stripThinkTags or
// char_macro.stripThinkBlocks — those are different contracts.

part of 'llm_eval_engine.dart';

/// The last few turns as `sender: text`, the shape every eval that needs scene
/// context uses.
///
/// Extracted because it was being written out by hand in three places and the
/// copies had already drifted into a bug. When Afterglow's climax check was
/// split out of the needs eval it inherited the reply and NOT this, so a climax
/// the user narrated became invisible to it and E2E went red on three platforms.
/// The Pockets pass had the same narrow view for the same reason.
///
/// Three turns is the window the needs eval has always used: enough to carry
/// the user's message and the reply it prompted, short enough that an eval
/// prompt stays an eval prompt.
/// Pre-gen judges score the USER. After Next Character the live list ends
/// on another NPC's reply — cut there so bond/mood/arousal cannot move off
/// that speech. Trust was already prompt-gated to the user; this is the
/// same rule in code. Post-gen (climax/pockets/posture) keep [recentExchange].
List<ChatMessage> messagesThroughLastUser(List<ChatMessage> msgs) {
  final i = msgs.lastIndexWhere((m) => m.isUser);
  return i < 0 ? msgs : msgs.sublist(0, i + 1);
}

String recentExchangeThroughLastUser(List<ChatMessage> msgs, {int take = 3}) =>
    recentExchange(messagesThroughLastUser(msgs), take: take);

String recentExchange(List<ChatMessage> msgs, {int take = 3}) {
  final n = msgs.length < take ? msgs.length : take;
  return msgs.reversed
      .take(n)
      .toList()
      .reversed
      // promptText, not displayText, since 2026-08-10: the two differ only
      // for photo messages, where promptText carries the "[shared a photo:
      // caption]" marker — and the realism judges already read promptText,
      // so needs/climax/pockets were the only evals blind to a photo the
      // exchange was about (eval review Tier-3 hygiene).
      .map((m) => '${m.sender}: ${clampEvalMessage(m.promptText)}')
      .join('\n');
}

/// Per-message ceiling for EVAL windows (chars, ≈1k tokens). Verbose models
/// write 20k+ character replies, and with no ceiling every judge window
/// ballooned to the size of a short story: the maintainer's own EvalTraffic
/// line showed four ~50k-char eval prompts in ONE turn — 48k tokens and 50
/// seconds of LLM time to score a single exchange, with the objective check
/// spending 50k chars on an 18-char answer. Evals judge the exchange; they
/// do not need to re-read the novella.
const int kEvalMessageCharCap = 4000;

/// The marker a clamped message carries in place of its middle. A visible
/// sentence, not an ellipsis: the judges must know text was omitted rather
/// than believe the reply jump-cut.
const String kEvalClampMarker =
    '[… middle of a very long message omitted for this evaluation …]';

/// Clamp ONE message's contribution to an eval window: text at or under
/// [kEvalMessageCharCap] passes through byte-identical (the overwhelming
/// majority — so short-message prompts, and every existing test fixture,
/// are unchanged); longer text keeps its head and tail around
/// [kEvalClampMarker]. Head-heavy on purpose — a reply's opening carries
/// the reaction to the user (what the judges score) and its tail carries
/// where the scene landed (what the reply-readers need). Pure and
/// deterministic, so a regen sees the identical window (the regen-parity
/// rule: identical inputs must produce identical eval prompts).
String clampEvalMessage(String text) {
  if (text.length <= kEvalMessageCharCap) return text;
  final head = (kEvalMessageCharCap * 2) ~/ 3;
  final tail = kEvalMessageCharCap - head;
  return '${text.substring(0, head)}\n$kEvalClampMarker\n'
      '${text.substring(text.length - tail)}';
}

/// Eval-lane think-strip. Completes, unclosed prefix, and orphan close.
/// User-prose stripThinkTags and chargen stripThinkBlocks stay separate.
String stripEvalThinkBlocks(String text) {
  String cleaned = canonicalizeReasoning(
    text,
  ).replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '').trim();
  final unclosed = cleaned.indexOf('<think>');
  if (unclosed >= 0) {
    cleaned = cleaned.substring(0, unclosed).trim();
  }
  // Third leak shape (utils/think_tags.dart names all three): a bare orphan
  // `</think>` whose opening tag the transport/chat template consumed, so
  // everything BEFORE it is reasoning. Unlike the user-prose strip — which
  // only drops the tag, because wiping prose would blank a legit message —
  // the eval lane must drop that reasoning: every extractor below is a
  // firstMatch over the whole string, so leaving it in hands the parse the
  // model's DRAFT numbers instead of its final JSON. Kept only when
  // something follows; otherwise callers' existing raw fallback applies.
  final orphan = cleaned.lastIndexOf('</think>');
  if (orphan >= 0) {
    final after = cleaned.substring(orphan + '</think>'.length).trim();
    if (after.isNotEmpty) cleaned = after;
  }
  return cleaned;
}

extension LlmEvalExtract on LlmEvalEngine {
  Future<String?> _evaluateNeedsImpactCall(
    String responseText, {
    void Function(String)? onChunk,
    int strength =
        1, // 1-5; injected into the prompt so the model emits deltas at the user-requested magnitude on the *first* call (e.g. normal -3 becomes ~-15 at 5x). When Director authority is on, the verifier is also told the strength and corrects in the scaled space. The evaluator no longer post-multiplies after Director (avoids double-scaling a -15 into -75).
    String? userCritique,
    Map<String, int>? previousDeltas,
    Map<String, int>? currentNeeds,
    int? decayTurns,
    Set<String> onlyNeeds = const {},
  }) async {
    if (!getRealismEnabled()) return null;
    if (getActiveCharacter() == null && getActiveGroup() == null) return null;
    if (getActiveGroup() != null && getIsObserverMode()) {
      return null; // Director
    }

    final recent = recentExchange(getMessages());

    final char = getActiveCharacter();
    final charName = char?.name ?? 'the character';
    String personalityInjection = '';
    if (char != null && char.personality.isNotEmpty) {
      final p = char.personality;
      personalityInjection = 'Character Personality Traits:\n"$p"\n\n';
    }
    final currentStance = relationshipService.spatialStance.isNotEmpty
        ? 'Current physical position/stance of $charName: "${relationshipService.spatialStance}". '
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

    final decayContextStr = decayTurns != null
        ? (decayTurns > 0
              ? '\nNOTE: Time has passed \u2014 needs have drifted lower by $decayTurns turn(s) of normal decline. '
                    'When the scene describes an activity that restores a need (using the bathroom -> bladder +60 to +100, '
                    'eating -> hunger +50 to +90, resting/sleeping -> energy +60 to +100, washing -> hygiene +50 to +90), '
                    'use the full chart magnitude \u2014 do not undershoot. The baseline was higher before the decline.\n\n'
              : '\nNOTE: No passive decay is occurring. Report only the scene\'s direct effects on needs \u2014 '
                    'do not subtract any baseline drift.\n\n')
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
      if (decayTurns != null) {
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
            'Guidelines (at ${strength}x scale \u2014 scale these baselines by $strength):\n'
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
            'Only report positive gains. Do NOT subtract anything.\n'
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
                '$decayContextStr'
                'This is immersive erotic roleplay. Detailed physical and psychological descriptions matter: self-touch, bodily arousal states, fluids, dominance, submission, power exchange, and explicit narration of actions should influence needs (fun, social, comfort, hygiene, energy, hunger, bladder) in natural grounded ways.\n\n'
                'Be reasonable and faithful to the written text. Do not invent events that are not described.\n\n'
                'PREVIOUS DELTAS:\n$prev\n\n'
                'USER CRITIQUE (The user noticed an issue with the deltas that MUST be fixed):\n"$userCritique"\n\n'
                'Analyze what actually occurred and output a corrected set of net signed effects (deltas) on each need.\n\n'
                'User has set Needs delta strength to ${strength}x. Emit deltas with magnitude scaled by this factor.\n\n'
                '${scoped.isEmpty ? 'Even if the critique suggests little/no change, you MUST output the complete flat JSON with all seven _delta keys (0 is valid). Do not omit fields.\n\n' : 'Reconsider ONLY ${scoped.join(', ')}. Do not emit any other need — those values are already correct and will be kept. Output ONLY {$deltaAsk, "reason": "<brief>"}.\n\n'}'
                'MAGNITUDE: needs run 0–100 (100 = fully satisfied); ±8 BARELY registers. When the scene SATISFIES/RESTORES a need, use a LARGE positive delta so it actually fills — using the bathroom → bladder +60 to +100; a full meal → hunger +50 to +90; sleeping / a long rest → energy +60 to +100; cozy solitude, lounging, drowsing → comfort +20 to +45, energy +10 to +30; a thorough wash → hygiene +50 to +90. Reserve small numbers for incidental effects, never a complete relief. (1x baselines; scale by the strength above.)\n\n'
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
                '$decayContextStr'
                'Analyze what actually occurred in the scene (actions, physical descriptions, dialogue, power dynamics, emotional tone) and determine the *net signed effects* on each of $charName\'s needs caused by this scene'
                '${decayContextStr.isEmpty ? ', on top of normal decay' : ''}.\n\n'
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
                // CLAUDE.md already forbids this for the Realism Engine — "the
                // eval scores the USER's message, never the character's own
                // reply" — and the rule had simply never been applied here.
                'DEPLETION IS HANDLED SEPARATELY. Needs drift downward on their own every turn; '
                'that is already accounted for and is not your job. The scene text above was WRITTEN FROM '
                'the current needs listed below — a character mentioning their empty stomach, dragging their feet, '
                'or squirming is DESCRIBING the state you are being shown, not becoming worse. Do not charge '
                'them for it.\n'
                'Report a NEGATIVE delta only when the scene explicitly describes something that COST them: '
                'hard exertion, sex, a soaking or a mess, being kept awake, going without, or drinking a '
                'lot (which fills the bladder rather than emptying it). A described event SHOULD register '
                'clearly — a soda is a real hit to bladder, a long walk a real hit to energy — it is the '
                'ambient drift you must not double-count. Otherwise the negative is 0; most needs in most '
                'scenes should be 0.\n\n'
                'Report *net signed effects* (deltas) on each need.\n\n'
                'User has set Needs delta strength to ' +
            strength.toString() +
            'x. Emit deltas with magnitude scaled by this factor so the final applied swings match the user setting (example: a hygiene hit you would normally call -3 at 1x should be around -15 at 5x; small effects stay small at 1x). The Director (if reviewing) also receives this strength and will correct at the requested scale.\n\n'
                'The optional Director/Verifier (when enabled with authority on needs) will correct you if your structured output does not match the actual narrative you just wrote.\n\n'
                'CRITICAL — MAGNITUDE: needs run 0–100 (100 = fully satisfied). A delta of ±5 is a nudge and ±8 BARELY registers, so when the scene clearly SATISFIES or RESTORES a need you MUST use a LARGE positive delta so the need actually fills — do NOT lowball a complete relief:\n'
                '  • Using the bathroom / relieving oneself → bladder +60 to +100 (a full relief nearly maxes it; +8 leaves them still desperate to go)\n'
                '  • A full meal → hunger +50 to +90 (a snack is smaller, ~+15)\n'
                '  • Sleeping, a long rest, or "through the night / waking next morning" → energy +60 to +100 (and broadly restores other physical needs as the body recovers; hygiene/social/fun stay only mildly affected)\n'
                '  • Drowsing, lounging, cozy solitude, or quiet relaxation → comfort +20 to +45, energy +10 to +30\n'
                '  • A thorough wash, shower, or bath → hygiene +50 to +90\n'
                '  • Deep, fulfilling social connection, cuddling, or play → social / fun +20 to +50; comfort +10 to +25\n'
                'Partial or interrupted versions get proportionally smaller deltas. Reserve small numbers (±1 to ±8) for INCIDENTAL effects, never for a complete relief or restoration. (These are 1x baselines — scale by the strength factor above.)\n\n' +
            flatJsonAsk +
            (toolsMode
                ? 'Individual needs may be 0. All seven 0 is a failed eval — score what the beat did to their body and mood.'
                : '"reason": "<brief grounded reason for the deltas>" }\n'
                      'Individual needs may be 0. All seven 0 is a failed eval — score what the beat did to their body and mood.');
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
      final useTools = scoped.isEmpty && fireToolEval != null && probe != null;
      final raw = useTools
          ? await fireStructuredEval(
              probe: probe!,
              backendIdentity: getBackendIdentity?.call() ?? '',
              debugLabel: kNeedsImpactTool,
              tools: kNeedsImpactEvalTools,
              buildPrompt: buildPrompt,
              callToText: (resp) =>
                  realismToolCallToJson(kNeedsImpactTool, resp.calls),
              fireToolEval: fireToolEval!,
              toolChoice: kNeedsImpactTool,
              getPreferTextEvals: getPreferTextEvals,
              fireTextEval: (p, {onChunk}) => fireLLMEval(
                p,
                onChunk: onChunk,
                repeatPenalty: kScalarEvalRepeatPenalty,
                label: 'needs',
              ),
              isCancelled: () =>
                  getIsCancellingRealismEval() || getRealismEvalCancelled(),
              onChunk: onChunk,
            )
          : await fireLLMEval(
              buildPrompt(toolsMode: false),
              onChunk: onChunk,
              repeatPenalty: kScalarEvalRepeatPenalty,
              label: 'needs',
            );
      if (raw == null) return null;
      final searchText = stripThinkBlocks(raw);
      // Same fallback the four realism calls use: a think-only reply (a
      // mandatory-reasoning model that parked its JSON in the think channel,
      // or was cut mid-think) must still reach the regex parse rather than
      // silently skipping the needs turn.
      var text = searchText.trim().isNotEmpty ? searchText : raw;
      if (text.trim().isEmpty) return null;
      if (scoped.isEmpty && !needsImpactHasNonZeroDelta(text)) {
        final usedTools =
            useTools &&
            (probe?.shouldFireTools(
                  getBackendIdentity?.call() ?? '',
                  preferTextEvals: getPreferTextEvals?.call() ?? false,
                ) ??
                false);
        final recovered = await recoverNeedsImpactIfAllZero(
          first: text,
          retryText: usedTools
              ? () => fireLLMEval(
                  buildPrompt(toolsMode: false),
                  onChunk: onChunk,
                  repeatPenalty: kScalarEvalRepeatPenalty,
                  label: 'needs',
                )
              : () async => null,
          repair: () => fireLLMEval(
            needsImpactAllZeroRepairPrompt(responseText, strength),
            onChunk: onChunk,
            repeatPenalty: kScalarEvalRepeatPenalty,
            label: 'needs',
          ),
          stripThink: stripThinkBlocks,
        );
        if (recovered != text) {
          debugPrint('[Realism:Needs] all-zero rejected; using recovered JSON');
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
