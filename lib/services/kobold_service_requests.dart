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

  /// Saves a chat's cache after its reply and loads it before the next one.
  KoboldSlotKeeper? keeper;
  Future<KoboldKeeperPlan> Function()? debugPlan;

  /// Goes up with every [KoboldService.abortGeneration]: a reply that fails
  /// while it goes up was stopped, not broken.
  int aborts = 0;

  /// Chat replies still waiting for their turn.
  final Set<_Waiting> waiting = {};

  /// Takes out of the line every waiting reply whose caller no longer wants
  /// it (Stop was pressed). True when there was one: that abort was meant
  /// for the reply, not for whoever is on the wire ahead of it.
  bool dropStoppedReplies() {
    var any = false;
    for (final w in waiting.toList()) {
      if (w.stillWant?.call() != false) continue;
      waiting.remove(w);
      w.left.complete();
      any = true;
    }
    return any;
  }
}

/// One chat reply in the line that has not had its turn. [left] completes
/// when the reply is to leave the line without waiting for it.
class _Waiting {
  _Waiting(this.stillWant);
  final bool Function()? stillWant;
  final Completer<void> left = Completer<void>();
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
  /// two drift apart. It changes the engine's cache, which the slot keeper
  /// is told before it goes out.
  Future<T> _runSerialized<T>(Future<T> Function() body) =>
      _requests.queue.run(() async {
        try {
          await _idleRequestStart();
          _keeper.helperStart();
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
  /// that leaves while the request still waits means it is never sent.
  ///
  /// A chat reply ([GenerationParams.kvChat]) has its chat's saved cache
  /// loaded before it goes out and saved after it, with the place held
  /// until the save is done, so the next request starts from a settled
  /// engine. The reader is not kept waiting for the save. Any other request
  /// only tells the keeper that it changes the cache.
  Stream<String> _generateStream(GenerationParams params) async* {
    final ticket = _requests.queue.enter();
    // A chat reply is stoppable while it waits. One that carries pictures is
    // also neither loaded for nor saved after (it is a helper to the keeper):
    // KoboldCpp does not bring a saved chat's pictures back with the chat.
    final reply = params.kvChat != null;
    final chat = reply && params.images?.isNotEmpty != true
        ? params.kvChat
        : null;
    bool wanted() => params.stillWant?.call() ?? true;
    final waiting = reply ? _Waiting(params.stillWant) : null;
    if (waiting != null) _requests.waiting.add(waiting);
    // _idleRequestStart began, and has an _idleRequestEnd to match.
    var counted = false;
    // The keeper was told about this request, so it has to be told it ended.
    var touched = false;
    var sent = false;
    var broken = false;
    var aborts = 0;
    http.Client? mine;
    try {
      if (waiting == null) {
        await ticket.turn;
      } else {
        // A Stop for this reply takes it out of the line at once.
        await Future.any([ticket.turn, waiting.left.future]);
        _requests.waiting.remove(waiting);
      }
      // Before the model is woken, if it was unloaded, and before a load.
      if (!wanted()) return;
      counted = true;
      await _idleRequestStart();
      touched = true;
      if (chat == null) {
        _keeper.helperStart();
      } else {
        await _keeper.chatStart(chat);
      }
      // The Stop button cancels the turn, not the reader's subscription, so
      // a reply that waited or loaded for a while asks before it is sent.
      if (!wanted()) return;
      aborts = _requests.aborts;
      // `yield*`, so a reader that left while this waited never starts the
      // request. The errors pass through to the reader, and this body notes
      // that the reply broke.
      yield* streamOpenAiChat(
        _baseUrl,
        params,
        thinkingModelKey: requestModel,
        foldSystemIntoUser: _systemRole.foldSystemIntoUser,
        registerClient: (client) {
          sent = true;
          mine = client;
          _activeClient = client;
        },
        // Ownership guard — see generateWithTools: this stream's late
        // teardown must not null a newer request's abort handle.
        onDone: () {
          if (identical(_activeClient, mine)) _activeClient = null;
        },
      ).handleError((Object error, StackTrace stack) {
        // A Stop closes the call and so ends the stream with an error: the
        // cache is as the reply left it, which is worth keeping.
        broken = _requests.aborts == aborts;
        Error.throwWithStackTrace(error, stack);
      });
    } finally {
      _requests.waiting.remove(waiting);
      void done() {
        if (counted) _idleRequestEnd();
        ticket.release();
      }

      if (!touched || chat == null) {
        done();
      } else {
        // The save is still the engine's work: it counts as busy, for the
        // idle unload, until the save is done.
        unawaited(
          _keeper
              .chatEnd(chat, ok: sent && !broken)
              .catchError(
                (Object e) => debugPrint('[Kobold] saving the chat failed: $e'),
              )
              .whenComplete(done),
        );
      }
    }
  }

  /// Closes the call on the wire and tells the engine to stop. Not when the
  /// abort is a Stop for a reply that is still waiting: whoever is on the
  /// wire is ahead of that reply and may be a pass of an earlier turn, which
  /// a Stop of this turn does not cancel. Every other abort is as it was.
  void _abortGeneration() {
    if (_requests.dropStoppedReplies()) return;
    _requests.aborts++;
    _activeClient?.close();
    _activeClient = null;
    // Server-side abort, not awaited so the UI never blocks: KoboldCpp stops
    // even with the socket gone, and drains before the next request.
    _postAbort();
  }

  Future<void> _waitForIdle() => _requests.queue.waitForIdle();
}
