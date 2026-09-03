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
import 'package:front_porch_ai/services/chat/chat.dart'
    show kMaxLocalServerStops;
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/llm_tool_parsing.dart';
import 'package:front_porch_ai/services/openai_tool_payload.dart';
import 'package:front_porch_ai/services/reasoning_effort.dart';
import 'package:front_porch_ai/services/reasoning_stream_wrapper.dart';
import 'package:front_porch_ai/services/system_role_probe.dart';
import 'package:front_porch_ai/services/tool_choice_style_probe.dart';

/// Streams an OpenAI-compatible `/v1/chat/completions` response token by token.
///
/// This is the single transport shared by every backend that speaks the OpenAI
/// chat protocol: the `.kcpps` pseudo-remote backend and the managed local
/// KoboldCpp backend both point it at `http://127.0.0.1:5001`.
///
/// Why this matters for local KoboldCpp: KoboldCpp serves this endpoint on the
/// same port as its native API and applies the loaded model's instruct/chat
/// template server-side — which the raw `/api/extra/generate/stream` endpoint
/// does NOT. Routing local generation here is what lets instruct GGUFs follow
/// instructions (character cards, realism evals) and stop naturally via EOS,
/// instead of emitting an immediate empty response or running away repeating on
/// an un-templated prompt.
///
/// [baseUrl] is the server root WITHOUT a trailing slash (e.g.
/// `http://127.0.0.1:5001`); `/v1/chat/completions` is appended here. KoboldCpp
/// ignores [modelName] (it serves the single loaded model), so a placeholder is
/// fine. [registerClient] hands the live [http.Client] to the caller so an abort
/// can close it; [onDone] fires in `finally` so the caller can clear its handle.
///
/// Kept intentionally minimal and identical to the long-proven pseudo-remote
/// path: a single `user` message (plus optional `system`), `frequency_penalty`
/// derived from `repeatPenalty`, and the model's own template doing the rest.
/// Chat-completions payload shared by [streamOpenAiChat] and
/// [postOpenAiChatWithTools] — one builder so the two paths can't drift.
///
/// [foldSystemIntoUser] is the escape hatch for backends the [SystemRoleProbe]
/// caught silently DISCARDING the leading system message — the `--jinja`
/// defect where a GGUF whose chat template has no system branch answers HTTP
/// 200 while the character card, persona, scenario and state blocks never
/// reach the model. When set, the same text is prepended to the user content
/// instead. See [foldSystemIntoUserContent] for why that trade is worth
/// making.
Map<String, dynamic> _chatPayload(
  GenerationParams params, {
  required String modelName,
  required bool stream,
  bool foldSystemIntoUser = false,
  String? thinkingModelKey,
}) {
  // Object-valued so the user content can be a plain string (text-only —
  // byte-identical to the pre-vision payload) or a multimodal array when
  // GenerationParams.images rides along (KoboldCpp accepts the OpenAI
  // image_url shape on this endpoint when an mmproj is loaded).
  final messages = <Map<String, Object>>[];
  final system = params.systemPrompt;
  var userContent = params.openAiUserContent;
  if (system != null && system.isNotEmpty) {
    if (foldSystemIntoUser) {
      userContent = foldSystemIntoUserContent(system, userContent);
    } else {
      messages.add({'role': 'system', 'content': system});
    }
  }
  messages.add({'role': 'user', 'content': userContent});

  final payload = <String, dynamic>{
    'model': modelName,
    'stream': stream,
    'max_tokens': params.maxLength,
    'temperature': params.temperature,
    'top_p': params.topP,
    'messages': messages,
    // KoboldCpp accepts its native sampler fields on /v1/chat/completions
    // (same handler as the classic API), so the sliders actually reach the
    // model. This replaced a lossy frequency_penalty≈rep_pen−1 conversion
    // that both mistranslated Rep Pen and silently dropped everything else.
    'min_p': params.minP,
    'rep_pen': params.repeatPenalty,
    'rep_pen_range': params.repPenTokens,
    'xtc_threshold': params.xtcThreshold,
    'xtc_probability': params.xtcProbability,
    if (params.topK > 0) 'top_k': params.topK,
    if (params.dynatempRange != null) 'dynatemp_range': params.dynatempRange,
    if (params.dryMultiplier > 0) ...{
      // Standard DRY companions (KoboldCpp defaults, stated explicitly).
      'dry_multiplier': params.dryMultiplier,
      'dry_base': 1.75,
      'dry_allowed_length': 2,
      'dry_sequence_breakers': ['\n', ':', '"', '*'],
    },
    if (params.bannedPhrases != null && params.bannedPhrases!.isNotEmpty)
      'banned_tokens': params.bannedPhrases,
  };

  // KoboldCpp reasoning controls. Kobold IGNORES the OpenRouter-style
  // `reasoning:{enabled,effort}` object (verified against its release notes /
  // koboldcpp.py), so we use Kobold's native fields:
  //   • chat_template_kwargs.enable_thinking — the model's own Jinja on/off
  //     switch. This ONLY takes effect because the managed backend now launches
  //     with `--jinja` (see kobold_service.dart), which makes Kobold execute the
  //     GGUF's embedded chat template instead of its built-in string adapter —
  //     without it, this field is silently discarded and thinking never fires.
  //   • reasoning_effort — think-token budget (none|low|medium|high); the app's
  //     effort strings map 1:1.
  // We deliberately do NOT send `encapsulate_thinking:false` anymore. In jinja
  // mode Kobold splits the model's thinking into the standard `reasoning_content`
  // field and leaves `content` as the clean final answer — the SAME shape the
  // OpenRouter/oMLX path returns. streamOpenAiChat consumes reasoning_content and
  // re-wraps it in <think>…</think> via the shared ReasoningTagWrapper, so both
  // transports converge on one parser. (encapsulate_thinking:false was the old
  // hack that kept thinking in `content`, but it only understood <think> tags;
  // channel-format reasoners like Gemma-4 dumped raw channel markers instead.)
  //
  // ALWAYS emit an explicit decision — the app owns the setting, and the UI says
  // reasoning "off" discards thinking. enable_thinking:false genuinely suppresses
  // it in jinja mode (verified). reasoningMaxTokens==0 is the Continue/eval
  // hard-suppress signal.
  final thinkOn = params.reasoningEnabled && params.reasoningMaxTokens != 0;
  payload['chat_template_kwargs'] = {'enable_thinking': thinkOn};
  payload['reasoning_effort'] = thinkOn
      ? (params.reasoningEffort.isEmpty ? 'high' : params.reasoningEffort)
      : 'none';
  // Same clamp as OpenRouterService for heretic templates that `{% set
  // enable_thinking = true %}`. llama.cpp / recent Kobold honour
  // thinking_budget: 0 as a force-close; omitted when the GGUF actually
  // reads the kwarg (stock Gemma-4).
  final clamp = thinkingBudgetClampForThinkOff(
    thinkingModelKey ?? modelName,
    thinkOn: thinkOn,
  );
  if (clamp != null) payload['thinking_budget'] = clamp;

  if (params.stopSequences != null && params.stopSequences!.isNotEmpty) {
    // This transport only ever talks to KoboldCpp (managed local +
    // pseudo-remote), which maps `stop` onto its native stop_sequence
    // machinery (stop_token_max = 256 since v1.77; 16 is a safe floor for
    // older builds). The old OpenAI-spec take(4) meant the shipped default
    // stops filled every slot and custom/name stops never reached the server
    // — the client-side trim hid it while the server generated on. The list
    // arrives priority-ordered (stop_sequences.dart).
    payload['stop'] = params.stopSequences!.take(kMaxLocalServerStops).toList();
  }
  return payload;
}

/// Non-streaming, tool-enabled chat completion against the same local
/// endpoint — the local-backend implementation of
/// [LLMService.generateWithTools]. Recent KoboldCpp versions support OpenAI
/// tool calling with template-aware models (Qwen3 family and friends); older
/// servers or non-tool models simply produce no tool calls and the Journal's
/// transport negotiation falls back to (and remembers) the XML floor.
/// Returns null when the server ANSWERED but the call yielded nothing usable
/// (a definitive non-200 such as 400/404); transport failures (socket down,
/// client torn down by an app-side abortGeneration, busy/5xx server) THROW so
/// callers can tell a network event apart from a capability verdict — see the
/// [LLMService.generateWithTools] contract.
Future<LlmToolResponse?> postOpenAiChatWithTools(
  String baseUrl,
  GenerationParams params,
  List<Map<String, dynamic>> tools, {
  String modelName = 'koboldcpp',
  String? thinkingModelKey,
  bool foldSystemIntoUser = false,
  void Function(http.Client client)? registerClient,
  void Function()? onDone,
  String? toolChoice,
  ToolChoiceStyleProbe? styleProbe,
}) async {
  final client = http.Client();
  registerClient?.call(client);
  try {
    // No wall-clock timeout: a tool/eval call against a local model can take
    // as long as the generation legitimately needs (a slow model, a large
    // token budget, or a reasoning pass). A dead/crashed backend closes the
    // socket (which throws and is handled), and the user's Cancel aborts an
    // in-flight call — so a fixed cap only ever killed work that was fine.
    // Local HTTP max_tokens stays params.maxLength — do NOT add remote
    // think headroom via reasoningCannotDisable(path).
    final identity = params.backendIdentity.isEmpty
        ? (thinkingModelKey ?? modelName)
        : params.backendIdentity;
    final response = await attachToolsWithStyleRetry(
      identity: identity,
      tools: tools,
      toolChoice: toolChoice ?? params.toolChoice,
      basePayload: _chatPayload(
        params,
        modelName: modelName,
        stream: false,
        foldSystemIntoUser: foldSystemIntoUser,
        thinkingModelKey: thinkingModelKey,
      ),
      probe: styleProbe,
      post: (payload) => client.post(
        Uri.parse('$baseUrl/v1/chat/completions'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ),
    );
    if (response.statusCode == 429 || response.statusCode >= 500) {
      // Busy/unavailable is transient (e.g. a non-multiuser KoboldCpp mid-
      // generation answers 503) — surface it as a transport failure so the
      // probe doesn't brand the model tool-less for the run.
      throw LlmToolTransportException(
        'tool call HTTP ${response.statusCode} (server busy/unavailable)',
      );
    }
    if (response.statusCode != 200) {
      debugPrint(
        '[OpenAiChat] Tool call rejected (HTTP ${response.statusCode}) — '
        'falling back to text transport',
      );
      return null;
    }
    if (RegExp(r'"finish_reason"\s*:\s*"length"').hasMatch(response.body)) {
      debugPrint(
        '[OpenAiChat] tool call hit max_tokens (finish_reason=length)',
      );
    }
    return parseOpenAiToolResponse(response.body);
  } catch (e) {
    // Rethrow instead of collapsing to null: a torn-down connection (e.g.
    // CharacterGenService firing abortGeneration while a background pass's
    // tool call is in flight) used to look identical to "model can't speak
    // tools" and permanently branded the backend XML-only for the run.
    debugPrint('[OpenAiChat] Tool call transport failure: $e');
    rethrow;
  } finally {
    onDone?.call();
    client.close();
  }
}

Stream<String> streamOpenAiChat(
  String baseUrl,
  GenerationParams params, {
  String modelName = 'koboldcpp',
  String? thinkingModelKey,
  bool foldSystemIntoUser = false,
  void Function(http.Client client)? registerClient,
  void Function()? onDone,
}) async* {
  final uri = Uri.parse('$baseUrl/v1/chat/completions');
  final payload = _chatPayload(
    params,
    modelName: modelName,
    stream: true,
    foldSystemIntoUser: foldSystemIntoUser,
    thinkingModelKey: thinkingModelKey,
  );

  // In jinja mode Kobold splits thinking into `reasoning_content`; re-wrap it in
  // <think>…</think> for the app's parser. Armed only when thinking was actually
  // requested (matches the payload's `thinkOn`) so an off toggle / the Continue
  // + eval suppress path (reasoningMaxTokens==0) discards any stray reasoning
  // rather than leaking it into the visible reply. Evals (salvageReasoning)
  // keep the channel TAGGED instead — a local model that ignores
  // enable_thinking:false and parks its answer in reasoning_content would
  // otherwise hand the judges an empty reply (the remote Kimi 2.6 bug's
  // local twin); evals are never user-visible, so nothing can leak.
  final wrapper = ReasoningIngest(
    wrap: params.reasoningEnabled && params.reasoningMaxTokens != 0,
    salvage: params.salvageReasoning,
  );

  final request = http.Request('POST', uri);
  request.headers['Content-Type'] = 'application/json';
  request.body = jsonEncode(payload);

  final client = http.Client();
  registerClient?.call(client);

  try {
    // No wall-clock timeout on the streamed reply. Token streaming can run as
    // long as the model needs — a long reasoning/thinking block especially —
    // and capping total time just killed working generations. A crashed backend
    // closes the socket (the stream ends / throws and is handled) and the user's
    // Cancel aborts mid-stream, so the fixed 120s cap only ever hurt.
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

    String buffer = '';
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      buffer += chunk;
      while (buffer.contains('\n')) {
        final idx = buffer.indexOf('\n');
        final line = buffer.substring(0, idx).trim();
        buffer = buffer.substring(idx + 1);
        if (line.isEmpty) continue;
        if (line == 'data: [DONE]' || line == 'data:[DONE]') {
          final tail = wrapper.finish();
          if (tail.isNotEmpty) yield tail;
          return;
        }
        if (!line.startsWith('data:')) continue;
        final data = line.startsWith('data: ')
            ? line.substring(6)
            : line.substring(5);
        try {
          final json = jsonDecode(data);
          final choice = json['choices']?[0];
          final delta = choice?['delta'];
          if (delta == null) continue;
          // Reasoning tokens first (jinja-mode Kobold uses reasoning_content;
          // tolerate 'reasoning' too). A delta carrying reasoning is consumed
          // and never also treated as content, mirroring the OpenRouter path.
          final reasoning = delta['reasoning_content'] ?? delta['reasoning'];
          if (reasoning != null &&
              reasoning is String &&
              reasoning.isNotEmpty) {
            final out = wrapper.onReasoning(reasoning);
            if (out.isNotEmpty) yield out;
            continue;
          }
          final content = delta['content'];
          if (content != null && content is String && content.isNotEmpty) {
            final out = wrapper.onContent(content);
            if (out.isNotEmpty) yield out;
          }
        } catch (_) {}
      }
    }
    // Stream closed without an explicit [DONE]: close an open reasoning block.
    final tail = wrapper.finish();
    if (tail.isNotEmpty) yield tail;
  } finally {
    onDone?.call();
    client.close();
  }
}
