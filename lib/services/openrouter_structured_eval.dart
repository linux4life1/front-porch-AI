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

import 'package:front_porch_ai/services/chat/eval_json_merge.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/reasoning_effort.dart';

/// True when [apiUrl] is OpenRouter's public API, not Nano-GPT / oMLX /
/// LM Studio / a LAN OpenAI-compatible host.
bool isOpenRouterApiUrl(String apiUrl) {
  final host = Uri.tryParse(apiUrl.trim())?.host.toLowerCase();
  return host == 'openrouter.ai' || (host?.endsWith('.openrouter.ai') ?? false);
}

/// Floor for OpenRouter `response_format` evals. Forced-tool judges used
/// 512 tokens; thinking endpoints that still honor the schema spend that
/// budget on the think and return empty `content`.
const int kOpenRouterStructuredEvalMinTokens = 4000;

/// Build the OpenRouter `json_schema` object from the named eval tool.
///
/// Strict mode wants every property listed in `required` plus
/// `additionalProperties: false`. Journal/Growth (`toolChoice` empty) return
/// null so they stay on real `tools`.
Map<String, dynamic>? openRouterEvalJsonSchema({
  required List<Map<String, dynamic>> tools,
  required String? toolChoice,
}) {
  if (toolChoice == null || toolChoice.isEmpty) return null;
  for (final tool in tools) {
    final function = tool['function'];
    if (function is! Map) continue;
    if (function['name']?.toString() != toolChoice) continue;
    final parameters = function['parameters'];
    if (parameters is! Map) return null;
    final rawProps = parameters['properties'];
    if (rawProps is! Map || rawProps.isEmpty) return null;
    final properties = <String, dynamic>{
      for (final entry in rawProps.entries) entry.key.toString(): entry.value,
    };
    return {
      'name': toolChoice,
      'strict': true,
      'schema': {
        'type': 'object',
        'properties': properties,
        'required': properties.keys.toList(),
        'additionalProperties': false,
      },
    };
  }
  return null;
}

/// OpenRouter structured-output routing for a named eval.
///
/// Drops tools, sampler extras, and the `reasoning` object so
/// `require_parameters` only has to match `response_format` — the #230 combo
/// of tools + tool_choice + reasoning + require_parameters routed to thinking
/// endpoints that ignore forced tools, or 404'd entirely.
Map<String, dynamic> applyOpenRouterStructuredEvalRouting(
  Map<String, dynamic> payload, {
  required Map<String, dynamic> jsonSchema,
  required bool mandatoryReasoning,
}) {
  final next = Map<String, dynamic>.from(payload)
    ..remove('repetition_penalty')
    ..remove('min_p')
    ..remove('top_k')
    ..remove('tools')
    ..remove('tool_choice')
    ..remove('reasoning')
    ..['response_format'] = {'type': 'json_schema', 'json_schema': jsonSchema}
    ..['provider'] = {'require_parameters': true};
  var floor = kOpenRouterStructuredEvalMinTokens;
  if (mandatoryReasoning) {
    floor += kMandatoryReasoningThinkHeadroomTokens;
  }
  final current = next['max_tokens'];
  if (current is! num || current < floor) next['max_tokens'] = floor;
  return next;
}

/// Turn schema `content` / `reasoning` into the same [LlmToolResponse] a
/// successful `tool_calls` reply would have produced.
LlmToolResponse? toolResponseFromStructuredEvalContent({
  required String? content,
  required String? reasoning,
  required String toolName,
}) {
  for (final raw in [content, reasoning]) {
    if (raw == null || raw.trim().isEmpty) continue;
    final decoded = parseEvalJsonObject(raw);
    if (decoded == null || decoded.isEmpty) continue;
    return LlmToolResponse(
      calls: [LlmToolCall(name: toolName, arguments: decoded)],
      text: raw,
      reasoning: reasoning ?? '',
    );
  }
  return null;
}
