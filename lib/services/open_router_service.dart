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

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/llm_tool_parsing.dart';
import 'package:front_porch_ai/services/openai_completions_fallback.dart';
import 'package:front_porch_ai/services/openai_tool_payload.dart';
import 'package:front_porch_ai/services/openai_tool_stream.dart';
import 'package:front_porch_ai/services/openrouter_native_tools.dart';
import 'package:front_porch_ai/services/openrouter_structured_eval.dart';
import 'package:front_porch_ai/services/openrouter_tool_support.dart';
import 'package:front_porch_ai/services/reasoning_effort.dart';
import 'package:front_porch_ai/services/reasoning_stream_wrapper.dart';
import 'package:front_porch_ai/services/remote_model_info.dart';
import 'package:front_porch_ai/services/remote_reachability.dart';

// RemoteModelInfo lived here for years — re-export so importers keep working.
export 'package:front_porch_ai/services/remote_model_info.dart';

part 'open_router_service.tools.dart';
part 'open_router_service.catalog.dart';

/// LLM backend for OpenAI-compatible APIs (OpenRouter, Nano-GPT, vLLM, …).
class OpenRouterService extends LLMService implements LlmApiEndpoint {
  String _apiUrl;
  String _apiKey;
  String _modelName;
  final RemoteApiHealth _health = RemoteApiHealth();

  /// Every in-flight client; a set is required because staggered remote evals
  /// overlap, and one slot let the first completion disarm Cancel for the rest.
  final Set<http.Client> _activeClients = {};

  /// Test seam: a MockClient so reachability tests never hit the network.
  http.Client Function()? get httpClientFactory => _health.httpClientFactory;
  set httpClientFactory(http.Client Function()? factory) =>
      _health.httpClientFactory = factory;

  @override
  String get apiUrl => _apiUrl;
  String get apiKey => _apiKey;
  String get modelName => _modelName;
  RemoteReachability get reachability => _health.reachability;
  bool get isReachable => _health.isReachable;
  bool get isCheckingReachability => _health.isChecking;

  /// Local backends (oMLX, LM Studio, llama.cpp, vLLM on LAN / Tailscale)
  /// are usable without an API key. Same predicate the effort probe uses so
  /// a 192.168 LM Studio still gets `enable_thinking` — the old
  /// `contains('localhost')` gate left those servers on the OpenRouter
  /// `reasoning` object, which they ignore.
  bool get _isLocalUrl => isLocalRemoteUrl(_apiUrl);

  /// Thinking-off 400/422 → Kimi salvage for this model, any host phrasing.
  bool _thinkingOffRejected(int status, GenerationParams params, String err) =>
      !reasoningCannotDisable(modelName) &&
      shouldFailoverToMandatoryReasoning(
        statusCode: status,
        askedToDisableThinking: askedToDisableThinking(
          reasoningEnabled: params.reasoningEnabled,
          reasoningMaxTokens: params.reasoningMaxTokens,
        ),
        errorMessage: err,
      );

  /// Credentials + model are filled in. Not a live ping.
  bool get isConfigured =>
      _modelName.isNotEmpty && (_apiKey.isNotEmpty || _isLocalUrl);

  /// Generation gate: configured, and not proven unreachable. Unknown /
  /// checking stay provisionally ready so a 5s ping does not freeze send;
  /// a failed ping flips this off (composer: "No API connection").
  @override
  bool get isReady {
    if (!isConfigured) return false;
    if (reachability == RemoteReachability.unreachable) return false;
    return true;
  }

  @override
  String get backendName => 'Remote API';

  OpenRouterService({
    String apiUrl = 'https://openrouter.ai/api/v1',
    String apiKey = '',
    String modelName = '',
  }) : _apiUrl = apiUrl,
       _apiKey = apiKey,
       _modelName = modelName {
    _health.onChanged = _emit;
  }

  void _emit() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }

  /// Update configuration at runtime (e.g. when user changes settings).
  /// Returns true when URL / key / model actually changed.
  bool configure({String? apiUrl, String? apiKey, String? modelName}) {
    var changed = false;
    var endpointChanged = false;
    if (apiUrl != null && apiUrl != _apiUrl) {
      _apiUrl = apiUrl;
      changed = true;
      endpointChanged = true;
    }
    if (apiKey != null && apiKey != _apiKey) {
      _apiKey = apiKey;
      changed = true;
      endpointChanged = true;
    }
    if (modelName != null && modelName != _modelName) {
      _modelName = modelName;
      changed = true;
    }
    if (endpointChanged || !isConfigured) {
      _health.reset();
    }
    if (changed) _emit();
    return changed;
  }

  /// Live `GET /models` against the configured endpoint. Stamps
  /// [reachability] (and therefore [isReady] / [isReachable]).
  Future<void> refreshReachability() =>
      _health.ping(apiUrl: _apiUrl, apiKey: _apiKey, configured: isConfigured);

  /// Test whether the API connection is working.
  /// Returns a human-readable status message.
  /// Tests connectivity against [apiUrl] (else this service's live URL).
  /// Same override contract as [fetchAvailableModels]: pass the target
  /// explicitly from UI so a connection test never re-routes the active
  /// backend's live configuration.
  Future<String> testConnection({String? apiUrl, String? apiKey}) =>
      _health.testConnection(
        liveUrl: _apiUrl,
        liveKey: _apiKey,
        configured: isConfigured,
        apiUrl: apiUrl,
        apiKey: apiKey,
      );

  Future<List<RemoteModelInfo>> fetchAvailableModels({
    String? apiUrl,
    String? apiKey,
  }) => _fetchAvailableModels(apiUrl: apiUrl, apiKey: apiKey);

  /// Named evals share [generateWithTools]. Public OpenRouter is the
  /// dedicated tools path (no json_schema-then-tools double bill).
  Future<LlmToolResponse?> generateStructuredJson(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) => generateWithTools(params, tools);

  /// OpenAI tools: null = unusable; throw = transport failure.
  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) => _generateWithTools(params, tools);

  /// Shared identification/auth headers for both request paths.
  /// Auth is [remoteAuthHeaders] — the same map Check Connection sends.
  Map<String, String> get _chatHeaders => {
    'Content-Type': 'application/json',
    ...remoteAuthHeaders(_apiKey),
    'HTTP-Referer': 'https://github.com/linux4life1/front-porch-AI',
    'X-Title': 'Front Porch AI',
  };

  /// Test seam: the exact headers [generateStream] puts on chat/completions.
  Map<String, String> get chatRequestHeaders => _chatHeaders;

  @override
  Stream<String> generateStream(
    GenerationParams params, {
    int payloadRetries = 0,
  }) async* {
    if (!isReady) {
      throw Exception(
        'Remote API not configured. Please set API key and model.',
      );
    }

    if (isRememberedCompletionsOnlyModel(_modelName)) {
      yield* _generateCompletionsStream(params);
      return;
    }

    final request = http.Request(
      'POST',
      Uri.parse('$_apiUrl/chat/completions'),
    );
    request.headers.addAll(_chatHeaders);
    request.body = jsonEncode(_chatPayload(params, stream: true));

    final client = httpClientFactory?.call() ?? http.Client();
    final owned = httpClientFactory == null;
    _activeClients.add(client);
    // Only wrap reasoning in <think> tags when the app explicitly requested it.
    // Some models (e.g. Qwen on LM Studio) send the entire response as
    // reasoning_content even when reasoning wasn't requested — wrapping those
    // in <think> tags would hide the response entirely. The shared wrapper is
    // the same one the local KoboldCpp path uses (see streamOpenAiChat), so the
    // two transports emit identical <think>…</think> framing.
    //
    // The arming condition here is bare `reasoningEnabled` (vs the local path's
    // `reasoningEnabled && reasoningMaxTokens != 0`), and that is correct, not an
    // oversight: this backend suppresses reasoning REQUEST-side via the
    // `reasoning:{exclude:true}` object whenever `!reasoningEnabled` (see the
    // payload builder), so the provider returns no reasoning to wrap. Every
    // suppress path (Continue, evals) sets reasoningEnabled=false anyway, so the
    // two predicates are equivalent in practice.
    final wrapper = ReasoningIngest(
      wrap: params.reasoningEnabled,
      salvage: params.salvageReasoning,
    );

    try {
      // No wall-clock timeout on the streamed reply (incl. local oMLX): a long
      // reasoning/thinking generation streams for as long as it needs. A crashed
      // connection ends the stream / throws (handled) and Cancel aborts, so the
      // fixed cap only ever killed working generations.
      final response = await client.send(request);

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        final errorMsg = openRouterApiErrorMessage(body, response.statusCode);
        // A mandatory-reasoning model refusing `reasoning:{enabled:false}`.
        // Remember it and RETRY ONCE right here rather than just throwing:
        // without the retry the caller still loses this eval, and for the
        // reported case that is every judge on the turn the user is waiting on.
        // The rejection then costs one round trip for the life of the process.
        if (payloadRetries < 1 &&
            _thinkingOffRejected(response.statusCode, params, errorMsg)) {
          rememberMandatoryReasoning(modelName);
          debugPrint(
            '[RemoteAPI] $modelName cannot disable reasoning — retrying with '
            'Kimi salvage (remembered for this session)',
          );
          yield* generateStream(params, payloadRetries: payloadRetries + 1);
          return;
        }
        // The provider re-tiered this model's reasoning.effort values under
        // us (DeepSeek v4-flash:thinking dropped low/medium, 2026-07-18) and
        // its 400 names the values it still takes. Same learn-once-and-retry
        // as generateWithTools: remember the supported set, remap on the
        // payload, retry this turn. A second rejection of the same listing
        // does not loop.
        if (payloadRetries < 1 &&
            learnReasoningEffortFromError(
              model: modelName,
              errorMessage: errorMsg,
              body: body,
            )) {
          debugPrint(
            '[RemoteAPI] $modelName rejected reasoning.effort '
            '"${params.reasoningEffort}" — retrying with '
            '"${wireReasoningEffort(modelName, params.reasoningEffort)}" '
            '(remembered for this session)',
          );
          yield* generateStream(params, payloadRetries: payloadRetries + 1);
          return;
        }
        if (isChatCompletionsUnsupportedError(errorMsg)) {
          rememberCompletionsOnlyModel(_modelName);
          debugPrint(
            '[RemoteAPI] $_modelName is completions-only on this '
            'server — retrying /v1/completions',
          );
          yield* _generateCompletionsStream(params);
          return;
        }
        throw Exception('API error: $errorMsg');
      }

      // Parse SSE stream. [DONE] and connection-close share one end check
      // so a silent mandatory-reasoner (length + zero content) is learned
      // the same way on either terminator.
      var emittedContent = false;
      var finishReasonLength = false;

      Iterable<String> ingestChoice(Object? rawChoice) sync* {
        if (rawChoice is! Map) return;
        if (rawChoice['finish_reason'] == 'length') {
          finishReasonLength = true;
          debugPrint(
            '[RemoteAPI] $modelName hit max_tokens '
            '(finish_reason=length) — response truncated',
          );
        }
        final delta = rawChoice['delta'];
        if (delta is! Map) return;
        final reasoning = delta['reasoning'] ?? delta['reasoning_content'];
        if (reasoning is String && reasoning.isNotEmpty) {
          final out = wrapper.onReasoning(reasoning);
          if (out.isNotEmpty) yield out;
          return;
        }
        final content = delta['content'];
        if (content is String && content.isNotEmpty) {
          if (contentDeltaCountsAsEmitted(content)) {
            emittedContent = true;
          }
          final out = wrapper.onContent(content);
          if (out.isNotEmpty) yield out;
        }
      }

      String buffer = '';
      streamLoop:
      await for (final chunk in response.stream.transform(utf8.decoder)) {
        buffer += chunk;

        while (buffer.contains('\n')) {
          final idx = buffer.indexOf('\n');
          final line = buffer.substring(0, idx).trim();
          buffer = buffer.substring(idx + 1);

          if (line.isEmpty) continue;
          if (line == 'data: [DONE]' || line == 'data:[DONE]') {
            break streamLoop;
          }
          if (!line.startsWith('data:')) continue;

          final data = line.startsWith('data: ')
              ? line.substring(6)
              : line.substring(5);
          try {
            final json = jsonDecode(data);
            for (final out in ingestChoice(json['choices']?[0])) {
              yield out;
            }
          } catch (_) {
            // Skip malformed chunks
          }
        }
      }

      // Last chunk may lack a trailing newline.
      final remaining = buffer.trim();
      if (remaining.isNotEmpty && remaining.startsWith('data:')) {
        final data = remaining.startsWith('data: ')
            ? remaining.substring(6)
            : remaining.substring(5);
        if (data != '[DONE]') {
          try {
            final json = jsonDecode(data);
            for (final out in ingestChoice(json['choices']?[0])) {
              yield out;
            }
          } catch (_) {}
        }
      }

      final tail = wrapper.finish();
      if (tail.isNotEmpty) yield tail;

      final askedOff = askedToDisableThinking(
        reasoningEnabled: params.reasoningEnabled,
        reasoningMaxTokens: params.reasoningMaxTokens,
      );
      final silentStarve = isSilentMandatoryReasoningStarve(
        finishReasonLength: finishReasonLength,
        emittedContent: emittedContent,
        askedToDisableThinking: askedOff,
      );
      if (silentStarve) {
        // Same key as the 400 path — OpenRouter ids are already
        // provider/model (not a bare slug).
        if (!reasoningCannotDisable(modelName)) {
          rememberMandatoryReasoning(modelName);
          debugPrint(
            '[RemoteAPI] $modelName silent mandatory-reasoning starve '
            '(finish_reason=length, no content) — remembered for this session',
          );
        }
        if (params.mandatoryReasoningHeadroom && payloadRetries < 1) {
          debugPrint(
            '[RemoteAPI] $modelName retrying once with think headroom '
            '(exclude stays on)',
          );
          yield* generateStream(params, payloadRetries: payloadRetries + 1);
          return;
        }
        if (params.mandatoryReasoningHeadroom) {
          throw SilentMandatoryReasoningStarveException(modelName);
        }
      }
    } finally {
      _activeClients.remove(client);
      if (owned) client.close();
    }
  }

  /// oMLX VLM / completions-only models. Same abort set as [generateStream].
  Stream<String> _generateCompletionsStream(GenerationParams params) async* {
    final payload = openAiCompletionsPayload(
      params,
      modelName: _modelName,
      stream: true,
    );
    final client = http.Client();
    _activeClients.add(client);
    try {
      final response = await postOpenAiCompletions(
        apiUrl: _apiUrl,
        headers: _chatHeaders,
        payload: payload,
        client: client,
      );
      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        throw Exception(
          'API error: ${openRouterApiErrorMessage(body, response.statusCode)}',
        );
      }
      yield* parseCompletionsSse(response.stream);
    } finally {
      _activeClients.remove(client);
      client.close();
    }
  }

  @override
  void abortGeneration() {
    // Iterate a copy: each close() lets its call's finally run, which mutates
    // the set.
    for (final client in _activeClients.toList()) {
      client.close();
    }
    _activeClients.clear();
  }
}
