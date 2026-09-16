// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Guards for eval text streams: wall-clock, open-think dump, early JSON.

import 'package:front_porch_ai/services/chat/eval_json_merge.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Hard wall-clock for one fused-eval text attempt. Between-chunk silence
/// is a different guard ([kEvalStreamChunkTimeout]); this one trips while
/// tokens keep arriving. 75s stays under the ~90s chat-turn target.
const Duration kEvalWallClockTimeout = Duration(seconds: 75);

/// Whole fused one-shot (`report_realism`) budget including tools retries
/// and recovery. The turn must not sit on the Realism spinner for minutes.
const Duration kFusedEvalBudget = Duration(seconds: 75);

/// Open `<think>` (after canonicalize) past this many characters with no
/// extractable JSON → abort that stream and recover. Do not wait for
/// max_tokens. 7k is inside the 6–8k band.
const int kEvalThinkDumpCharCap = 7000;

/// Tight text / recovery `maxLength`. No mandatory-reasoning 16k headroom.
/// Scalar tool calls already live at 512.
const int kEvalRecoveryMaxLength = 512;

/// Characters inside the last still-open think fence, or 0 if none / closed.
int openThinkBodyChars(String raw) {
  if (raw.isEmpty) return 0;
  final canon = canonicalizeReasoning(raw);
  final openAt = canon.lastIndexOf('<think>');
  if (openAt < 0) return 0;
  final closeAt = canon.indexOf('</think>', openAt);
  if (closeAt >= 0) return 0;
  return canon.length - (openAt + '<think>'.length);
}

/// True when an open think fence has blown [cap] and no JSON object is
/// visible yet (closed-think tails are stripped first).
bool thinkDumpExceeded(
  String raw, {
  int cap = kEvalThinkDumpCharCap,
  String Function(String)? stripThink,
}) {
  if (openThinkBodyChars(raw) < cap) return false;
  final cleaned = stripThink != null ? stripThink(raw) : _stripClosedThink(raw);
  return parseEvalJsonObject(cleaned) == null;
}

String _stripClosedThink(String text) {
  var cleaned = canonicalizeReasoning(
    text,
  ).replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '').trim();
  final unclosed = cleaned.indexOf('<think>');
  if (unclosed >= 0) {
    cleaned = cleaned.substring(0, unclosed).trim();
  }
  return cleaned;
}

Duration remainingBudget(Stopwatch sw, Duration budget) {
  final left = budget - sw.elapsed;
  return left.isNegative ? Duration.zero : left;
}
