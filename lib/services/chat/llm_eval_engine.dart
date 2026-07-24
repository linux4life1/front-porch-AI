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

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/chat/realism_tools.dart';
import 'package:front_porch_ai/services/chat/relationship_service.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/models/group_chat.dart';

/// Hang guard for eval streams: the maximum gap between streamed chunks
/// before the attempt is treated as dead (covers the first token too, so a
/// backend stalling on a cold model reload — or holding a request in a queue
/// forever — can't park an eval and its spinner indefinitely). Generous on
/// purpose: slow local prefill on a big journal window must still fit.
const Duration kEvalStreamChunkTimeout = Duration(seconds: 180);

/// Hang guard for the non-streaming tools-transport call (the journal/
/// realism tool calls and the one-shot capability probe). Whole-call
/// deadline, so it must cover a full slow-hardware generation — a timed-out
/// PROBE merely marks the backend XML-only for the run (text path floor,
/// which carries its own chunk timeout).
const Duration kEvalToolCallTimeout = Duration(minutes: 6);

/// Plain (non-ChangeNotifier) domain service owning the central LLM eval
/// firing (_fireLLMEval with full streaming + retry loop + cancel support,
/// fixed params maxLength:4000 / temp 0.1 / reasoningEnabled:false / stop: []),
/// the tiny _extractJsonInt/_extractJsonBool helpers, the central
/// _stripThinkBlocks (handles completed + unclosed &lt;think&gt; prefix).
/// (The 5 realism eval prompt builders + call methods (relationship, emotional,
/// physical, narrative with proposed_objective logic, one-shot fused) moved to
/// sibling leaf realism_evals.dart in step 10 per extraction order; the
/// objective proposal path handling + generateObjectiveTasks +
/// _checkTaskCompletionInBackground moved to sibling leaf
/// objective_proposal.dart in step 11; this engine now provides the
/// fire/strip/extract cbs + evaluateNeedsImpactCall for the needs domain +
/// the 5 realism calls (granular cbs to realism_evals) + fire/strip to
/// objective_proposal.)
///
/// Extracted as step 9 (immediately after prompt_injection step 8 per the
/// 15-step leaf-first order in docs/refactoring-guide.md).
/// + needs impact support (evaluateNeedsImpactCall for the needs_impact_evaluator leaf; open prompt + simple clamps, model-driven like other realism evals).
/// + step 10 sibling realism_evals uses this engine's fire/strip/extract for the
/// 5 realism calls (granular cbs; prompt builders full in leaf).
/// + step 11 sibling objective_proposal uses this engine's strip (for central
/// &lt;think&gt; in 2000 gen/check paths).
///
/// Depends on prompt_injection only in the ordering sense (prompt builders
/// for main chat context are step 8); this engine's eval prompts are
/// self-contained (no direct use of the 8 _get*Injection builders).
/// "thin delegation here; full engine in step9"; "objective proposal
/// coordination kept thin/stayed in god per plan for step9/11" (setObjective
/// + generate dispatch + list mgmt + _load + _activeObjectives + tasksFor
/// + _isChecking + _pendingRealismMetadata + captureRealismState +
/// _saveChat coordination stay in god; engine calls via cbs only; full
/// gen/check + internal prompt/strip/parse in step 11 leaf).
///
/// ChatService owns via 1 late final (inserted after the 8 prompt_injection
/// ones) + thin public delegates (_fireLLMEval, _stripThinkBlocks,
/// _extract*, evaluateNeedsImpactCall) at *every* prior call site (firing points,
/// direct _fire/_strip/_extract calls, needs impact thin). The 5 _evaluate*Call
/// thins delegate to realism_evals (step 10). generateObjectiveTasks +
/// _checkTaskCompletionInBackground thins now delegate to objective_proposal
/// (step 11). 0 @Deprecated shims for this surface (thins stay in god as the
/// public surface for now).
/// 0 new god private _ methods beyond the required thin delegates (_fireLLMEval/_strip/_extract* + evaluateNeedsImpactCall; void _ count stayed 15; +1 late final only; thins/calls/late final only per plan;
/// reset comment syncs only).
///
/// Ctor receives state via granular callbacks (modeled exactly on steps 6-8:
/// onNotify, onSaveChat (now dead post step11 objective move; removed below),
/// getActiveCharacter, getActiveGroup, getGroupCharacters
/// not needed here, getUserName, getCharacterIdFromCard not directly,
/// isGroup/isObserverMode via getActiveGroup+getIsObserverMode,
/// getGroupValue/setGroupValue not needed (use rel/nsfw services for scalars),
/// plus for fire readiness + cancel: getLlmService, getIsLocal, getKoboldService,
/// reconnectIfAlive, ensureServerIdle, getIsCancellingRealismEval,
/// getRealismEvalCancelled,
/// plus for state sets (now used by needs impact; realism evals use via their own
/// leaf cbs; objective gen/check moved to step 11 leaf): get/setPendingRealismMetadata,
/// captureRealismState, get/setCharacterEmotion, get/setEmotionIntensity,
/// plus dep services for their owned state (relationshipService for apply deltas /
/// updateFixation / setSpatial / shortTermTierName / trustLevel / spatialStance
/// used by stayed needs impact path).
/// Use live closures over god state for any cross (e.g. _pending map, emotion
/// scalars, test overrides); avoid cycles; testable with small factory in test.
///
/// 1:1 vs group parity + oneShot vs normal eval deltas 1:1 equivalent
/// (Realism Engine bond/trust ±300, arousal ±100, emotion inertia, fixation,
/// deterministic time every 6, needs decay/step/catastrophe/erotic buffers/
/// afterglow/lust-haze/post-crash/priority/fulfillment; objectives/tasks
/// autonomous get autoGenerateTasks:true + correct target even under
/// impersonation, user-created do not — proposal target + gen/check dispatch
/// preserved via cbs + god impersonation; full in step 11 leaf) qualified
/// (preserved exactly; exercised in dedicated + key suites + manual). The 5
/// realism calls now in sibling leaf (step 10) inherit the same cbs/impersonation
/// for parity.
///
/// All &lt;think&gt; stripping uses the central stripThinkBlocks (2000 budget
/// already applied in gen/check/objective paths via step 11 leaf's use of this
/// strip cb; naive inlines in non-eval paths left for later steps).
///
/// Reset hygiene: stateless or prompt-only (no owned reset/seed/load state);
/// no reset calls needed on engine; comments in god updated to list full
/// "needs/chaos/relationship/expression/time/nsfw/lorebook_scanner +
/// prompt_injection (stateless builders; no reset calls needed) +
/// llm_eval_engine (stateless or prompt-only; no reset calls needed;
/// incomplete zeroing of secondary config on group/0-session/new-chat now complete)
/// + realism_evals (stateless or prompt-only; no reset calls needed)
/// + objective_proposal (stateless or prompt-only; no reset calls needed)"
/// + cross-refs (e.g. setActiveCharacter:1572) at all ~12-15 sites (top ctor
/// docs + setActiveCharacter, setActiveGroup x2, _loadLast empty, startNewChat
/// 1:1 ext-seed + group non-ext both branches, other load/seed); both startNew
/// branches have explicit comments even if no engine reset call.
///
/// aug exercising only passive/qualified (no llm-eval-specific aug file edits;
/// reset sites passively hit by pre-existing startNew/setActive/_loadLast/group;
/// full eval/JSON/strip + needs impact only in dedicated + manual;
/// objective proposal/gen/check exercised via god thins generate/check ;
/// qualified notes only in dedicated header + god + MD per precedent).
///
/// test count 11 (11 bodies via grep -c '^\s*test(' confirmed post dead noop/placeholder deletion as part of task; objective tests excised to dedicated step11 test).
/// (onNotify of cbs unexercised by design (no onNotify wiring in this passive factory; exercised in prod + key suites); onNotify/onSaveChat now dead post step11 objective move, to be cleaned).
/// 0 new god private _ methods beyond required thin delegates (fire/strip/extract thins; void_ grep 15; +1 late final only; thins/calls/late final only per plan; confirmed grep).
/// dispatch preserved.
/// realism/oneShot/group parity qualified.
///
/// Some objective mgmt / prompt coordination stayed thin in god per plan for step9/11
/// (qualify everywhere; full objective proposal in step 11 sibling leaf).
/// Realism evals (step 10) own their 5 calls + prompts.
class LlmEvalEngine {
  // (onNotify/onSaveChat removed here post step11 objective_proposal extraction;
  // they were only used by the moved checkTaskCompletionInBackground finally;
  // deletion part of task + anti-accumulation. Engine is now strictly for fire/strip/
  // extract + needs impact call. on* if needed by future would be re-added then.)

  // Character / group / mode state (for guard + 1:1 vs group dispatch via impersonation)
  final CharacterCard? Function() getActiveCharacter;
  final GroupChat? Function()
  getActiveGroup; // note: GroupChat type from models
  final bool Function() getIsObserverMode;

  // User / persona for eval prompts
  final String Function() getUserName;

  // Realism flag
  final bool Function() getRealismEnabled;

  // Messages for recent context in evals + gen/check
  final List<ChatMessage> Function() getMessages;

  // Tools transport for the needs-impact eval (nullable — tests and any
  // host without the tools door stay on the text path; the god wires the
  // same _fireToolEval/_toolProbe/_evalBackendIdentity the Journal, Growth,
  // and realism evals share, so the probe answers once per run app-wide).
  final Future<LlmToolResponse?> Function(
    String prompt,
    List<Map<String, dynamic>> tools,
  )?
  fireToolEval;
  final ToolTransportProbe? probe;
  final String Function()? getBackendIdentity;

  // LLM readiness + cancel (honors test overrides via live closure in god)
  final LLMService Function() getLlmService;
  final bool Function() getIsLocal;
  final KoboldService? Function() getKoboldService;
  final Future<void> Function() reconnectIfAlive;
  final Future<void> Function() ensureServerIdle;
  final bool Function() getIsCancellingRealismEval;
  final bool Function() getRealismEvalCancelled;

  // Pending metadata + capture for realism state snapshot (oneShot + rel)
  final Map<String, dynamic>? Function() getPendingRealismMetadata;
  final void Function(Map<String, dynamic>?) setPendingRealismMetadata;
  final Map<String, dynamic> Function({Map<String, int>? preTurn})
  captureRealismState;

  // Emotion scalars set by evals (1:1 + group speaker after impersonation)
  final String Function() getCharacterEmotion;
  final void Function(String) setCharacterEmotion;
  final String Function() getEmotionIntensity;
  final void Function(String) setEmotionIntensity;

  // Services for owned state (avoids duplicating scalars/cbs in god for this leaf)
  final RelationshipService relationshipService;

  // (Objective proposal + gen/check cbs moved to step 11 sibling leaf
  // objective_proposal.dart; getExpressionEnabled also dead post step10 move of
  // realism evals; onSaveChat dead post step11; cleaned here as part of task.
  // onNotify remains declared for now but will be audited; if unused after,
  // further hygiene in later.)

  /// Between-chunk hang guard for [fireLLMEval] streams. Injectable so tests
  /// can prove the guard without waiting out the production value.
  final Duration streamChunkTimeout;

  LlmEvalEngine({
    required this.getActiveCharacter,
    required this.getActiveGroup,
    required this.getIsObserverMode,
    required this.getUserName,
    required this.getRealismEnabled,
    required this.getMessages,
    this.fireToolEval,
    this.probe,
    this.getBackendIdentity,
    this.streamChunkTimeout = kEvalStreamChunkTimeout,
    required this.getLlmService,
    required this.getIsLocal,
    required this.getKoboldService,
    required this.reconnectIfAlive,
    required this.ensureServerIdle,
    required this.getIsCancellingRealismEval,
    required this.getRealismEvalCancelled,
    required this.getPendingRealismMetadata,
    required this.setPendingRealismMetadata,
    required this.captureRealismState,
    required this.getCharacterEmotion,
    required this.setCharacterEmotion,
    required this.getEmotionIntensity,
    required this.setEmotionIntensity,
    required this.relationshipService,
  });

  // ── Public surface (thins in god delegate here; used by tests + god) ──

  /// Shared helper: strip think blocks and extract text after them.
  /// (Central implementation; all &lt;think&gt; handling for evals + needs impact
  /// routes here. 2000 budget for gen/check paths now applied in step 11
  /// objective_proposal leaf via this strip cb passed from god thin.)
  String stripThinkBlocks(String text) {
    String cleaned = text
        .replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '')
        .trim();
    final unclosed = cleaned.indexOf('<think>');
    if (unclosed >= 0) {
      cleaned = cleaned.substring(0, unclosed).trim();
    }
    return cleaned;
  }

  /// Tiny helpers to deduplicate the ~20+ brittle RegExp patterns used
  /// to fish bool/int scalars out of the flat JSON-like strings returned by
  /// fireLLMEval across all Realism + Needs evaluation sites.
  int? extractJsonInt(String text, String key) {
    final m = RegExp(
      r'"' + RegExp.escape(key) + r'"\s*:\s*(-?\d+)',
    ).firstMatch(text);
    return m != null ? int.tryParse(m.group(1)!) : null;
  }

  bool? extractJsonBool(String text, String key) {
    final m = RegExp(
      r'"' + RegExp.escape(key) + r'"\s*:\s*(true|false)',
    ).firstMatch(text);
    return m != null ? (m.group(1) == 'true') : null;
  }

  /// Shared helper: fire a lightweight LLM eval call and return the raw response.
  ///
  /// No stop sequences (see implementation). We rely on the "ONLY the JSON" instruction
  /// in the eval prompts + temp 0.1 + the post-response strip + regex extractors.
  /// Old }\n stops were causing truncation / "stop string" problems when reason fields
  /// contained similar sequences or when models emitted compact JSON.
  /// Thinking models still produce &lt;think&gt; freely before JSON (handled by strip).
  /// (Post-0.9.8: regex-based; no GBNF.)
  Future<String?> fireLLMEval(
    String prompt, {
    void Function(String)? onChunk,
  }) async {
    final llm = getLlmService();
    // For remote backends, require full readiness (API key + model configured).
    // For local KoboldCPP: if state says not-running, do a live probe first —
    // the constructor probe is a best-effort fast path but can lose the race
    // against session load on hot restart. This on-demand probe is definitive.
    final bool effectiveIsLocal = getIsLocal();
    if (effectiveIsLocal) {
      final kobold = getKoboldService();
      if (kobold != null && !kobold.isProcessRunning) {
        // Probe takes ~2–5 ms if KoboldCPP is up, times out after 5 s if not.
        await reconnectIfAlive();
      }
      // After probe, if still not running the server genuinely isn't up.
      if (kobold != null && !kobold.isProcessRunning) return null;
      // If test override with local=true but no real kobold, we let it proceed
      // (caller is responsible for the fake being "ready").
    } else {
      if (!llm.isReady) return null;
    }

    final params = GenerationParams(
      prompt: prompt,
      maxLength: 4000,
      temperature: 0.1,
      repeatPenalty: 1.15,
      topP: 0.5,
      xtcProbability: 0.0,
      reasoningEnabled: false,
      // Force thinking OFF on remote ":thinking" models (Kimi K2.6, DeepSeek
      // hybrids, etc.): the reasoning-disable block is only sent when a
      // reasoning field is set, so evals must set this or the model reasons
      // through every eval — slow, costly, and a source of flaky/empty
      // structured replies. 0 → {enabled:false, max_tokens:0, exclude:true}.
      reasoningMaxTokens: 0,
      stopSequences: const [],
    );

    if (effectiveIsLocal) {
      final k = getKoboldService();
      if (k != null) await k.waitForIdle();
    }

    String response = '';
    // Retry loop: thinking models can cause KoboldCPP to drop the connection
    // briefly (OOM during dense thinking sessions). One retry after a short
    // pause is enough to recover without user-visible impact.
    for (int attempt = 0; attempt < 2; attempt++) {
      // If cancellation has been requested, abort before attempting a new stream
      if (getIsCancellingRealismEval() || getRealismEvalCancelled()) {
        debugPrint(
          '[Realism] evaluation cancelled before attempt ${attempt + 1}',
        );
        return null;
      }

      // If cancellation was requested, abort immediately
      if (getIsCancellingRealismEval()) {
        debugPrint('[Realism] eval cancelled before attempt ${attempt + 1}');
        return null;
      }
      if (attempt > 0) {
        debugPrint(
          '[Realism:Eval] Retrying after connection drop (attempt ${attempt + 1})...',
        );
        await Future.delayed(const Duration(seconds: 3));
        final bool retryIsLocal = getIsLocal();
        if (retryIsLocal) {
          final k = getKoboldService();
          if (k != null) {
            await ensureServerIdle();
          }
        }
        response = ''; // reset for clean retry
      }
      // If cancellation occurred during setup, bail out before streaming
      if (getIsCancellingRealismEval() || getRealismEvalCancelled()) {
        debugPrint('[Realism] eval cancelled before streaming');
        return null;
      }
      try {
        // Streaming loop with cancellation support. The between-chunk
        // timeout is the hang guard: a backend that accepts the request but
        // never streams (e.g. a server stalling on a cold model reload after
        // an idle unload — the oMLX "spinner forever" report) used to park
        // the eval — and its spinner — indefinitely, because retries only
        // trigger on thrown errors or completed-but-empty streams. A gap
        // longer than [kEvalStreamChunkTimeout] now throws into the existing
        // retry/give-up path instead, so a hung eval degrades to the same
        // silent fail-and-retry-next-interval the passes were designed for.
        bool cancelledDuringStream = false;
        await for (final chunk in llm
            .generateStream(params)
            .timeout(
              streamChunkTimeout,
              onTimeout: (sink) {
                sink.addError(
                  TimeoutException(
                    'eval stream: no chunk within '
                    '${streamChunkTimeout.inSeconds}s',
                  ),
                );
                sink.close();
              },
            )) {
          // If a cancellation has been requested, terminate streaming gracefully.
          if (getIsCancellingRealismEval()) {
            debugPrint('[Realism] streaming terminated via cancel');
            cancelledDuringStream = true;
            break;
          }
          response += chunk;
          onChunk?.call(chunk);
        }
        if (cancelledDuringStream) {
          // Return null to indicate cancellation to callers.
          debugPrint('[Realism] streaming terminated via cancel (early exit)');
          return null;
        }

        // Handle empty responses (common with local thinking models during <think> prefill).
        // Retry once after a short settle + idle wait. Critical for reliable manual
        // Needs reprocess and other evals on Kobold thinking setups.
        if (response.trim().isEmpty && attempt < 1) {
          debugPrint(
            '[Realism:Eval] Empty stream response, retrying after settle...',
          );
          await Future.delayed(const Duration(seconds: 2));
          if (effectiveIsLocal) await ensureServerIdle();
          response = '';
          continue;
        }

        // Ensure visual separation between concurrent eval outputs in stream display
        // (helps when multiple realism/impact calls are in flight).
        if (!response.endsWith('\n') && onChunk != null) {
          onChunk('\n');
          response += '\n';
        }

        break; // stream completed cleanly — exit retry loop
      } catch (e) {
        debugPrint('[Realism:Eval] Stream error on attempt ${attempt + 1}: $e');
        // Check if cancellation was requested during the error handling
        if (getIsCancellingRealismEval()) {
          debugPrint('[Realism] eval cancelled during error handling');
          return null;
        }
        if (attempt >= 1) {
          // Second failure — give up silently; don't surface to UI
          return null;
        }
        // else: fall through to retry
      }
    }

    // Log raw eval response for diagnostics
    final preview = response.length > 300
        ? response.substring(0, 300)
        : response;
    debugPrint(
      '[Realism:RawEval] len=${response.length} | ${preview.replaceAll('\n', '↵')}',
    );
    return response.isEmpty ? null : response;
  }

  // (generateObjectiveTasks excised; full impl + prompt/strip/parse/2000 now in
  // objective_proposal.dart step 11. Deletion part of task.)

  // (checkTaskCompletionInBackground excised; full body + logic moved to
  // objective_proposal.dart step 11. Deletion part of task.)
  // (check + gen excised to objective_proposal step 11; deletion part of task)
  // (all dangling body chunks removed; engine clean for step 11.)

  Future<String?> evaluateNeedsImpactCall(
    String responseText, {
    void Function(String)? onChunk,
    int strength =
        1, // 1-5; injected into the prompt so the model emits deltas at the user-requested magnitude on the *first* call (e.g. normal -3 becomes ~-15 at 5x). When Director authority is on, the verifier is also told the strength and corrects in the scaled space. The evaluator no longer post-multiplies after Director (avoids double-scaling a -15 into -75).
    String? userCritique,
    Map<String, int>? previousDeltas,
    Map<String, int>? currentNeeds,
    int? decayTurns,
  }) async {
    if (!getRealismEnabled()) return null;
    if (getActiveCharacter() == null && getActiveGroup() == null) return null;
    if (getActiveGroup() != null && getIsObserverMode()) {
      return null; // Director
    }

    final msgs = getMessages();
    final recentCount = msgs.length < 3 ? msgs.length : 3;
    final recent = msgs.reversed
        .take(recentCount)
        .toList()
        .reversed
        .map((m) => '${m.sender}: ${m.displayText}')
        .join('\n');

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

    // Shared climax-detection guidance, injected into BOTH the main and the
    // critique prompts. Without explicit criteria the model (especially a
    // reasoning/"thinking" model, which won't guess at an undefined field)
    // almost never sets is_climax=true, so the post-orgasm cooldown never fires
    // and the Lust/arousal bar stays pinned at the top. This mirrors the
    // "high arousal is NOT climax" rule the other realism evals already use
    // (see realism_evals.dart arousal instructions).
    final climaxGuidance =
        'CLIMAX DETECTION — "is_climax": Set this to true ONLY when $charName themselves reaches sexual orgasm / release in THIS scene — '
        'i.e. the text explicitly narrates their own climax (coming, finishing, a shuddering or spasming release, '
        'crying out as they tip over the edge, gushing/ejaculating, going limp or boneless right after the peak). '
        'High arousal, being "close", edging, begging, grinding, foreplay, or ONLY the partner/user climaxing are NOT a climax for '
        '$charName — leave "is_climax" false in those cases. '
        'When (and only when) "is_climax" is true, also emit "refractory_turns" as an int from 3 to 7 for how long the post-orgasm '
        'cooldown should last (~6-7 for an intense, drawn-out, or repeated climax; ~3 for a quick one). When false, set "refractory_turns" to 0.\n\n';

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

    String buildPrompt({required bool toolsMode}) {
      // The format sections below are the ONLY difference between the tools
      // and text transports — every guideline/magnitude line is shared, so
      // the two paths can never drift in what the model is told.
      final flatJsonAsk = toolsMode
          ? 'Report the result by calling the $kNeedsImpactTool tool. '
                'Use ONLY the tool — no plain-text reply.\n'
          : 'Respond with ONLY a flat JSON object. Do NOT use markdown code blocks — return raw JSON only:\n'
                '{"activities": ["sexual", "self_touch", "messy", "dominance" or similar], '
                '"intensity": 1-10, '
                '"hunger_delta": <int>, "energy_delta": <int>, "hygiene_delta": <int>, "fun_delta": <int>, "social_delta": <int>, "bladder_delta": <int>, "comfort_delta": <int>, ';
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
          'Even if the critique suggests little/no change, you MUST output the complete flat JSON with all seven _delta keys (0 is valid). Do not omit fields.\n\n'
          'MAGNITUDE: needs run 0–100 (100 = fully satisfied); ±8 BARELY registers. When the scene SATISFIES/RESTORES a need, use a LARGE positive delta so it actually fills — using the bathroom → bladder +60 to +100; a full meal → hunger +50 to +90; sleeping / a long rest → energy +60 to +100; cozy solitude, lounging, drowsing → comfort +20 to +45, energy +10 to +30; a thorough wash → hygiene +50 to +90. Reserve small numbers for incidental effects, never a complete relief. (1x baselines; scale by the strength above.)\n\n'
          'Examples of valid correction output:\n'
          '{"hunger_delta": 8, "energy_delta": 0, "hygiene_delta": -2, "fun_delta": 5, "social_delta": 0, "bladder_delta": 0, "comfort_delta": 1, "reason": "ate snack per critique", "is_climax": false, "refractory_turns": 0}\n'
          '{"hunger_delta": 0, "energy_delta": 0, "hygiene_delta": 0, "fun_delta": 0, "social_delta": 0, "bladder_delta": 0, "comfort_delta": 0, "reason": "no notable need impact", "is_climax": false, "refractory_turns": 0}\n'
          '{"hunger_delta": 0, "energy_delta": -12, "hygiene_delta": -10, "fun_delta": 25, "social_delta": 10, "bladder_delta": 0, "comfort_delta": 8, "reason": "$charName climaxed during sex", "is_climax": true, "refractory_turns": 6}\n\n' +
          climaxGuidance +
          flatJsonAsk +
          (toolsMode
              ? ''
              : '"reason": "<brief grounded reason for the deltas incorporating the critique>", '
                  '"is_climax": true/false, "refractory_turns": <int 3-7 when is_climax is true, else 0> }');
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
            climaxGuidance +
            flatJsonAsk +
            (toolsMode
                ? 'If the scene had little or no notable effect on needs, use small numbers or zeros and a short reason.'
                : '"reason": "<brief grounded reason for the deltas>", '
                      '"is_climax": true/false, "refractory_turns": <int 3-7 when is_climax is true, else 0> }\n'
                      'Example when $charName climaxes: {"activities": ["sexual"], "intensity": 9, "hunger_delta": 0, "energy_delta": -12, "hygiene_delta": -10, "fun_delta": 25, "social_delta": 10, "bladder_delta": 0, "comfort_delta": 8, "reason": "$charName came hard during sex", "is_climax": true, "refractory_turns": 6}\n'
                      'If the scene had little or no notable effect on needs, use small numbers or zeros and a short reason.');
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
      final raw = fireToolEval != null && probe != null
          ? await fireStructuredEval(
              probe: probe!,
              backendIdentity: getBackendIdentity?.call() ?? '',
              debugLabel: kNeedsImpactTool,
              tools: kNeedsImpactEvalTools,
              buildPrompt: buildPrompt,
              callToText: (resp) =>
                  realismToolCallToJson(kNeedsImpactTool, resp.calls),
              fireToolEval: fireToolEval!,
              fireTextEval: fireLLMEval,
              isCancelled: () =>
                  getIsCancellingRealismEval() || getRealismEvalCancelled(),
              onChunk: onChunk,
            )
          : await fireLLMEval(buildPrompt(toolsMode: false), onChunk: onChunk);
      if (raw == null) return null;
      final searchText = stripThinkBlocks(raw);
      if (searchText.trim().isEmpty) return null;
      return searchText;
    } catch (e) {
      debugPrint('[Realism:Needs] Engine impact call failed: $e');
      return null;
    }
  }
}
