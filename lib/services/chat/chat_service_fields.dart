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

  bool _disposed = false;
  // Dynamic Responses, Scene Guests, the Away pulse and the director's scene
  // live on the cast door (ChatService.castDoor, doors/cast/).

  // Scene Guest cast detection: gate is realismSettings.sceneGuestDetectionEnabled
  // (read in the turn engine's cast scan, TurnEntry). kCastScanInterval → chat_defaults.dart.

  /// Serializes [sendMessage] so two composer taps during settle cannot
  /// both pass `isGenerating` and then both run after the wait.
  Future<void> _sendChain = Future.value();
  // An import in flight (`isImporting`) and the `.porch` chat-move claim
  // live on the transfer doors (chatImporter, chatPackager).

  // The turn's flags (isGenerating, the settling window, Stop, the epoch),
  // the status bar's numbers, the display buffer and the token and sentence
  // streams live on the turn engine (ChatService.turnEngine.progress).

  // The forked-in entrances' flag lives on the entry door
  // (entryDoor.entrancesInFlight).
  // The session-load and chat-switch flags, the history window and the
  // save chain live on the session store (ChatService.sessionStore).

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

  // Voice call mode lives on the controls door (controlsDoor.callMode).

  // The main model parked by the pre-turn call-model swap lives on the
  // prompt assembler (promptAssembler.callSwap).

  // The group repository main.dart wires in and the auto-chat turn budget
  // live on the entry door (entryDoor.groupRepository, entryDoor.autoChat).

  // A group's per-member notes, prompts and RAG knobs, the Author's Note,
  // the gallery looks and the recap ("Where we are") live on the session
  // store (sessionStore.groupConfig and the store's own fields).
  // Director Mode state is owned by _session.groupManager when active.
  // ── Realism Mode ──
  // The chat's own switches (Realism, Needs, Objectives, low hygiene) and
  // their gates live on the controls door (ChatService.controlsDoor).
  // The eval overlay's flags, streamed text and verifier pass, the emotion
  // registers and the pending turn metadata live on the Realism graph
  // (ChatService.realism: evalStatus, registers).

  // Chaos Mode state lives on the Realism graph's chaos service; Chance
  // Time's park (the overlay trigger, the parked send, the phone's
  // pre-picked event) on the controls door (controlsDoor.chance).

  // Per-chat lore timers, the parsed group book, the Setting and Lore slots,
  // the climate spans and the scene move state live on the Realism graph
  // (realism.lore, realism.places).
  // The last turn's lore meter, the macro resolver, the {{idle_duration}}
  // clock, the Context Viewer budget, the history window's token memo and
  // the prompt picker's arm live on the prompt assembler (promptAssembler).
  // Session name, description, per-chat generation settings and theme, and
  // the fork lineage live on the session store.

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

/// The Realism graph's, the session store's, the entry door's and the
/// prompt assembler's state and behaviour under the names the rest of this
/// library still uses. Each line is debt its caller's package retires by
/// calling the door itself (WP10c, WP11).
extension _ChatServiceDoorNames on ChatService {
  // State the graph owns.
  bool get _realismEvalCancelled => realism.evalStatus.cancelled;
  set _realismEvalCancelled(bool v) => realism.evalStatus.cancelled = v;
  Map<String, dynamic>? get _pendingRealismMetadata =>
      realism.registers.pending;
  set _pendingRealismMetadata(Map<String, dynamic>? v) =>
      realism.registers.pending = v;
  String get _characterEmotion => realism.registers.emotion;
  String get _emotionIntensity => realism.registers.intensity;
  set _isGrowthPassRunning(bool v) => realism.growthPassRunning = v;
  ChatPlaceSlots get _chatPlaceSlots => realism.places.slots;
  LorebookTimedEffects get _loreTimedEffects => realism.lore.timedEffects;
  ToolTransportProbe get _toolProbe => realism.transport.probe;

  // The leaves.
  LorebookScanner get _lorebookScanner => realism.lore.scanner;
  TimeService get _timeService => realism.time;
  ChaosModeService get _chaosModeService => realism.chaos;
  NeedsSimulation get _needsSimulation => realism.needs;
  Map<String, GroupMemberRealism> get _groupRealism => realism.groups.members;
  NeedsPass get _needsPass => realism.needsPass;
  MoodRegisters get _mood => realism.mood;
  RealismSnapshot get _realismSnapshot => realism.snapshot;
  RealismDance get _realismDance => realism.dance;
  RelationshipService get _relationshipService => realism.relationship;
  ExpressionService get _expressionService => realism.expression;
  DreamService get _dreamService => realism.dreams;
  JournalStore get _journalStore => realism.journalStore;
  PorchMemoryImportService get _porchMemoryImport => realism.porchImport;
  ToolSupportTester get _toolSupportTester => realism.toolSupportTester;

  // Behaviour.
  RealismScope _realismScope() => realism.scope;
  bool get _realismActiveThisMode => realism.realismActiveThisMode;
  String get _evalBackendIdentity => realism.transport.backendIdentity;
  PlayerSkip _buildPlayerSkip() => realism.playerSkip();
  void _restoreRealismStateFromMessage(
    ChatMessage? msg, {
    String? groupSpeakerId,
    bool restoreClock = false,
  }) => realism.restores.fromMessage(
    msg,
    groupSpeakerId: groupSpeakerId,
    restoreClock: restoreClock,
  );
  void _applyMoodDecay() => realism.restores.applyMoodDecay();

  // The prompt assembler and the entry door.
  set _lastUserMessageAt(DateTime? at) =>
      promptAssembler.lastUserMessageAt = at;
  void _enterCallEvalModelSwap() => promptAssembler.callSwap.enter();
  void _exitCallEvalModelSwap() => promptAssembler.callSwap.exit();
  GroupChat? get _activeGroup => _session.activeGroup;
  List<CharacterCard> get _groupCharacters => _session.groupCharacters;
  bool get _entrancesInFlight => entryDoor.entrancesInFlight;
  set _groupChatRepository(GroupChatRepository? repo) =>
      entryDoor.groupRepository = repo;
  Future<void> _waitForTurnToSettle() => entryDoor.cover.waitForTurnToSettle();

  // The session store.
  set _summaryPaused(bool v) => sessionStore.summaryPaused = v;
  bool get _isSummaryGenerating => sessionStore.isSummaryGenerating;
  set _isSummaryGenerating(bool v) => sessionStore.isSummaryGenerating = v;
  bool get _isNewChat => sessionStore.isNewChat;
  set _isNewChat(bool v) => sessionStore.isNewChat = v;
  bool get _isLoadingSession => sessionStore.isLoadingSession;
  int get _chatSwitches => sessionStore.chatSwitches;
  bool get _absenceAckPending => sessionStore.absenceAckPending;
  set _absenceAckPending(bool v) => sessionStore.absenceAckPending = v;
  bool get _absenceAckConsumed => sessionStore.absenceAckConsumed;
  set _absenceAckConsumed(bool v) => sessionStore.absenceAckConsumed = v;

  // The today line (TodaySentence).
  set _onTodayAbandoned(void Function(String? held)? v) =>
      sessionStore.today.onTodayAbandoned = v;
  void _clearTodayPointer() => sessionStore.today.clearTodayPointer();

  // Load, save and the window.
  Future<void> _saveChat({bool replaceAll = false}) =>
      sessionStore.save(replaceAll: replaceAll);
  void _rememberRecapEdit(String text) => sessionStore.rememberRecapEdit(text);
  Future<void> _awaitHistoryHydrated() =>
      sessionStore.window.awaitHistoryHydrated();
}

/// The cast door's state and behaviour under the names the rest of this
/// library still uses. Each line is debt its caller's package retires by
/// calling [ChatService.castDoor] itself (WP10c, WP11).
extension _ChatServiceCastNames on ChatService {
  /// The unified ordered cast of speakers for the active chat, regardless of
  /// mode. This is the single roster the UI reads instead of branching on
  /// `isGroupMode` between `activeCharacter`, `groupCharacters`, and
  /// `sceneGuestCards`:
  ///   - Group chat → each group member, in turn order (no distinct host).
  ///   - 1:1 / NPC chat → the host (`cast[0]`, realism-bearing) followed by any
  ///     present Scene Guests (lite NPCs, realism off).
  /// Empty only when no chat is loaded.
  List<ChatParticipant> get _castImpl {
    if (isGroupMode) {
      return [
        for (final c in groupCharacters)
          ChatParticipant(card: c, isHost: false),
      ];
    }
    final host = _session.activeCharacter;
    return [
      if (host != null) ChatParticipant(card: host, isHost: true),
      for (final g in _sceneGuest.cards)
        ChatParticipant(card: g, isHost: false, isSceneGuest: true),
    ];
  }

  SceneGuestState get _sceneGuest => castDoor.guests.state;
  AwayPulseState get _awayPulse => castDoor.away.state;
  bool get _narrating => castDoor.narrating;
  set _stoppedReplyAnchor(ChatMessage? v) =>
      castDoor.guests.stoppedReplyAnchor = v;
  set _greetingIndex(int v) => castDoor.greetings.greetingIndex = v;
  set _pendingIdleCue(String? v) => castDoor.idle.pendingIdleCue = v;
  set _hasCompletedExchange(bool v) => castDoor.idle.hasCompletedExchange = v;

  bool _sceneChanged(String? token) => castDoor.sceneChanged(token);
  void _setGuestStatus(
    String? msg, {
    bool isError = false,
    bool sticky = false,
  }) => castDoor.guests.setStatus(msg, isError: isError, sticky: sticky);
  void _clearExitUndo() => castDoor.guests.clearExitUndo();
  bool _isGuestAuthoredMessage(ChatMessage m) =>
      castDoor.guests.isGuestAuthoredMessage(m);
  CharacterCard? _sceneGuestForMessage(ChatMessage m) =>
      castDoor.guests.sceneGuestForMessage(m);
  CharacterCard? _directAddressRoutedGuest(String promptText) =>
      castDoor.guests.directAddressRoutedGuest(promptText);
  Future<void> _resolveSceneGuestCards() =>
      castDoor.guests.resolveSceneGuestCards();

  Future<void> _commitPendingMemberExit() =>
      castDoor.roster.commitPendingMemberExit();
  bool _speakerIsSoft(CharacterCard speaker) =>
      castDoor.roster.speakerIsSoft(speaker);
  Future<bool> _bridgeLongSkip({
    required DateTime from,
    required int skipped,
    required ChatMessage skipLine,
    required String? token,
  }) => castDoor.stage.bridgeLongSkip(
    from: from,
    skipped: skipped,
    skipLine: skipLine,
    token: token,
  );

  Future<void> _invalidateGreetingEval() =>
      castDoor.greetings.invalidateGreetingEval();
  String _buildFirstMessage(CharacterCard character, {String? greetingText}) =>
      castDoor.greetings.buildFirstMessage(
        character,
        greetingText: greetingText,
      );
  CharacterCard? _greetingOwnerCard() => castDoor.greetings.greetingOwnerCard();
  Future<void> _applyGreetingOpeningSeed({
    required CharacterCard card,
    required int index,
    bool scheduleEval = true,
  }) => castDoor.greetings.applyGreetingOpeningSeed(
    card: card,
    index: index,
    scheduleEval: scheduleEval,
  );
  Future<void> _applyGroupCustomGreetingSeed(
    int index, {
    bool scheduleEval = true,
  }) => castDoor.greetings.applyGroupCustomGreetingSeed(
    index,
    scheduleEval: scheduleEval,
  );
  void _stampGreetingIndex(int index) =>
      castDoor.greetings.stampGreetingIndex(index);

  Future<void> _runAwayPulse({
    required String userText,
    required bool fromUserSend,
  }) => castDoor.away.runAwayPulse(
    userText: userText,
    fromUserSend: fromUserSend,
  );
  void _resetIdleTimer() => castDoor.idle.resetIdleTimer();
  void _cancelIdleTimer() => castDoor.idle.cancelIdleTimer();
}

/// The turn engine's state and behaviour under the names the rest of this
/// library still uses. Each line is debt the send spine retires by calling
/// [ChatService.turnEngine] itself (WP10c).
extension _ChatServiceTurnNames on ChatService {
  bool get _isGenerating => turnEngine.progress.isGenerating;
  bool get _isTurnBusy => turnEngine.isTurnBusy;
}
