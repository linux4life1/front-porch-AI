// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Fused one-shot (`report_realism`) fire. Not [fireStructuredEval]:
// after a tools miss that helper opens the eval text lane with
// salvageReasoning, which on mandatory-reasoning models becomes
// max_tokens 4000+16000. The model writes a think novel; the
// between-chunk hang guard never trips; the chat spinner sits for
// minutes. This path retries tools (forced tool_choice), then a tight
// no-headroom text stream that stops at the first schema-complete JSON,
// then recovery tools. A second JSON-only text call runs only if the
// stream aborted (think-dump / wall-clock). Honest empty does not fire
// a second LLM text call. Deltas still apply whenever any attempt
// returns JSON — never skip the turn.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/chat/eval_stream_guards.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/chat/tool_eval_spec.dart';
import 'package:front_porch_ai/services/services.dart'
    show LlmToolResponse, isToolTransportFailure;

/// Result of one tight text stream. [aborted] is think-dump / wall-clock
/// (recovery-text may still run). Honest empty / backend-down is not
/// aborted — do not fire a second LLM text call.
class FusedTextAttempt {
  const FusedTextAttempt._(this.text, this.aborted);
  const FusedTextAttempt.ok(String text) : this._(text, false);
  const FusedTextAttempt.empty() : this._(null, false);
  const FusedTextAttempt.aborted() : this._(null, true);

  final String? text;
  final bool aborted;

  bool get hasJson => text != null && text!.trim().isNotEmpty;
}

FusedTextAttempt fusedTextFromRaw(String? raw, {bool aborted = false}) {
  if (aborted) return const FusedTextAttempt.aborted();
  if (raw == null || raw.trim().isEmpty) return const FusedTextAttempt.empty();
  return FusedTextAttempt.ok(raw);
}

/// Tight text attempt used by [fireFusedRealismEval]. [wallClockTimeout]
/// is the remaining fused budget — not a second 20k think hose.
typedef FusedTightTextEval =
    Future<FusedTextAttempt> Function(
      String prompt, {
      void Function(String)? onChunk,
      Duration? wallClockTimeout,
    });

Future<String?> fireFusedRealismEval({
  required ToolTransportProbe probe,
  required String backendIdentity,
  required String debugLabel,
  required List<Map<String, dynamic>> tools,
  required String Function({required bool toolsMode}) buildPrompt,
  required String? Function(LlmToolResponse resp) callToText,
  required Object fireToolEval,
  required FusedTightTextEval fireTightText,
  bool Function()? isCancelled,
  void Function(String)? onChunk,
  String? toolChoice,
  int maxLength = kScalarToolMaxTokens,
  double repeatPenalty = kScalarToolRepeatPenalty,
  bool Function()? getPreferTextEvals,
  Duration budget = kFusedEvalBudget,
}) async {
  final sw = Stopwatch()..start();
  final preferText = getPreferTextEvals?.call() ?? false;

  String? salvage(LlmToolResponse resp) {
    final text = callToText(resp);
    if (text != null) return text;
    return usableEvalJsonText(
          resp.text,
          tools: tools,
          toolChoice: toolChoice,
          callToText: callToText,
        ) ??
        usableEvalJsonText(
          resp.reasoning,
          tools: tools,
          toolChoice: toolChoice,
          callToText: callToText,
        );
  }

  Future<LlmToolResponse?> toolsOnce(String why) async {
    final wait = remainingBudget(sw, budget);
    if (wait == Duration.zero) {
      debugPrint(
        '[Realism] wall-clock abort ${sw.elapsedMilliseconds} ms ($why)',
      );
      return null;
    }
    debugPrint('[Eval:Tools] $debugLabel $why');
    onChunk?.call('⏳ $debugLabel…\n');
    try {
      return await invokeToolEval(
        fireToolEval,
        ToolEvalSpec(
          prompt: buildPrompt(toolsMode: true),
          tools: tools,
          toolChoice: toolChoice,
          maxLength: maxLength,
          repeatPenalty: repeatPenalty,
          onChunk: onChunk,
        ),
      ).timeout(wait);
    } on TimeoutException {
      debugPrint(
        '[Realism] wall-clock abort ${sw.elapsedMilliseconds} ms ($why)',
      );
      return null;
    } catch (e) {
      debugPrint('[Eval:Tools] $debugLabel $why failed: $e');
      if (isCancelled?.call() ?? false) return null;
      if (!isToolTransportFailure(e)) {
        probe.markXmlOnly(backendIdentity);
      } else {
        probe.noteInconclusive(backendIdentity);
      }
      return null;
    }
  }

  String? take(LlmToolResponse? resp) {
    if (resp == null) return null;
    if (isCancelled?.call() ?? false) return null;
    final got = salvage(resp);
    if (got != null) {
      probe.markSupported(backendIdentity);
      onChunk?.call('$got\n');
      return got;
    }
    if (resp.isUnusableNativeToolCall) {
      debugPrint(
        '[Eval:Tools] $debugLabel empty tool_calls — unusable, retry tools',
      );
      probe.noteInconclusive(backendIdentity);
      return null;
    }
    if (resp.text.trim().isNotEmpty || resp.reasoning.trim().isNotEmpty) {
      debugPrint(
        '[Eval:Tools] $debugLabel returned prose or incomplete JSON — '
        'retrying tools (forced $toolChoice), not the text think hose',
      );
    }
    probe.noteInconclusive(backendIdentity);
    return null;
  }

  Future<FusedTextAttempt> tightText(String prompt, String why) async {
    final wait = remainingBudget(sw, budget);
    if (wait == Duration.zero) {
      debugPrint(
        '[Realism] wall-clock abort ${sw.elapsedMilliseconds} ms ($why)',
      );
      return const FusedTextAttempt.aborted();
    }
    debugPrint('[Eval:Tools] $debugLabel tight text ($why)');
    return fireTightText(prompt, onChunk: onChunk, wallClockTimeout: wait);
  }

  if (!preferText &&
      probe.shouldFireTools(backendIdentity, preferTextEvals: preferText)) {
    final first = take(await toolsOnce('tools'));
    if (first != null) return first;
    if (isCancelled?.call() ?? false) return null;
    // Harder tools: one forced retry before any text stream.
    final retry = take(await toolsOnce('tools-retry'));
    if (retry != null) return retry;
    if (isCancelled?.call() ?? false) return null;
  } else if (preferText) {
    debugPrint('[Eval:Tools] skipping (override) on $backendIdentity');
  }

  final textPrompt = buildPrompt(toolsMode: false);
  final streamed = await tightText(textPrompt, 'after-tools');
  if (streamed.hasJson) return streamed.text;
  if (isCancelled?.call() ?? false) return null;

  debugPrint(
    '[Eval:Tools] $debugLabel recovering after abort/empty — tools then '
    'tight JSON (${sw.elapsedMilliseconds} ms so far)',
  );
  final recovered = take(await toolsOnce('recovery-tools'));
  if (recovered != null) return recovered;
  if (isCancelled?.call() ?? false) return null;

  // Honest completed-null (backend down / empty reply): the first text
  // call already finished. A second fireLLMEval would invent a second
  // fused evaluation (one_shot_parity pins length == 1). Think-dump /
  // wall-clock abort still gets a JSON-only follow-up so the turn is
  // not left without deltas.
  if (!streamed.aborted) return null;

  final jsonOnly =
      '$textPrompt\n\nReply with ONLY the JSON object. No analysis.';
  final last = await tightText(jsonOnly, 'recovery-text');
  return last.hasJson ? last.text : null;
}
