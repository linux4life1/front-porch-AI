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
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/eval_traffic.dart';
import 'package:front_porch_ai/services/chat/needs_impact_zero.dart';
import 'package:front_porch_ai/services/chat/needs_simulation.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/chat/realism_tools.dart';
import 'package:front_porch_ai/services/chat/relationship_service.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/reasoning_markers.dart';

/// Hang guard for eval streams: the maximum gap between streamed chunks
/// before the attempt is treated as dead (covers the first token too, so a
/// backend stalling on a cold model reload — or holding a request in a queue
/// forever — can't park an eval and its spinner indefinitely). Generous on
/// purpose: slow local prefill on a big journal window must still fit.
const Duration kEvalStreamChunkTimeout = Duration(seconds: 180);

/// Settle before retrying a completed-but-empty eval stream. Local thinking
/// models often return nothing during `<think>` prefill; this pause plus an
/// idle wait is usually enough. Injectable so tests do not wait out 2s.
const Duration kEvalEmptyStreamSettle = Duration(seconds: 2);

/// Pause after a thrown stream error before the one retry. Separate from
/// [kEvalEmptyStreamSettle]: empty is not a connection drop. Injectable so
/// tests do not wait out 3s.
const Duration kEvalConnectionDropSettle = Duration(seconds: 3);

/// Hang guard for the non-streaming tools-transport call (the journal/
/// realism tool calls and the one-shot capability probe). Whole-call
/// deadline, so it must cover a full slow-hardware generation — a timed-out
/// PROBE merely marks the backend XML-only for the run (text path floor,
/// which carries its own chunk timeout).
const Duration kEvalToolCallTimeout = Duration(minutes: 6);

/// Repeat penalty for the SCALAR JSON evals (realism judges, needs impact,
/// scene time, posture, climax, pockets, reply-facts, cast detect, guest
/// gate, Director critique). Repeat penalty punishes exactly the tokens
/// structured output must repeat — quotes, braces, seven `*_delta` keys — a
/// known distorter of long JSON, and at temp 0.1 it buys nothing (eval
/// review Tier-1 §3.6). The prose-emitting passes (Journal cards + recap,
/// Growth rings, Dreams, task generation) deliberately KEEP
/// [fireLLMEval]'s 1.15 default, where the penalty still earns its keep
/// against low-temperature repetition loops.
const double kScalarEvalRepeatPenalty = 1.0;

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
  final Object? fireToolEval;
  final ToolTransportProbe? probe;
  final String Function()? getBackendIdentity;
  final bool Function()? getPreferTextEvals;

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

  /// See [kEvalEmptyStreamSettle].
  final Duration emptyStreamSettle;

  /// See [kEvalConnectionDropSettle].
  final Duration connectionDropSettle;

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
    this.getPreferTextEvals,
    this.streamChunkTimeout = kEvalStreamChunkTimeout,
    this.emptyStreamSettle = kEvalEmptyStreamSettle,
    this.connectionDropSettle = kEvalConnectionDropSettle,
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
    double repeatPenalty = 1.15,
    // For the [EvalTraffic] tally only. Coarse where a closure is shared
    // (the realism judges + scene time all ride one wiring closure as
    // 'realism'; their per-kind detail is in the [Realism:*] logs), precise
    // where a pass has its own closure.
    String label = 'eval',
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
      repeatPenalty: repeatPenalty,
      topP: 0.5,
      xtcProbability: 0.0,
      reasoningEnabled: false,
      // Force thinking OFF on remote ":thinking" models (Kimi K2.6, DeepSeek
      // hybrids, etc.): the reasoning-disable block is only sent when a
      // reasoning field is set, so evals must set this or the model reasons
      // through every eval — slow, costly, and a source of flaky/empty
      // structured replies. 0 → {enabled:false, max_tokens:0, exclude:true}.
      reasoningMaxTokens: 0,
      // Mandatory-reasoning models park the JSON in the think channel.
      // Salvage it; exclude:true would drop it (Kimi 2.6, 2026-08-15).
      salvageReasoning: true,
      stopSequences: const [],
    );

    if (effectiveIsLocal) {
      final k = getKoboldService();
      if (k != null) await k.waitForIdle();
    }

    final trafficWatch = Stopwatch()..start();
    String response = '';
    // Retry loop: one extra attempt. Empty completed streams retry only on
    // a local backend (thinking-model <think> prefill). Thrown stream errors
    // retry after [connectionDropSettle] on any backend (the oMLX hang
    // guard). The empty path used to `continue` into the drop delay as well,
    // so every unmatched ScriptedLlm eval stalled 5s.
    for (int attempt = 0; attempt < 2; attempt++) {
      if (getIsCancellingRealismEval() || getRealismEvalCancelled()) {
        debugPrint(
          '[Realism] evaluation cancelled before attempt ${attempt + 1}',
        );
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
        await for (final chunk
            in llm
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
          if (getIsCancellingRealismEval() || getRealismEvalCancelled()) {
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

        // Empty completed stream: common with local thinking models during
        // <think> prefill. Remote APIs and test fakes returning "" is a real
        // empty — retrying them is how With-you (and any other unmatched
        // eval) stalled every ScriptedLlm chat test 5s per call.
        if (response.trim().isEmpty && attempt < 1) {
          if (getIsCancellingRealismEval() || getRealismEvalCancelled()) {
            debugPrint('[Realism] eval cancelled on empty stream; no retry');
            return null;
          }
          if (!effectiveIsLocal) {
            debugPrint(
              '[Realism:Eval] Empty stream on non-local backend; no retry',
            );
            break;
          }
          debugPrint(
            '[Realism:Eval] Empty stream response, retrying after settle...',
          );
          await Future.delayed(emptyStreamSettle);
          await ensureServerIdle();
          response = '';
          continue;
        }

        // Ensure visual separation between concurrent eval outputs in stream display
        // (helps when multiple realism/impact calls are in flight).
        if (!response.endsWith('\n') && onChunk != null) {
          onChunk('\n');
          response += '\n';
        }

        if (getIsCancellingRealismEval() || getRealismEvalCancelled()) {
          debugPrint('[Realism] eval cancelled after stream; drop live apply');
          return null;
        }
        break; // stream completed cleanly — exit retry loop
      } catch (e) {
        debugPrint('[Realism:Eval] Stream error on attempt ${attempt + 1}: $e');
        // Check if cancellation was requested during the error handling
        if (getIsCancellingRealismEval() || getRealismEvalCancelled()) {
          debugPrint('[Realism] eval cancelled during error handling');
          return null;
        }
        if (attempt >= 1) {
          // Second failure — give up silently; don't surface to UI
          return null;
        }
        debugPrint(
          '[Realism:Eval] Retrying after connection drop (attempt ${attempt + 2})...',
        );
        await Future.delayed(connectionDropSettle);
        if (getIsLocal()) {
          final k = getKoboldService();
          if (k != null) await ensureServerIdle();
        }
        response = '';
      }
    }

    // Log raw eval response for diagnostics
    final preview = response.length > 300
        ? response.substring(0, 300)
        : response;
    debugPrint(
      '[Realism:RawEval] len=${response.length} | ${preview.replaceAll('\n', '↵')}',
    );
    EvalTraffic.current.record(
      label: label,
      lane: 'text',
      promptChars: prompt.length,
      outputChars: response.length,
      ms: trafficWatch.elapsedMilliseconds,
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
                // narration as evidence she had BECOME hungrier. Describing a
                // state was being scored as changing it, and the lower a need
                // went the more vivid the prose and the harder the next hit.
                //
                // CLAUDE.md already forbids this for the Realism Engine — "the
                // eval scores the USER's message, never the character's own
                // reply" — and the rule had simply never been applied here.
                'DEPLETION IS HANDLED SEPARATELY. Needs drift downward on their own every turn; '
                'that is already accounted for and is not your job. The scene text above was WRITTEN FROM '
                'the current needs listed below — a character mentioning her empty stomach, dragging her feet, '
                'or squirming is DESCRIBING the state you are being shown, not becoming worse. Do not charge '
                'her for it.\n'
                'Report a NEGATIVE delta only when the scene explicitly describes something that COST her: '
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
                ? 'Individual needs may be 0. All seven 0 is a failed eval — score what the beat did to her body and mood.'
                : '"reason": "<brief grounded reason for the deltas>" }\n'
                      'Individual needs may be 0. All seven 0 is a failed eval — score what the beat did to her body and mood.');
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
