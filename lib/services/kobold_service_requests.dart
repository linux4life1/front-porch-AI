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

  /// The call that is open to the engine now, for Stop to cut.
  final KoboldWire wire = KoboldWire();

  /// Saves a chat's cache after its reply and loads it before the next one.
  KoboldSlotKeeper? keeper;
  Future<KoboldKeeperPlan> Function()? debugPlan;

  /// Goes up with every [KoboldService.abortGeneration]: a reply that fails
  /// while it goes up was stopped, not broken.
  int aborts = 0;

  /// Chat replies still waiting for their turn.
  final Set<_Waiting> waiting = {};

  /// Set while the preset editor's speed test has the engine; completes when
  /// chat's model is back. The app's own requests wait for it.
  Completer<void>? speedTest;

  /// The speed test has the engine and nothing of the app's is left on it.
  bool speedTestHasEngine = false;

  /// Takes out of the line every waiting reply whose caller no longer wants
  /// it (the turn was cancelled). True when there was one.
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
    // Before the readiness check: the speed test's load is not a model gone.
    final speedTest = _requests.speedTest;
    if (speedTest != null) await speedTest.future;
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
          _requests.wire.hold(client);
        },
        onDone: () => _requests.wire.release(mine),
      );
    });
  }

  /// The preset editor's speed test is about to load its own preset. Until
  /// the returned [_endSpeedTestHold] is called the app's own requests
  /// (replies, the turn's judges and passes, tool calls) wait for chat's
  /// model to be back, in front of the line; what the test sends and what a
  /// load starts by itself (the system-role check) still go through it.
  /// Completes when what was already in the line is done, on chat's model,
  /// saves included.
  Future<void Function()> _holdForSpeedTest() async {
    _requests.speedTest ??= Completer<void>();
    liveProgress.heldBy = 'the speed test';
    notify();
    await _waitForIdle();
    if (_requests.speedTest != null) _requests.speedTestHasEngine = true;
    return _endSpeedTestHold;
  }

  /// Chat's model is back (or could not be put back: the hold never
  /// outlives the test).
  void _endSpeedTestHold() {
    final held = _requests.speedTest;
    _requests.speedTest = null;
    _requests.speedTestHasEngine = false;
    liveProgress.heldBy = null;
    held?.complete();
    notify();
  }

  /// One fresh timing prompt for the MMQ trial ([timeKoboldPrompt]). It
  /// changes what the engine keeps in its cache like any request does, so it
  /// waits its turn in the line and nothing overlaps it: not the save of a
  /// chat, not a reply.
  Future<Duration> _timePrompt(int round) =>
      _runSerialized(() => timeKoboldPrompt(_baseUrl, round));

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
    // While the editor's speed test has the engine, the request waits for
    // chat's model in front of the line and takes its place after it.
    final speedTest = _requests.speedTest;
    var ticket = speedTest == null ? _requests.queue.enter() : null;
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
      if (speedTest != null) {
        // A Stop for this reply takes it out of this wait at once too.
        await Future.any([speedTest.future, ?waiting?.left.future]);
        if (!wanted()) return;
      }
      final place = ticket ??= _requests.queue.enter();
      if (waiting == null) {
        await place.turn;
      } else {
        // A Stop for this reply takes it out of the line at once.
        await Future.any([place.turn, waiting.left.future]);
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
          _requests.wire.hold(client);
        },
        onDone: () => _requests.wire.release(mine),
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
        ticket?.release();
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

  /// Closes the call on the wire and tells the engine to stop. Always, for
  /// whoever asks: an eval that has its answer, a tool call that timed out,
  /// a creator, the Stop button.
  void _abortGeneration() {
    _requests.aborts++;
    _requests.wire.cut();
    // While the speed test has the engine nothing of the app's is on it:
    // telling KoboldCpp to stop would stop the test's prompt.
    if (_requests.speedTestHasEngine) return;
    // Server-side abort, not awaited so the UI never blocks: KoboldCpp stops
    // even with the socket gone, and drains before the next request.
    _postAbort();
  }

  /// A cancelled turn's replies that still wait leave the line at once. The
  /// wire is left alone: whoever is on it is ahead of those replies and may
  /// be a pass of an earlier turn, which cancelling this turn does not
  /// cancel. Only the Stop button and a chat switch ask for this.
  bool _dropStoppedReplies() => _requests.dropStoppedReplies();

  Future<void> _waitForIdle() => _requests.queue.waitForIdle();
}
