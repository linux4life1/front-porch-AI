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

import 'llm_service.dart';

/// Parse a non-streaming OpenAI chat-completions response body into an
/// [LlmToolResponse]: the assistant message's `tool_calls` (arguments
/// JSON-decoded; malformed arguments become `{}` so the downstream op parser
/// drops just that op) plus any plain text content. Returns null when the
/// body has no assistant message at all.
///
/// Pure and provider-agnostic — shared by any [LLMService] that implements
/// [LLMService.generateWithTools] over the OpenAI protocol.
LlmToolResponse? parseOpenAiToolResponse(String body) {
  final dynamic json;
  try {
    json = jsonDecode(body);
  } catch (_) {
    return null;
  }
  if (json is! Map) return null;
  final choices = json['choices'];
  final first = (choices is List && choices.isNotEmpty) ? choices[0] : null;
  final message = first is Map ? first['message'] : null;
  if (message is! Map) return null;

  final calls = <LlmToolCall>[];
  for (final tc in (message['tool_calls'] as List? ?? const [])) {
    final fn = tc is Map ? tc['function'] : null;
    final name = fn is Map ? fn['name'] : null;
    if (name is! String || name.isEmpty) continue;
    final rawArgs = fn['arguments'];
    Map<String, dynamic> args = const {};
    if (rawArgs is Map) {
      args = Map<String, dynamic>.from(rawArgs);
    } else if (rawArgs is String && rawArgs.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawArgs);
        if (decoded is Map) args = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    calls.add(LlmToolCall(name: name, arguments: args));
  }
  return LlmToolResponse(
    calls: calls,
    text: message['content'] is String ? message['content'] as String : '',
  );
}
