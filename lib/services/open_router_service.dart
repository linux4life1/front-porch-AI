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
import 'package:front_porch_ai/services/reasoning_stream_wrapper.dart';
import 'package:front_porch_ai/services/remote_model_info.dart';

// RemoteModelInfo lived here for years — re-export so importers keep working.
export 'package:front_porch_ai/services/remote_model_info.dart';

/// LLM backend that connects to OpenAI-compatible APIs
/// (OpenRouter, Nano-GPT, vLLM, LM Studio, etc).
class OpenRouterService extends LLMService {
  String _apiUrl;
  String _apiKey;
  String _modelName;
  bool _isReady = false;
  http.Client? _activeClient;

  String get apiUrl => _apiUrl;
  String get apiKey => _apiKey;
  String get modelName => _modelName;

  /// Local backends (LM Studio, vLLM, etc.) are usable without an API key.
  bool get _isLocalUrl =>
      _apiUrl.contains('localhost') || _apiUrl.contains('127.0.0.1');

  @override
  bool get isReady {
    if (!_isReady || _modelName.isEmpty) return false;
    return _apiKey.isNotEmpty || _isLocalUrl;
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
    _isReady = (_apiKey.isNotEmpty || _isLocalUrl) && _modelName.isNotEmpty;
  }

  /// Update configuration at runtime (e.g. when user changes settings).
  void configure({String? apiUrl, String? apiKey, String? modelName}) {
    bool changed = false;
    if (apiUrl != null && apiUrl != _apiUrl) {
      _apiUrl = apiUrl;
      changed = true;
    }
    if (apiKey != null && apiKey != _apiKey) {
      _apiKey = apiKey;
      changed = true;
    }
    if (modelName != null && modelName != _modelName) {
      _modelName = modelName;
      changed = true;
    }
    // Allow local backends without API key
    final newReady =
        (_apiKey.isNotEmpty || _isLocalUrl) && _modelName.isNotEmpty;
    if (newReady != _isReady) {
      _isReady = newReady;
      changed = true;
    }
    if (changed) {
      // Defer notification to after the current frame to avoid calling
      // notifyListeners() during the widget build phase, which crashes
      // release builds (setState called during build).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }
  }

  /// Test whether the API connection is working.
  /// Returns a human-readable status message.
  /// Tests connectivity against [apiUrl] (else this service's live URL).
  /// Same override contract as [fetchAvailableModels]: pass the target
  /// explicitly from UI so a connection test never re-routes the active
  /// backend's live configuration.
  Future<String> testConnection({String? apiUrl, String? apiKey}) async {
    final url = apiUrl ?? _apiUrl;
    final key = apiKey ?? _apiKey;
    if (url.isEmpty) return 'API URL is empty.';
    // Allow empty API key for local backends (localhost / 127.0.0.1)
    final isLocal = url.contains('localhost') || url.contains('127.0.0.1');
    if (key.isEmpty && !isLocal) return 'API key is empty.';

    final client = http.Client();
    try {
      final uri = Uri.parse('$url/models');
      final response = await client
          .get(uri, headers: {'Authorization': 'Bearer $key'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return 'Connection successful!';
      } else {
        String msg = 'HTTP ${response.statusCode}';
        try {
          final body = jsonDecode(response.body);
          msg = body['error']?['message'] ?? msg;
        } catch (_) {}
        return 'Connection failed: $msg';
      }
    } catch (e) {
      return 'Connection failed: $e';
    } finally {
      client.close();
    }
  }

  /// Fetch the list of available models with pricing info from the API.
  /// Lists models from [apiUrl] (else this service's live URL). Pass the
  /// target EXPLICITLY when fetching for a picker: this service is the ONE
  /// shared client for Remote API and oMLX, and UI sites that called
  /// `configure(...)` just to point a list-fetch somewhere were silently
  /// re-routing the ACTIVE backend's chat traffic (opening Settings while on
  /// oMLX sent every request to the Remote API provider until the next
  /// storage sync). The overrides fetch without touching live state.
  Future<List<RemoteModelInfo>> fetchAvailableModels({
    String? apiUrl,
    String? apiKey,
  }) async {
    final url = apiUrl ?? _apiUrl;
    final key = apiKey ?? _apiKey;
    if (url.isEmpty) return [];
    final isLocal = url.contains('localhost') || url.contains('127.0.0.1');
    if (key.isEmpty && !isLocal) return [];

    final client = http.Client();
    try {
      final uri = Uri.parse('$url/models');
      debugPrint('[OpenRouter] Fetching models from: $uri');
      final response = await client
          .get(
            uri,
            headers: {
              if (key.isNotEmpty) 'Authorization': 'Bearer $key',
            },
          )
          .timeout(const Duration(seconds: 15));

      debugPrint('[OpenRouter] Response status: ${response.statusCode}');
      if (response.statusCode != 200) {
        debugPrint('[OpenRouter] Error body: ${response.body}');
        return [];
      }

      final body = jsonDecode(response.body);
      debugPrint('[OpenRouter] Response keys: ${body.keys.toList()}');
      // Handle both OpenAI format ('data') and LM Studio format ('models')
      final data =
          (body['data'] as List<dynamic>?) ??
          (body['models'] as List<dynamic>?) ??
          [];
      debugPrint('[OpenRouter] Found ${data.length} model entries');
      if (data.isNotEmpty) {
        debugPrint('[OpenRouter] First entry type: ${data.first.runtimeType}');
        debugPrint('[OpenRouter] First entry: ${data.first}');
      }
      final models = <RemoteModelInfo>[];

      for (final m in data) {
        String id = '';
        String name = '';

        if (m is String) {
          // Plain string list of model names (some backends)
          id = m;
          name = m;
        } else if (m is Map) {
          id =
              m['id']?.toString() ??
              m['key']?.toString() ??
              m['name']?.toString() ??
              m['model']?.toString() ??
              '';
          name =
              m['display_name']?.toString() ??
              m['name']?.toString() ??
              m['id']?.toString() ??
              id;
        }
        if (id.isEmpty) continue;
        final pricing = m['pricing'] as Map<String, dynamic>?;

        // API returns USD per token; convert to per 1M tokens for readability
        double? promptCost;
        double? completionCost;
        if (pricing != null) {
          final promptRaw = double.tryParse(
            pricing['prompt']?.toString() ?? '',
          );
          final completionRaw = double.tryParse(
            pricing['completion']?.toString() ?? '',
          );
          if (promptRaw != null) promptCost = promptRaw * 1000000;
          if (completionRaw != null) completionCost = completionRaw * 1000000;
        }

        models.add(
          RemoteModelInfo(
            id: id,
            name: name,
            promptCostPerMillion: promptCost,
            completionCostPerMillion: completionCost,
          ),
        );
      }

      debugPrint('[OpenRouter] Parsed ${models.length} models');
      models.sort((a, b) => a.id.compareTo(b.id));
      return models;
    } catch (e) {
      debugPrint('[OpenRouter] Error fetching models: $e');
      return [];
    } finally {
      client.close();
    }
  }

  /// Chat-completions payload shared by [generateStream] and
  /// [generateWithTools] (one builder, so the two paths can't drift).
  Map<String, dynamic> _chatPayload(
    GenerationParams params, {
    required bool stream,
  }) {
    // Role-separated messages; user content is a plain string or, when
    // images ride along, a multimodal array (see openAiUserContent).
    final messages = <Map<String, Object>>[];
    if (params.systemPrompt != null && params.systemPrompt!.isNotEmpty) {
      messages.add({'role': 'system', 'content': params.systemPrompt!});
    }
    messages.add({'role': 'user', 'content': params.openAiUserContent});

    // api.openai.com rejects unknown parameters outright, so it keeps the
    // old conservative payload (frequency_penalty approximation, no
    // extensions). Everyone else (OpenRouter, Nano-GPT, vLLM, LM Studio)
    // supports or ignores the native sampler fields.
    final strictOpenAi = _apiUrl.contains('openai.com');
    final payload = <String, dynamic>{
      'model': _modelName,
      'stream': stream,
      'max_tokens': params.maxLength,
      'temperature': params.temperature,
      'top_p': params.topP,
      'messages': messages,
      if (strictOpenAi)
        'frequency_penalty': params.repeatPenalty > 1.0
            ? (params.repeatPenalty - 1.0).clamp(0.0, 2.0)
            : 0.0
      else ...{
        // The real thing — Rep Pen used to be mistranslated into
        // frequency_penalty (1.15 → 0.15) and Min-P was dropped entirely.
        'repetition_penalty': params.repeatPenalty,
        'min_p': params.minP,
        if (params.topK > 0) 'top_k': params.topK,
      },
    };

    // Add reasoning params.
    // For Continue (and call mode) we force enabled:false + max_tokens:0 .
    // This gives OpenRouter (and Nano-GPT etc.) the strongest signal to disable thinking
    // for models like Kimi K2.6:thinking, DeepSeek hybrids, etc.
    // We always include the 'enabled' key so the disable is explicit.
    if (params.reasoningEnabled || params.reasoningMaxTokens != null) {
      final reasoning = <String, dynamic>{
        'enabled': params.reasoningEnabled,
      };
      if (params.reasoningEnabled) {
        reasoning['effort'] = params.reasoningEffort;
      }
      if (params.reasoningMaxTokens != null) {
        reasoning['max_tokens'] = params.reasoningMaxTokens;
      }
      // When suppressing reasoning (e.g. Continue with budget 0), also ask the provider
      // to exclude reasoning tokens from the response entirely. This matches how SillyTavern
      // handles "Request model reasoning" = off for OpenRouter models.
      if (!params.reasoningEnabled) {
        reasoning['exclude'] = true;
      }
      payload['reasoning'] = reasoning;
    }

    // Qwen3's NATIVE thinking switch — LOCAL backends only. Local OpenAI-compatible
    // MLX/vLLM servers (oMLX, LM Studio) IGNORE the OpenRouter `reasoning` object
    // above and only honor `enable_thinking` in the chat template. Verified live
    // against oMLX v0.5.2: `reasoning:{enabled:false}` left Qwen3 thinking (554
    // reasoning tokens), while `enable_thinking:false` suppressed it completely (0).
    // Gated to `_isLocalUrl` so real OpenRouter/Nano-GPT are untouched — they read
    // the `reasoning` object and could reject/misforward an unknown chat-template
    // kwarg. Mirrors the KoboldCpp path (openai_chat_stream.dart). `thinkOn` matches
    // Kobold's exactly: reasoning wanted, unless a caller hard-suppressed via
    // reasoningMaxTokens==0 (Continue, evals, call mode). (A remote self-hosted
    // vLLM/MLX endpoint would also want this, but that's not the localhost case
    // this fixes; extend the gate if that need appears.)
    if (_isLocalUrl) {
      payload['chat_template_kwargs'] = {
        'enable_thinking':
            params.reasoningEnabled && params.reasoningMaxTokens != 0,
      };
    }

    // Add stop sequences if present
    if (params.stopSequences != null && params.stopSequences!.isNotEmpty) {
      // Remote providers commonly hard-cap `stop` at 4 (OpenAI spec). The
      // list arrives priority-ordered (stop_sequences.dart) so these 4 are
      // the most important — user stops first, then custom, then names. The
      // client-side mid-stream trim enforces the rest of the list.
      payload['stop'] = params.stopSequences!.take(4).toList();
    }
    return payload;
  }

  /// Shared identification/auth headers for both request paths.
  Map<String, String> get _chatHeaders => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $_apiKey',
    // Identify the app for providers that support it
    'HTTP-Referer': 'https://github.com/linux4life1/front-porch-AI',
    'X-Title': 'Front Porch AI',
  };

  /// OpenAI-style tool calling (non-streaming) — used by the Journal's
  /// tool transport. Returns null when the provider ANSWERED but the call
  /// yielded nothing usable (non-200 status, e.g. a model without tool
  /// support): the caller treats null as "use the text transport instead".
  /// Transport failures (host unreachable, client torn down by an app-side
  /// abortGeneration) THROW so callers never record a capability verdict
  /// for what was a network event — see the base-class contract.
  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    if (!isReady) return null;
    final payload = _chatPayload(params, stream: false)
      ..['tools'] = tools
      ..['tool_choice'] = 'auto';

    final client = http.Client();
    _activeClient = client;
    try {
      // No wall-clock timeout: a tool/eval call (incl. local oMLX via this same
      // client) can legitimately run long on a slow model or reasoning pass. A
      // dead connection throws (rethrown below as a transport failure) and
      // Cancel aborts, so a fixed cap only killed working calls.
      final response = await client.post(
        Uri.parse('$_apiUrl/chat/completions'),
        headers: _chatHeaders,
        body: jsonEncode(payload),
      );
      if (response.statusCode == 429 || response.statusCode >= 500) {
        // Rate-limited / provider hiccup: transient, not a capability
        // verdict — must not brand the model tool-less for the run.
        throw LlmToolTransportException(
          'tool call HTTP ${response.statusCode} (server busy/unavailable)',
        );
      }
      if (response.statusCode != 200) {
        debugPrint(
          '[RemoteAPI] Tool call rejected (HTTP ${response.statusCode}) — '
          'falling back to text transport',
        );
        return null;
      }
      return parseOpenAiToolResponse(response.body);
    } catch (e) {
      // Rethrow instead of collapsing to null — a killed connection must not
      // read as "model can't speak tools" (it branded the backend XML-only
      // for the whole run). Callers filter via looksLikeBackendUnreachable.
      debugPrint('[RemoteAPI] Tool call transport failure: $e');
      rethrow;
    } finally {
      if (identical(_activeClient, client)) _activeClient = null;
      client.close();
    }
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (!isReady) {
      throw Exception(
        'Remote API not configured. Please set API key and model.',
      );
    }

    final request = http.Request(
      'POST',
      Uri.parse('$_apiUrl/chat/completions'),
    );
    request.headers.addAll(_chatHeaders);
    request.body = jsonEncode(_chatPayload(params, stream: true));

    final client = http.Client();
    _activeClient = client;
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
    final wrapper = ReasoningTagWrapper(wrap: params.reasoningEnabled);

    try {
      // No wall-clock timeout on the streamed reply (incl. local oMLX): a long
      // reasoning/thinking generation streams for as long as it needs. A crashed
      // connection ends the stream / throws (handled) and Cancel aborts, so the
      // fixed cap only ever killed working generations.
      final response = await client.send(request);

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        String errorMsg = 'HTTP ${response.statusCode}';
        try {
          final errJson = jsonDecode(body);
          errorMsg = errJson['error']?['message'] ?? errorMsg;
        } catch (_) {}
        throw Exception('API error: $errorMsg');
      }

      // Parse SSE stream
      String buffer = '';
      await for (final chunk in response.stream.transform(utf8.decoder)) {
        buffer += chunk;

        // Process complete lines
        while (buffer.contains('\n')) {
          final idx = buffer.indexOf('\n');
          final line = buffer.substring(0, idx).trim();
          buffer = buffer.substring(idx + 1);

          if (line.isEmpty) continue;
          if (line == 'data: [DONE]' || line == 'data:[DONE]') {
            // Close reasoning block if still open
            final tail = wrapper.finish();
            if (tail.isNotEmpty) yield tail;
            return;
          }
          if (!line.startsWith('data:')) continue;

          // Handle both 'data: {...}' and 'data:{...}' (LM Studio omits the space)
          final data = line.startsWith('data: ')
              ? line.substring(6)
              : line.substring(5);
          try {
            final json = jsonDecode(data);
            final choice = json['choices']?[0];
            final delta = choice?['delta'];
            if (delta == null) continue;

            // Handle reasoning content (thinking tokens)
            // OpenRouter uses 'reasoning', LM Studio/OpenAI uses 'reasoning_content'
            final reasoning = delta['reasoning'] ?? delta['reasoning_content'];
            if (reasoning != null &&
                reasoning is String &&
                reasoning.isNotEmpty) {
              final out = wrapper.onReasoning(reasoning);
              if (out.isNotEmpty) yield out;
              continue;
            }

            // Handle regular content — closes an open reasoning block first
            final content = delta['content'];
            if (content != null && content is String && content.isNotEmpty) {
              final out = wrapper.onContent(content);
              if (out.isNotEmpty) yield out;
            }
          } catch (_) {
            // Skip malformed chunks
          }
        }
      }

      // Process any remaining data in the buffer (last chunk may lack trailing newline)
      final remaining = buffer.trim();
      if (remaining.isNotEmpty && remaining.startsWith('data:')) {
        final data = remaining.startsWith('data: ')
            ? remaining.substring(6)
            : remaining.substring(5);
        if (data != '[DONE]') {
          try {
            final json = jsonDecode(data);
            final choice = json['choices']?[0];
            final delta = choice?['delta'];
            if (delta != null) {
              final reasoning =
                  delta['reasoning'] ?? delta['reasoning_content'];
              if (reasoning != null &&
                  reasoning is String &&
                  reasoning.isNotEmpty) {
                final out = wrapper.onReasoning(reasoning);
                if (out.isNotEmpty) yield out;
              }
              final content = delta['content'];
              if (content != null && content is String && content.isNotEmpty) {
                final out = wrapper.onContent(content);
                if (out.isNotEmpty) yield out;
              }
            }
          } catch (_) {}
        }
      }

      // Close reasoning block if stream ended without [DONE]
      final tail = wrapper.finish();
      if (tail.isNotEmpty) yield tail;
    } finally {
      _activeClient = null;
      client.close();
    }
  }

  @override
  void abortGeneration() {
    _activeClient?.close();
    _activeClient = null;
  }
}
