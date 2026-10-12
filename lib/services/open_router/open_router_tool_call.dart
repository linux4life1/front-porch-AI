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
import 'package:front_porch_ai/services/open_router/open_router_chat_payload.dart';
import 'package:front_porch_ai/services/open_router/open_router_clients.dart';
import 'package:front_porch_ai/services/openai_tool_payload.dart';
import 'package:front_porch_ai/services/openai_tool_stream.dart';
import 'package:front_porch_ai/services/openrouter_native_tools.dart';
import 'package:front_porch_ai/services/openrouter_structured_eval.dart';
import 'package:front_porch_ai/services/reasoning_effort.dart';

/// One OpenAI tools request on its own tracked client: null = unusable;
/// throw = transport failure. [retry] re-enters the caller's own tools entry point after a
/// reasoning rejection was learned, so the retry dispatches the way the
/// first call did.
Future<LlmToolResponse?> sendOpenRouterToolCall({
  required GenerationParams params,
  required List<Map<String, dynamic>> tools,
  required OpenRouterClients clients,
  required http.Client Function()? clientFactory,
  required String apiUrl,
  required String modelName,
  required String backendName,
  required Map<String, String> headers,
  required Map<String, dynamic> Function(
    GenerationParams params, {
    required bool stream,
  })
  chatPayload,
  required Future<LlmToolResponse?> Function() retry,
}) async {
  final client = clientFactory?.call() ?? http.Client();
  clients.add(client, params);
  try {
    if (isOpenRouterApiUrl(apiUrl)) {
      return await runOpenRouterNativeTools(
        apiUrl: apiUrl,
        modelName: modelName,
        params: params,
        tools: tools,
        client: client,
        headers: headers,
        chatPayload: chatPayload,
      );
    }
    final identity = params.backendIdentity.isEmpty
        ? '$backendName|$modelName|'
        : params.backendIdentity;
    final streaming = params.onChunk != null;
    final payload = chatPayload(params, stream: streaming);
    if (streaming) {
      String? streamErr;
      int? streamStatus;
      final thinkOn = params.reasoningEnabled && params.reasoningMaxTokens != 0;
      final streamed = await streamOpenAiChatToolsWithStyleRetry(
        identity: identity,
        tools: tools,
        toolChoice: params.toolChoice,
        basePayload: payload,
        uri: Uri.parse('$apiUrl/chat/completions'),
        headers: headers,
        client: client,
        wrapReasoning: thinkOn,
        salvage: params.salvageReasoning,
        onChunk: params.onChunk,
        includeUsage: true,
        onHttpError: (status, body) {
          streamStatus = status;
          streamErr = body;
        },
      );
      if (streamed != null) return streamed;
      final rejected = streamErr;
      final status = streamStatus ?? 0;
      if (rejected != null &&
          openRouterThinkingOffRejected(
            modelName: modelName,
            status: status,
            params: params,
            err: rejected,
          )) {
        rememberMandatoryReasoning(modelName);
        debugPrint(
          '[RemoteAPI] $modelName cannot disable reasoning — retrying '
          'streamed tool call with reasoning.exclude only',
        );
        return await retry();
      }
      if (rejected != null &&
          learnReasoningEffortFromError(
            model: modelName,
            errorMessage: openRouterApiErrorMessage(rejected, status),
            body: rejected,
          )) {
        debugPrint(
          '[RemoteAPI] $modelName rejected reasoning.effort '
          '"${params.reasoningEffort}" — retrying tools with '
          '"${wireReasoningEffort(modelName, params.reasoningEffort)}" '
          '(think cap stays on the payload)',
        );
        return await retry();
      }
      return null;
    }
    final response = await attachToolsWithStyleRetry(
      identity: identity,
      tools: tools,
      toolChoice: params.toolChoice,
      basePayload: payload,
      post: (payload) => client.post(
        Uri.parse('$apiUrl/chat/completions'),
        headers: headers,
        body: jsonEncode(payload),
      ),
    );
    if (response.statusCode == 429 || response.statusCode >= 500) {
      // A provider hiccup is transient, not a capability verdict.
      throw LlmToolTransportException(
        'tool call HTTP ${response.statusCode} (server busy/unavailable)',
      );
    }
    if (response.statusCode != 200) {
      final err = openRouterApiErrorMessage(response.body, response.statusCode);
      if (openRouterThinkingOffRejected(
        modelName: modelName,
        status: response.statusCode,
        params: params,
        err: err,
      )) {
        rememberMandatoryReasoning(modelName);
        debugPrint(
          '[RemoteAPI] $modelName cannot disable reasoning — retrying '
          'tool call with reasoning.exclude only',
        );
        return await retry();
      }
      if (learnReasoningEffortFromError(
        model: modelName,
        errorMessage: err,
        body: response.body,
      )) {
        debugPrint(
          '[RemoteAPI] $modelName rejected reasoning.effort '
          '"${params.reasoningEffort}" — retrying tools with '
          '"${wireReasoningEffort(modelName, params.reasoningEffort)}" '
          '(think cap stays on the payload)',
        );
        return await retry();
      }
      debugPrint(
        '[RemoteAPI] Tool call rejected (HTTP ${response.statusCode}) — '
        'falling back to text transport: $err',
      );
      return null;
    }
    if (RegExp(r'"finish_reason"\s*:\s*"length"').hasMatch(response.body)) {
      debugPrint(
        '[RemoteAPI] $modelName tool call hit max_tokens '
        '(finish_reason=length) — likely truncated mid-think, no tool call',
      );
    }
    return parseOpenAiToolResponse(response.body);
  } catch (e) {
    // Let callers classify killed connections as transport failures.
    debugPrint('[RemoteAPI] Tool call transport failure: $e');
    rethrow;
  } finally {
    clients.remove(client);
    client.close();
  }
}
