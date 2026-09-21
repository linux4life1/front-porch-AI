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

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/llm_tool_parsing.dart';
import 'package:front_porch_ai/services/openai_tool_payload.dart';
import 'package:front_porch_ai/services/openai_tool_stream.dart';
import 'package:front_porch_ai/services/openrouter_structured_eval.dart';
import 'package:front_porch_ai/services/openrouter_tool_support.dart';
import 'package:front_porch_ai/services/reasoning_effort.dart';
import 'package:front_porch_ai/services/tool_choice_style_probe.dart';

/// Public openrouter.ai tools door. Nested OpenAI tools, one shape, at most
/// one payload-fix / 429 retry. Nano / oMLX / LM Studio keep the style-probe
/// soup in [OpenRouterService.generateWithTools].
Future<LlmToolResponse?> runOpenRouterNativeTools({
  required String apiUrl,
  required String modelName,
  required GenerationParams params,
  required List<Map<String, dynamic>> tools,
  required http.Client client,
  required Map<String, String> headers,
  required Map<String, dynamic> Function(
    GenerationParams params, {
    required bool stream,
  })
  chatPayload,
}) async {
  final support = OpenRouterToolSupport.instance;
  if (!support.shouldSendTools(modelName)) {
    debugPrint(
      '[OpenRouter] $modelName has no tools (catalog or remembered 400) — '
      'skipping tools POST',
    );
    return null;
  }

  final uri = Uri.parse('$apiUrl/chat/completions');
  final streaming = params.onChunk != null;
  var retried = false;

  Map<String, dynamic> build() {
    var payload = chatPayload(params, stream: streaming);
    if (shouldApplyOpenRouterEvalToolRouting(
      reasoningEnabled: params.reasoningEnabled,
      reasoningMaxTokens: params.reasoningMaxTokens,
      toolChoice: params.toolChoice,
    )) {
      payload = applyOpenRouterToolRouting(
        payload,
        mandatoryReasoning: reasoningCannotDisable(modelName),
      );
    }
    payload = Map<String, dynamic>.from(payload)
      ..['provider'] = {'require_parameters': true};
    final style = params.toolChoice == kToolChoiceRequired
        ? ToolChoiceStyle.required
        : ToolChoiceStyle.named;
    attachTools(
      payload,
      tools: tools,
      toolChoice: params.toolChoice,
      stream: streaming,
      style: style,
      includeUsage: streaming,
    );
    return payload;
  }

  while (true) {
    final payload = build();
    if (streaming) {
      final request = http.Request('POST', uri)
        ..headers.addAll(headers)
        ..body = jsonEncode(payload);
      final streamed = await client.send(request);
      final status = streamed.statusCode;
      if (status == 200) {
        support.rememberConfirmed(modelName);
        final parsed = await consumeOpenAiToolSse(
          streamed.stream,
          wrap: params.reasoningEnabled && params.reasoningMaxTokens != 0,
          salvage: params.salvageReasoning,
          onChunk: params.onChunk,
        );
        _logUnusableToolCalls(modelName, parsed);
        return parsed;
      }
      final buffered = await http.Response.fromStream(streamed);
      final next = _handleNonOk(
        modelName: modelName,
        params: params,
        status: buffered.statusCode,
        body: buffered.body,
        retried: retried,
        support: support,
      );
      switch (next) {
        case _OrToolsNext.retry:
          retried = true;
          continue;
        case _OrToolsNext.failTransport:
          throw LlmToolTransportException(
            'tool call HTTP ${buffered.statusCode} (server busy/unavailable)',
          );
        case _OrToolsNext.giveUp:
          return null;
      }
    } else {
      final response = await client.post(
        uri,
        headers: headers,
        body: jsonEncode(payload),
      );
      final status = response.statusCode;
      if (status == 200) {
        support.rememberConfirmed(modelName);
        if (RegExp(r'"finish_reason"\s*:\s*"length"').hasMatch(response.body)) {
          debugPrint(
            '[OpenRouter] $modelName tool call hit max_tokens '
            '(finish_reason=length)',
          );
        }
        final parsed = parseOpenAiToolResponse(response.body);
        _logUnusableToolCalls(modelName, parsed);
        return parsed;
      }
      final next = _handleNonOk(
        modelName: modelName,
        params: params,
        status: status,
        body: response.body,
        retried: retried,
        support: support,
      );
      switch (next) {
        case _OrToolsNext.retry:
          retried = true;
          continue;
        case _OrToolsNext.failTransport:
          throw LlmToolTransportException(
            'tool call HTTP $status (server busy/unavailable)',
          );
        case _OrToolsNext.giveUp:
          return null;
      }
    }
  }
}

enum _OrToolsNext { retry, failTransport, giveUp }

_OrToolsNext _handleNonOk({
  required String modelName,
  required GenerationParams params,
  required int status,
  required String body,
  required bool retried,
  required OpenRouterToolSupport support,
}) {
  if (status == 429 || status >= 500) {
    if (retried) {
      return _OrToolsNext.failTransport;
    }
    debugPrint('[OpenRouter] $modelName HTTP $status — retrying once');
    return _OrToolsNext.retry;
  }
  final err = openRouterApiErrorMessage(body, status);
  final toolsUnsupported = isOpenRouterToolsUnsupportedStatus(status, body);
  final styleReject = isToolChoiceStyleRejection(status, body);
  if (!retried &&
      !toolsUnsupported &&
      !styleReject &&
      !reasoningCannotDisable(modelName) &&
      shouldFailoverToMandatoryReasoning(
        statusCode: status,
        askedToDisableThinking: askedToDisableThinking(
          reasoningEnabled: params.reasoningEnabled,
          reasoningMaxTokens: params.reasoningMaxTokens,
        ),
        errorMessage: err,
      )) {
    rememberMandatoryReasoning(modelName);
    debugPrint(
      '[OpenRouter] $modelName cannot disable reasoning — retrying once '
      'with reasoning.exclude only',
    );
    return _OrToolsNext.retry;
  }
  if (!retried &&
      learnReasoningEffortFromError(
        model: modelName,
        errorMessage: err,
        body: body,
      )) {
    debugPrint(
      '[OpenRouter] $modelName rejected reasoning.effort — retrying once',
    );
    return _OrToolsNext.retry;
  }
  if (toolsUnsupported) {
    support.rememberRejected(modelName);
    debugPrint(
      '[OpenRouter] $modelName does not support tools — remembered, '
      'no retry: $err',
    );
  } else {
    debugPrint(
      '[OpenRouter] Tool call rejected (HTTP $status) — unusable, '
      'no second generate: $err',
    );
  }
  return _OrToolsNext.giveUp;
}

void _logUnusableToolCalls(String modelName, LlmToolResponse? parsed) {
  if (parsed == null || !parsed.isUnusableNativeToolCall) return;
  debugPrint(
    '[OpenRouter] $modelName empty tool_calls '
    '(finish_reason=tool_calls) — unusable, no second generate',
  );
}

/// Pull a human error string out of a provider JSON body (or the raw body).
String openRouterApiErrorMessage(String body, int statusCode) {
  final fallback = 'HTTP $statusCode';
  if (body.isEmpty) return fallback;
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      final err = decoded['error'];
      if (err is Map && err['message'] != null) {
        return err['message'].toString();
      }
      if (err is String && err.isNotEmpty) return err;
      if (decoded['message'] != null) return decoded['message'].toString();
    }
    if (decoded is String && decoded.isNotEmpty) return decoded;
  } catch (_) {}
  return body.length > 800 ? '${body.substring(0, 800)}…' : body;
}
