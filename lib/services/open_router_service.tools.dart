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

part of 'open_router_service.dart';

/// Shared chat payload, tools transport, and style retry.
extension OpenRouterServiceTools on OpenRouterService {
  /// Chat-completions payload shared by [generateStream] and
  /// [generateWithTools] (one builder, so the two paths can't drift).
  Map<String, dynamic> _chatPayload(
    GenerationParams params, {
    required bool stream,
  }) {
    // Role-separated messages; user content is a plain string or, when
    // images ride along, a multimodal array (see openAiUserContent /
    // attachOpenAiImagesToLastUser for Waifu's custom chatMessages).
    final messages = params.openAiMessages;

    // api.openai.com rejects unknown parameters outright, so it keeps the
    // old conservative payload (frequency_penalty approximation, no
    // extensions). Everyone else (OpenRouter, Nano-GPT, vLLM, LM Studio)
    // supports or ignores the native sampler fields.
    final strictOpenAi = _apiUrl.contains('openai.com');
    // Mandatory-reasoning models spend `max_tokens` on the think they cannot
    // switch off, so an eval's 4000 cap was regularly consumed mid-think and
    // the answer (content JSON or tool call) never arrived — the intermittent
    // "no deltas" on Kimi 2.6:thinking. Evals (salvageReasoning) and chargen
    // (mandatoryReasoningHeadroom) get think headroom on such models;
    // chat/Continue keep the caller's cap (the think is excluded there and
    // reply length is the user's setting). Headroom does NOT drop exclude.
    final maxTokens =
        (params.salvageReasoning || params.mandatoryReasoningHeadroom) &&
            reasoningCannotDisable(modelName)
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
      if (params.reasoningEnabled && params.reasoningEffort.isNotEmpty) {
        // Empty effort (Waifu) omits the key so GLM 5.3 is not rewritten
        // from Low to High. Chat still sends a real effort and remaps.
        reasoning['effort'] = wireReasoningEffort(
          modelName,
          params.reasoningEffort,
        );
      }
      if (params.reasoningMaxTokens != null) {
        // GLM 5.3 (Nano) 400s `max_tokens: 0` as "disabling reasoning"
        // the same way it 400s `enabled: false`. After we remember the
        // model, a salvage retry that still sends 0 falls back to XML
        // and the XML round 400s twice more. Omit the zero budget.
        final zeroOff =
            params.reasoningMaxTokens == 0 && reasoningCannotDisable(modelName);
        if (!zeroOff) {
          reasoning['max_tokens'] = params.reasoningMaxTokens;
        }
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
        }
        // Evals need the think channel whenever the provider still thinks:
        // exclude:true leaves content empty after a long think (Kimi 2.6,
        // 2026-08-15; Grok/Gemini/DeepSeek on OpenRouter, 2026-09). Chat
        // Continue still excludes.
        if (params.salvageReasoning) reasoning.remove('exclude');
      }
      if (reasoning.isNotEmpty) {
        payload['reasoning'] = reasoning;
      }
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
      final budget = thinkingBudgetForRequest(
        model: _modelName,
        thinkOn: thinkOn,
        reasoningMaxTokens: params.reasoningMaxTokens,
      );
      if (budget != null) payload['thinking_budget'] = budget;
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

  /// OpenAI tools: null = unusable; throw = transport failure.
  Future<LlmToolResponse?> _generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    if (!isReady) return null;
    final client = httpClientFactory?.call() ?? http.Client();
    _activeClients.add(client);
    try {
      if (isOpenRouterApiUrl(_apiUrl)) {
        return await runOpenRouterNativeTools(
          apiUrl: _apiUrl,
          modelName: _modelName,
          params: params,
          tools: tools,
          client: client,
          headers: _chatHeaders,
          chatPayload: _chatPayload,
        );
      }
      final identity = params.backendIdentity.isEmpty
          ? '$backendName|$_modelName|'
          : params.backendIdentity;
      final streaming = params.onChunk != null;
      final payload = _chatPayload(params, stream: streaming);
      if (streaming) {
        String? streamErr;
        int? streamStatus;
        final thinkOn =
            params.reasoningEnabled && params.reasoningMaxTokens != 0;
        final streamed = await streamOpenAiChatToolsWithStyleRetry(
          identity: identity,
          tools: tools,
          toolChoice: params.toolChoice,
          basePayload: payload,
          uri: Uri.parse('$_apiUrl/chat/completions'),
          headers: _chatHeaders,
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
            _thinkingOffRejected(status, params, rejected)) {
          rememberMandatoryReasoning(modelName);
          debugPrint(
            '[RemoteAPI] $modelName cannot disable reasoning — retrying '
            'streamed tool call with reasoning.exclude only',
          );
          return await generateWithTools(params, tools);
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
          return await generateWithTools(params, tools);
        }
        return null;
      }
      final response = await attachToolsWithStyleRetry(
        identity: identity,
        tools: tools,
        toolChoice: params.toolChoice,
        basePayload: payload,
        post: (payload) => client.post(
          Uri.parse('$_apiUrl/chat/completions'),
          headers: _chatHeaders,
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
        final err = openRouterApiErrorMessage(
          response.body,
          response.statusCode,
        );
        if (_thinkingOffRejected(response.statusCode, params, err)) {
          rememberMandatoryReasoning(modelName);
          debugPrint(
            '[RemoteAPI] $modelName cannot disable reasoning — retrying '
            'tool call with reasoning.exclude only',
          );
          return await generateWithTools(params, tools);
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
          return await generateWithTools(params, tools);
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
      _activeClients.remove(client);
      client.close();
    }
  }
}
