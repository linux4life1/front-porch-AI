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

/// Metadata for a remote model, including pricing.
class RemoteModelInfo {
  final String id;
  final String name;
  final double? promptCostPerMillion; // USD per 1M input tokens
  final double? completionCostPerMillion; // USD per 1M output tokens

  const RemoteModelInfo({
    required this.id,
    this.name = '',
    this.promptCostPerMillion,
    this.completionCostPerMillion,
  });

  /// Human-readable pricing string, e.g. "$0.50 / $1.50"
  String get pricingLabel {
    if (promptCostPerMillion == null && completionCostPerMillion == null) {
      return 'Pricing unavailable';
    }
    final input = promptCostPerMillion != null
        ? '\$${promptCostPerMillion!.toStringAsFixed(2)}'
        : '?';
    final output = completionCostPerMillion != null
        ? '\$${completionCostPerMillion!.toStringAsFixed(2)}'
        : '?';
    return '$input in / $output out per 1M tokens';
  }

  bool get isFree =>
      (promptCostPerMillion == null || promptCostPerMillion == 0) &&
      (completionCostPerMillion == null || completionCostPerMillion == 0);
}

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

  @override
  bool get isReady {
    if (!_isReady || _modelName.isEmpty) return false;
    // Allow empty API key for local backends (LM Studio, vLLM, etc.)
    final isLocal =
        _apiUrl.contains('localhost') || _apiUrl.contains('127.0.0.1');
    return _apiKey.isNotEmpty || isLocal;
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
    final isLocal =
        apiUrl.contains('localhost') || apiUrl.contains('127.0.0.1');
    _isReady = (_apiKey.isNotEmpty || isLocal) && _modelName.isNotEmpty;
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
    final isLocal =
        _apiUrl.contains('localhost') || _apiUrl.contains('127.0.0.1');
    final newReady = (_apiKey.isNotEmpty || isLocal) && _modelName.isNotEmpty;
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
  Future<String> testConnection() async {
    if (_apiUrl.isEmpty) return 'API URL is empty.';
    // Allow empty API key for local backends (localhost / 127.0.0.1)
    final isLocal =
        _apiUrl.contains('localhost') || _apiUrl.contains('127.0.0.1');
    if (_apiKey.isEmpty && !isLocal) return 'API key is empty.';

    final client = http.Client();
    try {
      final uri = Uri.parse('$_apiUrl/models');
      final response = await client
          .get(uri, headers: {'Authorization': 'Bearer $_apiKey'})
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
  Future<List<RemoteModelInfo>> fetchAvailableModels() async {
    if (_apiUrl.isEmpty) return [];
    final isLocal =
        _apiUrl.contains('localhost') || _apiUrl.contains('127.0.0.1');
    if (_apiKey.isEmpty && !isLocal) return [];

    final client = http.Client();
    try {
      final uri = Uri.parse('$_apiUrl/models');
      debugPrint('[OpenRouter] Fetching models from: $uri');
      final response = await client
          .get(
            uri,
            headers: {
              if (_apiKey.isNotEmpty) 'Authorization': 'Bearer $_apiKey',
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

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (!isReady) {
      throw Exception(
        'Remote API not configured. Please set API key and model.',
      );
    }

    final uri = Uri.parse('$_apiUrl/chat/completions');

    // Build messages array with proper role separation for chat APIs.
    final messages = <Map<String, String>>[];
    if (params.systemPrompt != null && params.systemPrompt!.isNotEmpty) {
      messages.add({'role': 'system', 'content': params.systemPrompt!});
    }
    messages.add({'role': 'user', 'content': params.prompt});

    final payload = <String, dynamic>{
      'model': _modelName,
      'stream': true,
      'max_tokens': params.maxLength,
      'temperature': params.temperature,
      'top_p': params.topP,
      'frequency_penalty': params.repeatPenalty > 1.0
          ? (params.repeatPenalty - 1.0).clamp(0.0, 2.0)
          : 0.0,
      'messages': messages,
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

    // Add stop sequences if present
    if (params.stopSequences != null && params.stopSequences!.isNotEmpty) {
      // OpenAI API supports max 4 stop sequences
      payload['stop'] = params.stopSequences!.take(4).toList();
    }

    final request = http.Request('POST', uri);
    request.headers['Content-Type'] = 'application/json';
    request.headers['Authorization'] = 'Bearer $_apiKey';
    // Identify the app for providers that support it
    request.headers['HTTP-Referer'] =
        'https://github.com/linux4life1/front-porch-AI';
    request.headers['X-Title'] = 'Front Porch AI';
    request.body = jsonEncode(payload);

    final client = http.Client();
    _activeClient = client;
    bool hasYieldedReasoningStart = false;
    bool hasYieldedReasoningEnd = false;
    // Only wrap reasoning in <think> tags when the app explicitly requested it.
    // Some models (e.g. Qwen on LM Studio) send the entire response as
    // reasoning_content even when reasoning wasn't requested — wrapping those
    // in <think> tags would hide the response entirely.
    final wrapThinking = params.reasoningEnabled;

    try {
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 120));

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
            if (wrapThinking &&
                hasYieldedReasoningStart &&
                !hasYieldedReasoningEnd) {
              yield '</think>\n';
            }
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
              if (wrapThinking) {
                if (!hasYieldedReasoningStart) {
                  yield '<think>';
                  hasYieldedReasoningStart = true;
                }
                yield reasoning;
              } else {
                // Reasoning wasn't requested (e.g. forced off for Continue to match SillyTavern behavior).
                // Discard it entirely instead of yielding as content. This prevents thinking text
                // from leaking into the visible character response even if the model/provider
                // still emits some reasoning deltas.
              }
              continue;
            }

            // Handle regular content — close reasoning block first if needed
            final content = delta['content'];
            if (content != null && content is String && content.isNotEmpty) {
              if (wrapThinking &&
                  hasYieldedReasoningStart &&
                  !hasYieldedReasoningEnd) {
                yield '</think>\n';
                hasYieldedReasoningEnd = true;
              }
              yield content;
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
                // Only yield if we actually requested/wrapped reasoning.
                // Otherwise discard (SillyTavern-style strict handling for unrequested reasoning).
                if (wrapThinking) {
                  yield reasoning;
                }
              }
              final content = delta['content'];
              if (content != null && content is String && content.isNotEmpty) {
                yield content;
              }
            }
          } catch (_) {}
        }
      }

      // Close reasoning block if stream ended without [DONE]
      if (wrapThinking && hasYieldedReasoningStart && !hasYieldedReasoningEnd) {
        yield '</think>\n';
      }
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
