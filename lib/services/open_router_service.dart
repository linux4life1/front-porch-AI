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
import 'package:front_porch_ai/services/reasoning_effort.dart';
import 'package:front_porch_ai/services/reasoning_stream_wrapper.dart';
import 'package:front_porch_ai/services/remote_model_info.dart';
import 'package:front_porch_ai/services/remote_reachability.dart';

// RemoteModelInfo lived here for years — re-export so importers keep working.
export 'package:front_porch_ai/services/remote_model_info.dart';

/// Does this provider error mean "you may not switch my reasoning off"?
///
/// Matched on the message rather than a status code because 400 covers every
/// malformed-request case; keyed on the two words every provider phrasing so
/// far shares. Nano-GPT: "Kimi K2 Thinking is a mandatory-reasoning model. Use
/// reasoning.exclude=true to hide reasoning output." Deliberately narrow — a
/// false positive here would silently stop us disabling reasoning on a model
/// that supports it, which costs the user tokens on every eval forever.
bool _isMandatoryReasoningRejection(String msg) {
  final m = msg.toLowerCase();
  return m.contains('reasoning') &&
      (m.contains('mandatory') ||
          m.contains('cannot be disabled') ||
          m.contains('exclude=true'));
}

/// Pull a human error string out of a provider JSON body (or the raw body).
/// Several Nano/OpenRouter shapes exist; we try them all so the effort
/// learn-path is not skipped just because the envelope moved.
String _remoteApiErrorMessage(String body, int statusCode) {
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
  // Plain-text / HTML body still carries the effort rejection wording.
  return body.length > 800 ? '${body.substring(0, 800)}…' : body;
}

/// LLM backend for OpenAI-compatible APIs (OpenRouter, Nano-GPT, vLLM, …).
class OpenRouterService extends LLMService {
  String _apiUrl;
  String _apiKey;
  String _modelName;
  final RemoteApiHealth _health = RemoteApiHealth();

  /// Every client with a call in flight, so [abortGeneration] can close all of
  /// them. A SET rather than one slot because this is a single shared instance
  /// and the app deliberately overlaps remote calls on it (the staggered
  /// realism judges, post-gen needs + reply-facts): with one slot the first
  /// call to finish cleared the field, and Cancel then closed nothing while
  /// the rest kept streaming (and billing).
  final Set<http.Client> _activeClients = {};

  /// Test seam: a MockClient so reachability tests never hit the network.
  http.Client Function()? get httpClientFactory => _health.httpClientFactory;
  set httpClientFactory(http.Client Function()? factory) =>
      _health.httpClientFactory = factory;

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

    // Same seam as [refreshReachability]: tests inject a MockClient so
    // this never hits the network (flutter test HttpOverrides is a
    // bodiless 400, which used to empty the picker and flip isReady).
    final client = httpClientFactory?.call() ?? http.Client();
    final owned = httpClientFactory == null;
    var batched = false;
    try {
      final uri = Uri.parse('$url/models');
      debugPrint('[OpenRouter] Fetching models from: $uri');
      final response = await client
          .get(
            uri,
            headers: {if (key.isNotEmpty) 'Authorization': 'Bearer $key'},
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
      beginReasoningEffortCatalogBatch();
      batched = true;
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
        if (m is Map) {
          rememberReasoningProfileFromCatalog(id, m['reasoning']);
        }
        // `m` is dynamic, so indexing a plain-String entry dispatches to
        // String.operator[](int) and THROWS — which aborted the whole loop and
        // emptied the picker for any backend answering {"models":["llama-3"]},
        // the very shape the `m is String` branch above exists to support.
        final pricing = m is Map ? m['pricing'] : null;

        // API returns USD per token; convert to per 1M tokens for readability
        double? promptCost;
        double? completionCost;
        if (pricing is Map) {
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
      if (batched) endReasoningEffortCatalogBatch();
      if (owned) client.close();
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
    // Mandatory-reasoning models spend `max_tokens` on the think they cannot
    // switch off, so an eval's 4000 cap was regularly consumed mid-think and
    // the answer (content JSON or tool call) never arrived — the intermittent
    // "no deltas" on Kimi 2.6:thinking. Evals (salvageReasoning) get think
    // headroom on such models; chat/Continue keep the caller's cap (the think
    // is excluded there and reply length is the user's setting).
    final maxTokens =
        params.salvageReasoning && reasoningCannotDisable(modelName)
        ? params.maxLength + kMandatoryReasoningThinkHeadroomTokens
        : params.maxLength;
    final payload = <String, dynamic>{
      'model': _modelName,
      'stream': stream,
      'max_tokens': maxTokens,
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
      final reasoning = <String, dynamic>{'enabled': params.reasoningEnabled};
      if (params.reasoningEnabled) {
        // User setting stays in prefs; wire value may adapt (learned 400 or
        // :thinking suffix hint — see wireReasoningEffort).
        reasoning['effort'] = wireReasoningEffort(
          modelName,
          params.reasoningEffort,
        );
      }
      if (params.reasoningMaxTokens != null) {
        reasoning['max_tokens'] = params.reasoningMaxTokens;
      }
      // When suppressing reasoning (e.g. Continue with budget 0), also ask the provider
      // to exclude reasoning tokens from the response entirely. This matches how SillyTavern
      // handles "Request model reasoning" = off for OpenRouter models.
      if (!params.reasoningEnabled) {
        reasoning['exclude'] = true;
        // MANDATORY-REASONING MODELS REJECT `enabled:false` OUTRIGHT.
        //
        // The two keys do different jobs: `enabled:false` stops the model
        // thinking (saves tokens), `exclude:true` merely keeps the thoughts out
        // of the response. A model whose reasoning cannot be switched off 400s
        // the first and is perfectly happy with the second — its own error says
        // so: "Kimi K2 Thinking is a mandatory-reasoning model. Use
        // reasoning.exclude=true to hide reasoning output."
        //
        // This is not cosmetic. EVERY eval suppresses reasoning (they want flat
        // JSON, not think-blocks), so on such a model every judge 400s, twice
        // each with the retry — relationship, emotional, narrative, needs-impact
        // and objective-completion all fail, and the maintainer sees "no deltas,
        // emotion sticking across messages" with bond_delta=null on every turn
        // while needs quietly fall back to plain decay. Reported 2026-08-08.
        //
        // Learned per model rather than dropped for everyone: `enabled:false` is
        // what actually saves money on models that honour it, and silently
        // paying for discarded reasoning tokens on every eval, forever, is a bill
        // the user never agreed to. One rejection per model is the whole cost.
        if (reasoningCannotDisable(modelName)) {
          reasoning.remove('enabled');
          // Evals need the think channel: Kimi 2.6:thinking puts the JSON
          // there, and exclude:true leaves content as a newline after a
          // long think (2026-08-15). Chat Continue still excludes.
          if (params.salvageReasoning) reasoning.remove('exclude');
        }
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
      final thinkOn = params.reasoningEnabled && params.reasoningMaxTokens != 0;
      payload['chat_template_kwargs'] = {'enable_thinking': thinkOn};
      // Heretic / uncensored templates `{% set enable_thinking = true %}`
      // overwrite the kwarg. oMLX and llama.cpp honour thinking_budget: 0
      // as a decode-time force-close (mlx-lm handles budget=0; oMLX's
      // Gemma parser supplies the `<channel|>` end token). Same thinkOn
      // bit as above, so Continue / call mode / evals clamp and a normal
      // reply with Request thinking on does not. Omitted on stock
      // templates — sending 0 on Gemma-4 that already honours the kwarg
      // attaches the closer processor and can leak into the answer.
      final clamp = thinkingBudgetClampForThinkOff(
        _modelName,
        thinkOn: thinkOn,
      );
      if (clamp != null) payload['thinking_budget'] = clamp;
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

  /// OpenAI-style tool calling (non-streaming). Null = answered unusable;
  /// throw = transport failure. Named `tool_choice` rides [params.toolChoice]
  /// so the mandatory-reasoning retry forwards it by passing the same params.
  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    if (!isReady) return null;
    final client = http.Client();
    _activeClients.add(client);
    try {
      final identity = params.backendIdentity.isEmpty
          ? '$backendName|$_modelName|'
          : params.backendIdentity;
      final response = await attachToolsWithStyleRetry(
        identity: identity,
        tools: tools,
        toolChoice: params.toolChoice,
        basePayload: _chatPayload(params, stream: false),
        post: (payload) => client.post(
          Uri.parse('$_apiUrl/chat/completions'),
          headers: _chatHeaders,
          body: jsonEncode(payload),
        ),
      );
      if (response.statusCode == 429 || response.statusCode >= 500) {
        // Rate-limited / provider hiccup: transient, not a capability
        // verdict — must not brand the model tool-less for the run.
        throw LlmToolTransportException(
          'tool call HTTP ${response.statusCode} (server busy/unavailable)',
        );
      }
      if (response.statusCode != 200) {
        final err = _remoteApiErrorMessage(response.body, response.statusCode);
        if (!reasoningCannotDisable(modelName) &&
            _isMandatoryReasoningRejection(err)) {
          rememberMandatoryReasoning(modelName);
          debugPrint(
            '[RemoteAPI] $modelName cannot disable reasoning — retrying '
            'tool call with reasoning.exclude only',
          );
          return await generateWithTools(params, tools);
        }
        debugPrint(
          '[RemoteAPI] Tool call rejected (HTTP ${response.statusCode}) — '
          'falling back to text transport: $err',
        );
        return null;
      }
      // A tool call cut by max_tokens comes back as a clean 200 with no
      // tool_calls and no content — downstream that reads as "inconclusive,
      // fall back to text" with no trace. Name it in the log.
      if (RegExp(r'"finish_reason"\s*:\s*"length"').hasMatch(response.body)) {
        debugPrint(
          '[RemoteAPI] $modelName tool call hit max_tokens '
          '(finish_reason=length) — likely truncated mid-think, no tool call',
        );
      }
      return parseOpenAiToolResponse(response.body);
    } catch (e) {
      // Rethrow instead of collapsing to null — a killed connection must not
      // read as "model can't speak tools" (it branded the backend XML-only
      // for the whole run). Callers filter via looksLikeBackendUnreachable.
      debugPrint('[RemoteAPI] Tool call transport failure: $e');
      rethrow;
    } finally {
      _activeClients.remove(client);
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

    final client = http.Client();
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
        final errorMsg = _remoteApiErrorMessage(body, response.statusCode);
        // A mandatory-reasoning model refusing `reasoning:{enabled:false}`.
        // Remember it and RETRY ONCE right here rather than just throwing:
        // without the retry the caller still loses this eval, and for the
        // reported case that is every judge on the turn the user is waiting on.
        // The rejection then costs one round trip for the life of the process.
        if (!reasoningCannotDisable(modelName) &&
            _isMandatoryReasoningRejection(errorMsg)) {
          rememberMandatoryReasoning(modelName);
          debugPrint(
            '[RemoteAPI] $modelName cannot disable reasoning — retrying with '
            'reasoning.exclude only (remembered for this session)',
          );
          yield* generateStream(params);
          return;
        }
        // The provider re-tiered this model's reasoning.effort values under
        // us (DeepSeek v4-flash:thinking dropped low/medium, 2026-07-18) and
        // its 400 names the values it still takes. Same learn-once-and-retry
        // as the mandatory-reasoning case above: remember the supported set,
        // let the payload builder substitute the closest one, and retry right
        // here so the turn the user is waiting on still completes. The
        // containsKey guard makes a second rejection for the same model
        // throw instead of loop. Parse message AND raw body — some providers
        // put the listing only in one of the two.
        final supportedEfforts =
            supportedReasoningEffortsFromError(errorMsg) ??
            supportedReasoningEffortsFromError(body);
        if (supportedEfforts != null &&
            !kLearnedReasoningEffortsByModel.containsKey(modelName)) {
          rememberReasoningEffortsForModel(modelName, supportedEfforts);
          debugPrint(
            '[RemoteAPI] $modelName rejected reasoning.effort '
            '"${params.reasoningEffort}" — provider supports '
            '${supportedEfforts.join('/')}; retrying with '
            '"${nearestReasoningEffort(params.reasoningEffort, supportedEfforts)}" '
            '(remembered for this session)',
          );
          yield* generateStream(params);
          return;
        }
        // Already learned / hinted but still rejected — allow one overwrite
        // when the provider's new listing differs (re-tier mid-session).
        if (supportedEfforts != null) {
          final prev = kLearnedReasoningEffortsByModel[modelName];
          final same =
              prev != null &&
              prev.length == supportedEfforts.length &&
              prev.containsAll(supportedEfforts);
          if (!same) {
            rememberReasoningEffortsForModel(modelName, supportedEfforts);
            debugPrint(
              '[RemoteAPI] $modelName re-tiered reasoning.effort again — '
              'now ${supportedEfforts.join('/')}; retrying once',
            );
            yield* generateStream(params);
            return;
          }
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
            // The cut-mid-think signature: on a mandatory-reasoning model
            // this is exactly "the eval will have no deltas this turn".
            // One glance at the log now names the failure class.
            if (choice?['finish_reason'] == 'length') {
              debugPrint(
                '[RemoteAPI] $modelName hit max_tokens '
                '(finish_reason=length) — response truncated',
              );
            }
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
      _activeClients.remove(client);
      client.close();
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
          'API error: ${_remoteApiErrorMessage(body, response.statusCode)}',
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
