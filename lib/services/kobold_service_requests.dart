// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The requests the app sends to the engine, and the one line they wait in.

part of 'kobold_service.dart';

/// What one [KoboldService] keeps for sending requests. Held beside the
/// service, not in a field, like [_idleStates]: the test fakes implement
/// [KoboldService] through noSuchMethod and still reach the extensions.
class _RequestState {
  /// Every request that can change what KoboldCpp keeps in its cache waits
  /// here for its turn: replies, tool calls, helper streams, the
  /// system-role check. Stop, perf, token counts and swaps do not.
  final KoboldRequestQueue queue = KoboldRequestQueue();
}

final Expando<_RequestState> _requestStates = Expando('fpai.koboldRequests');

extension KoboldServiceRequests on KoboldService {
  _RequestState get _requests => _requestStates[this] ??= _RequestState();

  /// Local tool calling: recent KoboldCpp supports OpenAI tools with
  /// template-aware models (Qwen3 family etc.). Models/servers that can't
  /// simply yield no tool calls and the caller's negotiation falls back to
  /// its text transport (the Journal's XML floor).
  Future<LlmToolResponse?> _generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    if (!isReady) return null;
    http.Client? mine;
    return _runSerialized<LlmToolResponse?>(() async {
      if (params.stillWantTools?.call() == false) return null;
      return postOpenAiChatWithTools(
        _baseUrl,
        params,
        tools,
        thinkingModelKey: requestModel,
        foldSystemIntoUser: _systemRole.foldSystemIntoUser,
        toolChoice: params.toolChoice,
        registerClient: (client) {
          mine = client;
          _activeClient = client;
        },
        // A finishing call may clear the abort handle only while it is ITS
        // handle: clearing a newer request's left Stop with nothing to close.
        onDone: () {
          if (identical(_activeClient, mine)) _activeClient = null;
        },
      );
    });
  }

  /// Run [body] when its turn comes, with the engine to itself. The one
  /// copy of the protocol every request that is not a reply follows, so no
  /// two drift apart.
  Future<T> _runSerialized<T>(Future<T> Function() body) =>
      _requests.queue.run(() async {
        try {
          await _idleRequestStart();
          return await body();
        } finally {
          _idleRequestEnd();
        }
      });

  /// Routes generation through KoboldCpp's OpenAI-compatible
  /// `/v1/chat/completions` endpoint (via [streamOpenAiChat]) instead of the
  /// legacy raw `/api/extra/generate/stream`. The chat endpoint applies the
  /// loaded model's instruct template server-side, so instruct GGUFs follow
  /// instructions and stop naturally via EOS — the raw endpoint did neither
  /// (immediate empty responses or runaway repetition on un-templated prompts).
  /// KoboldCpp ignores the model name.
  ///
  /// The request waits for its turn when the stream is listened to, and gives
  /// the place back when the stream ends, fails or is cancelled. A reader
  /// that leaves while it still waits makes it stop at the first chunk.
  Stream<String> _generateStream(GenerationParams params) async* {
    final ticket = _requests.queue.enter();
    http.Client? mine;
    try {
      await ticket.turn;
      await _idleRequestStart();
      yield* streamOpenAiChat(
        _baseUrl,
        params,
        thinkingModelKey: requestModel,
        foldSystemIntoUser: _systemRole.foldSystemIntoUser,
        registerClient: (client) {
          mine = client;
          _activeClient = client;
        },
        // Ownership guard — see generateWithTools: this stream's late
        // teardown must not null a newer request's abort handle.
        onDone: () {
          if (identical(_activeClient, mine)) _activeClient = null;
        },
      );
    } finally {
      _idleRequestEnd();
      ticket.release();
    }
  }

  void _abortGeneration() {
    _activeClient?.close();
    _activeClient = null;
    // Server-side abort, not awaited so the UI never blocks: KoboldCpp stops
    // even with the socket gone, and drains before the next request.
    _postAbort();
  }

  Future<void> _waitForIdle() => _requests.queue.waitForIdle();
}
