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

import 'package:front_porch_ai/services/reasoning_effort.dart';
import 'package:front_porch_ai/services/tool_choice_style_probe.dart';

/// True when [apiUrl] is OpenRouter's public API, not Nano-GPT / oMLX /
/// LM Studio / a LAN OpenAI-compatible host.
bool isOpenRouterApiUrl(String apiUrl) {
  final host = Uri.tryParse(apiUrl.trim())?.host.toLowerCase();
  return host == 'openrouter.ai' || (host?.endsWith('.openrouter.ai') ?? false);
}

/// Floor for OpenRouter structured / tool evals. Scalar judges used 512
/// tokens; thinking endpoints spend that budget on the think and return
/// empty `content` / `tool_calls` with `finish_reason=length`.
const int kOpenRouterStructuredEvalMinTokens = 4000;

/// Named evals and think-off tool calls (Journal / judges). Waifu keeps
/// `reasoning.enabled` + `max_tokens` and must not inherit the 4000 floor.
bool shouldApplyOpenRouterEvalToolRouting({
  required bool reasoningEnabled,
  int? reasoningMaxTokens,
  String? toolChoice,
}) {
  if (askedToDisableThinking(
    reasoningEnabled: reasoningEnabled,
    reasoningMaxTokens: reasoningMaxTokens,
  )) {
    return true;
  }
  return toolChoice != null &&
      toolChoice.isNotEmpty &&
      toolChoice != kToolChoiceRequired;
}

/// Strip OR-hostile optional samplers, require the params on THIS request,
/// and raise a 512-token judge budget so a think cannot starve the call.
///
/// Thinking-on tool loops (Waifu) must keep `reasoning` and must not inherit
/// the eval floor — that cap is a think budget on GLM 5.3. Callers should
/// skip this helper via [shouldApplyOpenRouterEvalToolRouting]; this is the
/// same gate if someone still passes a live-think payload in.
Map<String, dynamic> applyOpenRouterToolRouting(
  Map<String, dynamic> payload, {
  required bool mandatoryReasoning,
}) {
  final reasoning = payload['reasoning'];
  if (reasoning is Map && reasoning['enabled'] == true) {
    return Map<String, dynamic>.from(payload);
  }
  final next = Map<String, dynamic>.from(payload)
    ..remove('repetition_penalty')
    ..remove('min_p')
    ..remove('top_k')
    // `reasoning` + `require_parameters` only routes to thinking
    // endpoints — the same class that ignores forced tool_choice.
    ..remove('reasoning')
    ..['provider'] = {'require_parameters': true};
  _floorOpenRouterEvalTokens(next, mandatoryReasoning: mandatoryReasoning);
  return next;
}

void _floorOpenRouterEvalTokens(
  Map<String, dynamic> payload, {
  required bool mandatoryReasoning,
}) {
  var floor = kOpenRouterStructuredEvalMinTokens;
  if (mandatoryReasoning) {
    floor += kMandatoryReasoningThinkHeadroomTokens;
  }
  final current = payload['max_tokens'];
  if (current is! num || current < floor) payload['max_tokens'] = floor;
}
