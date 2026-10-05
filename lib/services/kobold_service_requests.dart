// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The requests the app sends to the engine, and the one place they wait
// their turn.

part of 'kobold_service.dart';

extension KoboldServiceRequests on KoboldService {
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

  /// Run [body] with exclusive use of the single-slot local engine: wait for
  /// any in-flight request, then register on the SAME `_pendingRequest` slot
  /// [generateStream] uses, so other `waitForIdle` callers (text evals, the
  /// Scene Guest mint, the system-role probe) queue behind us instead of
  /// racing. One copy of this slot protocol, so no two drift apart.
  Future<T> _runSerialized<T>(Future<T> Function() body) async {
    await waitForIdle();
    final completer = Completer<void>();
    _pendingRequest = completer.future;
    try {
      await _idleRequestStart();
      return await body();
    } finally {
      _idleRequestEnd();
      if (!completer.isCompleted) completer.complete();
      // Only release the slot if it is still OURS — a stream that started
      // meanwhile (the main chat path doesn't waitForIdle) must not have its
      // registration nulled by this call's late finally.
      if (identical(_pendingRequest, completer.future)) _pendingRequest = null;
    }
  }

  /// Routes generation through KoboldCpp's OpenAI-compatible
  /// `/v1/chat/completions` endpoint (via [streamOpenAiChat]) instead of the
  /// legacy raw `/api/extra/generate/stream`. The chat endpoint applies the
  /// loaded model's instruct template server-side, so instruct GGUFs follow
  /// instructions and stop naturally via EOS — the raw endpoint did neither
  /// (immediate empty responses or runaway repetition on un-templated prompts).
  /// KoboldCpp ignores the model name.
  ///
  /// `_activeClient` is registered for [abortGeneration]; `_pendingRequest`
  /// (a completer future) is tracked so [waitForIdle] still unblocks on close.
  Stream<String> _generateStream(GenerationParams params) async* {
    final completer = Completer<void>();
    _pendingRequest = completer.future;
    http.Client? mine;
    try {
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
      if (!completer.isCompleted) completer.complete();
      // Same slot-ownership guard as generateWithTools: don't null a newer
      // request's registration from this one's late finally.
      if (identical(_pendingRequest, completer.future)) _pendingRequest = null;
    }
  }

  void _abortGeneration() {
    _activeClient?.close();
    _activeClient = null;
    // Server-side abort, not awaited so the UI never blocks: KoboldCpp stops
    // even with the socket gone, and drains before the next request.
    _postAbort();
  }

  Future<void> _waitForIdle() async {
    final pending = _pendingRequest;
    if (pending != null) {
      await pending;
    }
  }
}
