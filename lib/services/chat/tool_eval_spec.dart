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

import 'package:front_porch_ai/services/llm_service.dart' show LlmToolResponse;

/// Eval-sized `GenerationParams.maxLength` for scalar `report_*` tool
/// calls. Frozen for the tools-transport work: a relationship object is
/// tens of tokens; 512 is 5–10× headroom. Journal/Growth keep 4000.
const int kScalarToolMaxTokens = 512;

/// Ping budget. The capability probe wants one function and ~10 tokens.
const int kPingToolMaxTokens = 64;

/// Journal / Growth keep the chat-sized budget (a large window can
/// legitimately prefill slowly, and zero calls is a valid honest empty).
const int kProseToolMaxTokens = 4000;

/// Repeat penalty for scalar JSON evals (mirrors
/// `kScalarEvalRepeatPenalty`). Journal/Growth keep 1.15.
const double kScalarToolRepeatPenalty = 1.0;

/// Repeat penalty for Journal / Growth prose tool calls.
const double kProseToolRepeatPenalty = 1.15;

/// Default for optional `getPreferTextEvals` callbacks — tear-off is const.
bool preferTextEvalsOff() => false;

/// Default for optional `getPassEpoch` — a constant 0 never goes stale, so
/// unit tests that don't simulate regen keep the XML-fallback behaviour.
int passEpochNeverStale() => 0;

/// In-flight tool-eval request. Carries `toolChoice` as an argument so the
/// three staggered judges cannot race a ChatService field, and so a shared
/// `tools` list cannot silently name `tools.first`.
class ToolEvalSpec {
  final String prompt;
  final List<Map<String, dynamic>> tools;

  /// Null → `'auto'` (Journal/Growth). Non-null → named function.
  final String? toolChoice;
  final int maxLength;
  final double repeatPenalty;
  final void Function(String chunk)? onChunk;

  const ToolEvalSpec({
    required this.prompt,
    required this.tools,
    this.toolChoice,
    this.maxLength = kProseToolMaxTokens,
    this.repeatPenalty = kProseToolRepeatPenalty,
    this.onChunk,
  });
}

/// Production door: `(ToolEvalSpec)`. Existing tests still pass
/// `(String prompt, List tools)` — [invokeToolEval] accepts both so
/// test-integrity does not have to rewrite every `(p, t)` closure.
typedef FireToolEval = Future<LlmToolResponse?> Function(ToolEvalSpec spec);

typedef LegacyFireToolEval =
    Future<LlmToolResponse?> Function(
      String prompt,
      List<Map<String, dynamic>> tools,
    );

/// Dispatch a dual-accept tools callback. Production tear-offs of
/// `_fireToolEval(ToolEvalSpec)` hit [FireToolEval]; existing test
/// closures hit the two-arg fallback.
Future<LlmToolResponse?> invokeToolEval(
  Object fireToolEval,
  ToolEvalSpec spec,
) async {
  if (fireToolEval is FireToolEval) return fireToolEval(spec);
  if (fireToolEval is LegacyFireToolEval) {
    return fireToolEval(spec.prompt, spec.tools);
  }
  final fn = fireToolEval as Function;
  try {
    final r = Function.apply(fn, [spec]);
    return await (r as Future<LlmToolResponse?>);
  } catch (_) {
    final r = Function.apply(fn, [spec.prompt, spec.tools]);
    return await (r as Future<LlmToolResponse?>);
  }
}
