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

part of '../chat_service.dart';

/// Runtime fields that are not fake-pinned (no `implements ChatService` double
/// overrides them). Test hooks ride here too — they are written on real
/// [ChatService] instances only.
/// Extensions in this library can still read them; a Dart extension cannot
/// *declare* instance state, so this mixin is the legal home.
mixin ChatServiceFieldBag {
  /// The database's word of every chat it deletes, for KoboldCpp's saved
  /// cache of it. Moves with the database, so it is re-made on a swap.
  StreamSubscription<String>? _deletedChats;

  /// True while Try again (regenerate on a trailing user line) runs. That
  /// regen holds `_isPostGenerating`, but no reply exists to keep.
  bool _answeringUnansweredLine = false;

  bool _disposed = false;
  // Dynamic Responses, Scene Guests, the Away pulse and the director's scene
  // live on the cast door (ChatService.castDoor, doors/cast/).

  ChatCommandHandler? _commandHandler;

  // Scene Guest cast detection: gate is realismSettings.sceneGuestDetectionEnabled
  // (read in _maybeRunCastDetection). _castScanInterval → chat_service_defaults.

  /// Serializes [sendMessage] so two composer taps during settle cannot
  /// both pass `_isGenerating` and then both run after the wait.
  Future<void> _sendChain = Future.value();
  bool _isGenerating = false;

  /// True while the awaited POST-generation work is still running.
  ///
  /// `_isGenerating` is cleared the moment the last token lands, but the turn
  /// is not finished there: the needs-impact eval, the realism-state re-stamp,
  /// the `RealismDance.saveScalarsIntoGroup` persist and the chip attach all run
  /// afterwards, and in a group they run under an impersonation dance that
  /// reassigns `_session.activeCharacter` and loads that member's scalars. For those
  /// seconds the app used to report "not generating" while the engine was
  /// still mutating state, so every re-entrancy guard stood open: a delete
  /// could shift the timeline under a running eval, and a new turn could
  /// interleave with the previous one's persist.
  ///
  /// Deliberately NOT held across the fire-and-forget passes (journal, growth,
  /// promise-debt, embed, periodic evals). Those are unawaited by design and
  /// can run indefinitely; blocking input until they finish would trade a race
  /// for a wedged UI, which is the worse bug.
  bool _isPostGenerating = false;
  // An import in flight (`isImporting`) and the `.porch` chat-move claim
  // live on the transfer doors (chatImporter, chatPackager).

  // (_isTurnBusy — "this turn is still in motion" predicate for mutation
  // guards, NOT for stopGeneration/_cancelAndWaitForGeneration which must
  // keep testing _isGenerating alone — moved to chat_service_generation_stream.dart)

  // The forked-in entrances' flag lives on the entry door
  // (entryDoor.entrancesInFlight).
  // The session-load and chat-switch flags, the history window and the
  // save chain live on the session store (ChatService.sessionStore).
  bool _cancelRequested = false;
  int _generationEpoch = 0;

  /// The open chat every domain reads (messages, session id, character,
  /// group manager). Its session id setter tells KoboldCpp which chat is open.
  late final _session = ChatSessionState(onChatOpened: _keeperFollows);

  /// Chat screens open on the desktop ([chatScreenOpened]).
  int _chatScreens = 0;

  /// The "Did time pass?" question, and whether a web client is there to
  /// answer one (see `pendingSkip`).
  final SkipConfirmGate _skipGate = SkipConfirmGate();
  bool Function() _skipWebAsker = () => false;

  /// The desktop's chat page opened: the chat it shows is the open one.
  void chatScreenOpened() {
    if (_chatScreens++ == 0) _keeperFollows(_session.currentSessionId);
  }

  /// The desktop's chat page closed. With none left the user went back to
  /// the library: no chat is open, and KoboldCpp's saved cache can go.
  void chatScreenClosed() {
    if (_chatScreens > 0 && --_chatScreens == 0) _keeperFollows(null);
  }

  void _keeperFollows(String? chat) {
    // This bag is ChatService's; the engine is a field of the class.
    final self = this;
    if (self is! ChatService) return;
    try {
      self._koboldService.openChat(chat);
    } on Object catch (e) {
      debugPrint('[Chat] KoboldCpp could not be told which chat is open: $e');
    }
  }

  double _generationProgress = 0.0;

  // Real-absence awareness (Living Time §2) lives on the session store.
  int _tokensGenerated = 0;
  int _maxTokens = 0;
  DateTime? _generationStartTime;
  GenerationPhase _generationPhase = GenerationPhase.idle;
  DateTime? _prefillStartTime; // When we entered prefill (for elapsed timer)
  int _prefillPromptTokens =
      0; // Estimated prompt token count for progress display
  Map<String, dynamic>? _lastPerfData; // Cached KoboldCPP perf data
  final TokenCountMemo _tokenCountMemo = TokenCountMemo();
  final List<String> _tokenBuffer = [];
  Timer? _drainTimer;
  int _displayedTokenCount = 0;
  final List<DateTime> _tokenTimestamps =
      []; // Rolling window for TPS measurement

  // ── Streaming rebuild throttle ──
  // _notifyStreamListeners coalesces per-token notifies into at most one per
  // ~33 ms with a guaranteed trailing notify (the final token batch always
  // paints). End-of-turn paths still call plain notifyListeners() directly,
  // so terminal state (isGenerating=false, chips, perf) is never throttled.
  DateTime _lastStreamNotify = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _streamNotifyTimer;
  // (_notifyStreamListeners lives in chat_service_generation_stream_accessors)

  // ── Web token broadcast (the web StreamHub's real-time token feed) ──
  final StreamController<String> _tokenBroadcast =
      StreamController<String>.broadcast();

  /// Emits complete sentences as they're detected during LLM token streaming.
  /// Used by call mode to start TTS on the first sentence immediately.
  final StreamController<String> _sentenceBroadcast =
      StreamController<String>.broadcast();
  String _sentenceBuffer = ''; // accumulates tokens until a sentence boundary

  /// Whether the app is in voice call mode (auto-disables reasoning for lower latency).
  bool _callMode = false;

  /// Main model parked by the pre-turn call-model swap (sendMessage enters,
  /// the request phase adopts into the turn carrier — see the request part).
  String? _callEvalModelOriginal;

  // The group repository main.dart wires in and the auto-chat turn budget
  // live on the entry door (entryDoor.groupRepository, entryDoor.autoChat).

  // A group's per-member notes, prompts and RAG knobs, the Author's Note,
  // the gallery looks and the recap ("Where we are") live on the session
  // store (sessionStore.groupConfig and the store's own fields).
  // Director Mode state is owned by _session.groupManager when active.
  // ── Realism Mode ──
  bool _realismChatSwitch = false; // this chat's own; gate: _realismEnabled
  // The eval overlay's flags, streamed text and verifier pass, the emotion
  // registers and the pending turn metadata live on the Realism graph
  // (ChatService.realism: evalStatus, registers).

  // Chaos Mode state lives on _chaosModeService. UI park flags stay here.
  bool _chanceTimePendingTrigger =
      false; // true for one cycle to pop the overlay
  // The single event the web/mobile "reveal your fate" modal shows + accepts
  // while sendMessage is parked on the completer below. The desktop samples its
  // own spinning wheel; a phone has no room for one, so we pre-pick one event
  // from the same pool. Lives only during the park (set at the gate, cleared on
  // resume) — see [isAwaitingChanceTime] / [acceptPendingChanceTime].
  String? _webChanceTimeEvent;
  String? _webChanceTimeName; // who it names, fixed at the spin

  // ── Needs simulation + scene-impact evaluator ──
  bool _needsSimEnabled = false;
  // Per-chat Objectives switch (v45). Defaults true; read via objectivesActive.
  bool _objectivesEnabled = true;
  bool _enjoysLowHygiene =
      false; // inversion for hygiene (enjoys being dirty/sweaty/musky)

  // Per-chat lore timers, the parsed group book, the Setting and Lore slots,
  // the climate spans and the scene move state live on the Realism graph
  // (realism.lore, realism.places).
  // (chatLorebook / commitChatLorebookEdit / lastLoreOverflow / lastLoreTokens
  // / lastLoreBudget / loreTimedEffects / previewLoreTriggers /
  // currentlyActiveLoreEntries moved to chat_service_accessors.dart)
  List<String> _lastLoreOverflow = const [];
  int _lastLoreTokens = 0;
  int _lastLoreBudget = 0;

  /// Central macro resolver for prompt template expansion.
  late final _macroResolver = MacroResolver();

  /// In-memory clock for {{idle_duration}} — set on each user send; null
  /// after a restart (the macro passes through untouched then).
  DateTime? _lastUserMessageAt;

  Completer<void>?
  _chanceTimeCompleter; // pauses sendMessage while wheel is active (UI coordination)

  final ContextBudgetStore _contextBudget = ContextBudgetStore();
  // Session name, description, per-chat generation settings and theme, and
  // the fork lineage live on the session store.
  ({String key, ChatGenerationSettings chat})?
  _promptPickerPending; // prompt-picker SOW: the new 1:1 awaiting the picker

  String? _evalCleanSrc, _evalCleanOut;

  /// Test-only overrides for driving the real LLM paths (realism evals +
  /// chat generation) with canned responses without constructing a full
  /// LLMProvider (heavy deps).
  @visibleForTesting
  LLMService? testLlmServiceOverride;
  @visibleForTesting
  bool testIsLocalOverride = false;
  @visibleForTesting
  LLMService? testWorkerLlmServiceOverride;

  // The Feelings rescore flag and crossings, and the word-rewrite seed, live
  // on the edits door (editsDoor.reprocess, editsDoor.tokenAlts).
}
