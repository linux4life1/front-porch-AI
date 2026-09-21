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
import 'package:front_porch_ai/services/chat/eval_json_merge.dart';
import 'package:front_porch_ai/services/chat/eval_lane_params.dart';
import 'package:front_porch_ai/services/chat/eval_stream_guards.dart';
import 'package:front_porch_ai/services/chat/eval_traffic.dart';
import 'package:front_porch_ai/services/chat/needs_impact_zero.dart';
import 'package:front_porch_ai/services/chat/needs_simulation.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/chat/realism_tools.dart';
import 'package:front_porch_ai/services/chat/relationship_service.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/reasoning_markers.dart';

part 'llm_eval_extract.dart';

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

class LlmEvalEngine {
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

  /// Optional whole-call cap. Null = no wall-clock (chunk timeout only).
  /// Fused one-shot passes the remaining [kFusedEvalBudget].
  final Duration? wallClockTimeout;

  /// Open-think dump cap. Null = [kEvalThinkDumpCharCap].
  final int thinkDumpCharCap;

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
    this.wallClockTimeout,
    this.thinkDumpCharCap = kEvalThinkDumpCharCap,
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

  /// Shared helper: strip think blocks and extract text after them.
  /// (Central implementation; all &lt;think&gt; handling for evals + needs impact
  /// routes here. 2000 budget for gen/check paths now applied in step 11
  /// objective_proposal leaf via this strip cb passed from god thin.)
  String stripThinkBlocks(String text) => stripEvalThinkBlocks(text);

  /// The scalar extractors every Realism + Needs eval site uses. The bodies
  /// live in eval_json_merge.dart so a caller that only needs the regex does
  /// not have to construct this engine; these stay as the wired-callback door.
  int? extractJsonInt(String text, String key) => evalJsonInt(text, key);

  bool? extractJsonBool(String text, String key) => evalJsonBool(text, key);

  Future<String?> evaluateNeedsImpactCall(
    String responseText, {
    void Function(String)? onChunk,
    int strength = 1,
    String? userCritique,
    Map<String, int>? previousDeltas,
    Map<String, int>? currentNeeds,
    int? decayTurns,
    Set<String> onlyNeeds = const {},
  }) => _evaluateNeedsImpactCall(
    responseText,
    onChunk: onChunk,
    strength: strength,
    userCritique: userCritique,
    previousDeltas: previousDeltas,
    currentNeeds: currentNeeds,
    decayTurns: decayTurns,
    onlyNeeds: onlyNeeds,
  );

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
    double repeatPenalty = kEvalLaneRepeatPenalty,
    // For the [EvalTraffic] tally only. Coarse where a closure is shared
    // (the realism judges + scene time all ride one wiring closure as
    // 'realism'; their per-kind detail is in the [Realism:*] logs), precise
    // where a pass has its own closure.
    String label = 'eval',
    bool salvageReasoning = true,
    int? maxLength,
    Duration? wallClockTimeout,
    int? thinkDumpCharCap,
    bool Function(String accumulated)? stopWhen,
    bool abortClientOnStop = false,
    void Function()? onGuardAbort,
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

    // Shared eval-lane block. Fused one-shot recovery passes
    // salvageReasoning:false and a tight [maxLength] so we never open
    // the 4000+16000 think hose. Default salvage stays ON for other evals.
    final params = evalLaneParams(
      prompt: prompt,
      repeatPenalty: repeatPenalty,
      salvageReasoning: salvageReasoning,
      maxLength: maxLength ?? kEvalLaneMaxLength,
    );
    final wallLimit = wallClockTimeout ?? this.wallClockTimeout;
    final dumpCap = thinkDumpCharCap ?? this.thinkDumpCharCap;
    bool jsonReady(String acc) {
      if (stopWhen != null) return stopWhen(acc);
      return parseEvalJsonObject(stripThinkBlocks(acc)) != null;
    }

    if (effectiveIsLocal) {
      final k = getKoboldService();
      if (k != null) await k.waitForIdle();
    }

    final trafficWatch = Stopwatch()..start();
    String response = '';
    var guardAbort = false;
    // Retry loop: one extra attempt. Empty completed streams retry only on
    // a local backend (thinking-model <think> prefill). Thrown stream errors
    // retry after [connectionDropSettle] on any backend (the oMLX hang
    // guard). The empty path used to `continue` into the drop delay as well,
    // so every unmatched ScriptedLlm eval stalled 5s.
    // Think-dump / wall-clock do NOT retry — the fused caller recovers.
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
        var earlyJson = false;
        final slice = () {
          if (wallLimit == null) return streamChunkTimeout;
          final left = remainingBudget(trafficWatch, wallLimit);
          return left < streamChunkTimeout ? left : streamChunkTimeout;
        }();
        if (slice == Duration.zero) {
          debugPrint(
            '[Realism] wall-clock abort ${trafficWatch.elapsedMilliseconds} ms',
          );
          guardAbort = true;
          break;
        }
        await for (final chunk
            in llm
                .generateStream(params)
                .timeout(
                  slice,
                  onTimeout: (sink) {
                    final wall =
                        wallLimit != null && trafficWatch.elapsed >= wallLimit;
                    sink.addError(
                      TimeoutException(
                        wall
                            ? 'eval stream: wall-clock '
                                  '${trafficWatch.elapsedMilliseconds} ms'
                            : 'eval stream: no chunk within '
                                  '${slice.inMilliseconds}ms',
                      ),
                    );
                    sink.close();
                  },
                )) {
          if (getIsCancellingRealismEval() || getRealismEvalCancelled()) {
            debugPrint('[Realism] streaming terminated via cancel');
            cancelledDuringStream = true;
            break;
          }
          if (wallLimit != null && trafficWatch.elapsed >= wallLimit) {
            debugPrint(
              '[Realism] wall-clock abort ${trafficWatch.elapsedMilliseconds} ms',
            );
            guardAbort = true;
            break;
          }
          response += chunk;
          if (jsonReady(response)) {
            earlyJson = true;
            onChunk?.call(chunk);
            break;
          }
          if (thinkDumpExceeded(
            response,
            cap: dumpCap,
            stripThink: stripThinkBlocks,
          )) {
            debugPrint(
              '[Realism] think-dump abort chars=${response.length} '
              'ms=${trafficWatch.elapsedMilliseconds}',
            );
            guardAbort = true;
            break;
          }
          onChunk?.call(chunk);
        }
        if (cancelledDuringStream) {
          debugPrint('[Realism] streaming terminated via cancel (early exit)');
          return null;
        }
        if (guardAbort) {
          if (abortClientOnStop) {
            try {
              llm.abortGeneration();
            } catch (e) {
              debugPrint('[Realism] abortGeneration after guard: $e');
            }
          }
          break;
        }
        if (earlyJson && abortClientOnStop) {
          try {
            llm.abortGeneration();
          } catch (e) {
            debugPrint('[Realism] abortGeneration after JSON: $e');
          }
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
        if (getIsCancellingRealismEval() || getRealismEvalCancelled()) {
          debugPrint('[Realism] eval cancelled during error handling');
          return null;
        }
        final wall =
            wallLimit != null &&
            (trafficWatch.elapsed >= wallLimit ||
                e.toString().contains('wall-clock'));
        if (wall) {
          debugPrint(
            '[Realism] wall-clock abort ${trafficWatch.elapsedMilliseconds} ms',
          );
          guardAbort = true;
          if (abortClientOnStop) {
            try {
              llm.abortGeneration();
            } catch (err) {
              debugPrint('[Realism] abortGeneration after wall-clock: $err');
            }
          }
          break;
        }
        if (attempt >= 1) {
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
    if (guardAbort) {
      onGuardAbort?.call();
      return null;
    }
    return response.isEmpty ? null : response;
  }
}
