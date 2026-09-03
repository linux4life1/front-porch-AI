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

import 'dart:async';

import 'package:flutter/foundation.dart';

/// Generation parameters shared across all LLM backends.
class GenerationParams {
  final String prompt;
  final int maxLength;
  final int minLength;
  final double temperature;
  final double repeatPenalty;
  final double topP;
  final double minP;
  final int repPenTokens;
  final double? dynatempRange;
  final double xtcThreshold;
  final double xtcProbability;
  final List<String>? stopSequences;
  final bool reasoningEnabled;
  final String reasoningEffort;

  /// Optional maximum tokens the model may spend on its internal reasoning/thinking trace.
  /// Used by OpenRouter and compatible providers (e.g. Nano-GPT) via the `reasoning.max_tokens` field.
  /// Setting to 0 on Continue generations helps force non-thinking / direct output on models that support budget control (Kimi K2, DeepSeek hybrids, Qwen3 thinking variants, etc.).
  final int? reasoningMaxTokens;

  /// Evals only: keep reasoning-channel tokens so we can parse JSON out of
  /// them. Mandatory-reasoning models (Kimi :thinking) put the answer there
  /// and `reasoning.exclude` leaves `content` empty — a 90s think then a
  /// newline. Chat / Continue leave this false so thoughts stay hidden.
  final bool salvageReasoning;

  final List<String>? bannedPhrases;

  /// Top-K cutoff; 0 disables it (KoboldCpp and remote APIs both treat 0 as
  /// off, so it's only serialized when > 0).
  final int topK;

  /// DRY anti-repetition strength (KoboldCpp only; 0 = off).
  final double dryMultiplier;

  /// Optional system prompt for chat APIs. When provided, OpenRouter/LM Studio
  /// will send this as a proper 'system' role message instead of lumping
  /// everything into a single 'user' message. KoboldCPP ignores this field.
  final String? systemPrompt;

  /// Optional GBNF grammar string for constrained JSON output (KoboldCPP local only).
  /// Never set this when reasoning/thinking mode is active — the `<think>` block
  /// tokens would be illegal under the grammar and break generation.
  final String? grammar;

  /// When true, instructs KoboldCPP to never emit EOS mid-generation.
  /// Required for thinking models so the model can complete its `<think>` block
  /// without KoboldCPP treating the template's built-in stop tokens as EOS.
  final bool banEosToken;

  /// Controls KoboldCPP's trim_stop behaviour. Set to false for thinking models
  /// so template stop tokens (`<|im_end|>` etc.) don't silently eat the output.
  final bool trimStop;

  /// Optional base64-encoded PNG images attached to the user chat message
  /// (Vision QC, portrait describe). When non-empty, the OpenAI-compatible
  /// chat transports render the user content as a multimodal array via
  /// [openAiUserContent]; when null/empty the payload keeps the plain string
  /// content, byte-identical to the pre-vision text-only path.
  final List<String>? images;

  /// Named OpenAI `tool_choice` function, or null → `'auto'`. Rides the
  /// params object so [generateWithTools] overrides keep their two-arg
  /// signature (existing test fakes must not be edited).
  final String? toolChoice;

  /// Unused until the streaming-tools PR; forwarded on the mandatory-
  /// reasoning retry so it cannot be dropped.
  final void Function(String chunk)? onChunk;

  /// After Kobold FIFO `waitForIdle`: skip/pause/xml-only, never live
  /// prefer-text (the ping shares this door).
  final bool Function()? stillWantTools;

  /// Probe identity (`backend|model|path`). Style retry and skip/pause
  /// key on the same string [ChatService] uses.
  final String backendIdentity;

  const GenerationParams({
    required this.prompt,
    this.maxLength = 200,
    this.minLength = 0,
    this.temperature = 0.7,
    this.repeatPenalty = 1.1,
    this.topP = 0.9,
    this.minP = 0.0,
    this.topK = 0,
    this.dryMultiplier = 0.0,
    this.repPenTokens = 64,
    this.dynatempRange,
    this.xtcThreshold = 0.1,
    this.xtcProbability = 0.0, // 0 = off (samplers are delivered now)
    this.stopSequences,
    this.reasoningEnabled = false,
    this.reasoningEffort = 'medium',
    this.reasoningMaxTokens,
    this.salvageReasoning = false,
    this.bannedPhrases,
    this.systemPrompt,
    this.grammar,
    this.banEosToken = false,
    this.trimStop = true,
    this.images,
    this.toolChoice,
    this.onChunk,
    this.stillWantTools,
    this.backendIdentity = '',
  });

  /// The `content` value for the OpenAI chat user message: the plain [prompt]
  /// string when no [images] ride along, or a multimodal content array of one
  /// text part followed by one `image_url` part per image. Both chat-payload
  /// builders (openai_chat_stream.dart and OpenRouterService) call this so
  /// the two wire shapes can't drift.
  Object get openAiUserContent {
    final imgs = images;
    if (imgs == null || imgs.isEmpty) return prompt;
    return [
      {'type': 'text', 'text': prompt},
      for (final img in imgs)
        {
          'type': 'image_url',
          'image_url': {'url': 'data:image/png;base64,$img'},
        },
    ];
  }
}

/// One tool invocation from a tool-calling response (OpenAI `tool_calls`
/// entry, arguments already JSON-decoded; malformed arguments decode to {}).
class LlmToolCall {
  final String name;
  final Map<String, dynamic> arguments;

  const LlmToolCall({required this.name, required this.arguments});
}

/// Result of a tool-enabled, non-streaming generation: the tool calls the
/// model made (possibly none) plus any plain assistant text it also wrote.
class LlmToolResponse {
  final List<LlmToolCall> calls;
  final String text;

  const LlmToolResponse({required this.calls, required this.text});
}

/// Abstract interface for all LLM backends (local KoboldCPP, OpenRouter, etc).
abstract class LLMService extends ChangeNotifier {
  /// Stream tokens one at a time for real-time display.
  Stream<String> generateStream(GenerationParams params);

  /// Non-streaming generation with OpenAI-style tool calling. Returns null
  /// when this backend can't speak the tools protocol — callers fall back to
  /// their text transport (the Journal falls back to its XML tags). Every
  /// real backend implements it (remote APIs and local KoboldCpp alike —
  /// Qwen3-class local models call tools well); a model that can't simply
  /// produces no calls and the caller's negotiation handles the rest.
  ///
  /// Contract: null is a CAPABILITY signal (the backend answered and the
  /// call yielded nothing usable). Transport failures — host unreachable,
  /// the client torn down mid-call by [abortGeneration], a whole-call
  /// timeout, or a busy/5xx server — THROW instead, so verdict-recording
  /// callers (the shared ToolTransportProbe consumers) can classify them as
  /// network events via [isToolTransportFailure] rather than branding the
  /// backend XML-only for the whole run.
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async => null;

  /// Abort the current in-flight generation request (closes the HTTP client).
  void abortGeneration() {}

  /// Whether the backend is ready to accept requests.
  bool get isReady;

  /// Human-readable name for this backend (e.g. "KoboldCPP", "OpenRouter").
  String get backendName;
}

/// True when [error] reads like a failure to reach the backend at all —
/// nothing listening on the port, host down, or the HTTP client torn down
/// mid-request. The OS words the same failure differently per platform:
/// Windows says "The remote computer refused the network connection"
/// (errno 1225), macOS "Connection refused" (errno 61), Linux errno 111 —
/// so match the broad shapes rather than one platform's phrasing.
bool looksLikeBackendUnreachable(Object error) {
  final s = error.toString();
  return s.contains('SocketException') ||
      s.contains('Connection refused') ||
      s.contains('refused the network connection') ||
      s.contains('errno = 61') ||
      s.contains('Connection closed before full header') ||
      (s.contains('ClientException') && s.contains('closed'));
}

/// Thrown by [LLMService.generateWithTools] implementations when the server
/// answered "busy / unavailable" (HTTP 429 or 5xx) — the transient sibling
/// of a thrown socket error. Says nothing about the model's tool-calling
/// capability; callers classify it via [isToolTransportFailure].
class LlmToolTransportException implements Exception {
  final String message;

  LlmToolTransportException(this.message);

  @override
  String toString() => message;
}

/// True when a tools-transport attempt failed at the TRANSPORT level — an
/// unreachable backend, a client torn down mid-call (an app-side
/// abortGeneration), a whole-call timeout, or a busy/5xx server. These say
/// nothing about the MODEL's tool-calling capability, so verdict-recording
/// callers (the shared ToolTransportProbe consumers) must not brand a
/// backend XML-only on them.
bool isToolTransportFailure(Object error) =>
    error is TimeoutException ||
    error is LlmToolTransportException ||
    looksLikeBackendUnreachable(error) ||
    // package:http race: abortGeneration closed the client between its
    // creation and the post() — surfaces as a StateError, not a
    // ClientException.
    error.toString().contains('Client is already closed');

/// Thrown when a feature needs the AI backend but it isn't ready or can't be
/// reached. [message] is user-facing — surfaces like the story pages and the
/// web client show pipeline errors verbatim, so [toString] returns the plain
/// message with no "Exception:" prefix.
class LlmUnavailableException implements Exception {
  final String message;

  LlmUnavailableException(this.message);

  @override
  String toString() => message;
}
