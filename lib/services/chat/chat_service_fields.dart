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
  // Every other piece of the chat's state lives on the door that owns it:
  // the cast (guests, Away, idle turns, the director's scene), the transfer
  // doors (an import in flight), the turn engine (the turn's flags, the
  // status bar's numbers, the token and sentence streams), the send spine
  // (the send queue, the "Did time pass?" gate), the entry door (entrances,
  // the group repository, auto-chat), the session store (loading, the
  // history window, the save chain, per-chat settings, the recap), the
  // controls door (the switches, the call, Chance Time's park), the Realism
  // graph (eval status, registers, Chaos, lore, places), the prompt
  // assembler (the call-model swap, the macro resolver, the lore meter, the
  // Context Viewer budget) and the edits door (the Feelings rescore, the
  // word-rewrite seed). Director Mode state is the group manager's.

  /// The database's word of every chat it deletes, for KoboldCpp's saved
  /// cache of it. Moves with the database, so it is re-made on a swap.
  StreamSubscription<String>? _deletedChats;

  bool _disposed = false;

  /// The open chat every domain reads (messages, session id, character,
  /// group manager). Its session id setter tells KoboldCpp which chat is open.
  late final _session = ChatSessionState(onChatOpened: _keeperFollows);

  /// Chat screens open on the desktop ([chatScreenOpened]); a "Did time
  /// pass?" question needs one (or a web client) to be asked.
  int _chatScreens = 0;

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

  /// Test-only overrides for driving the real LLM paths (realism evals +
  /// chat generation) with canned responses without constructing a full
  /// LLMProvider (heavy deps).
  @visibleForTesting
  LLMService? testLlmServiceOverride;
  @visibleForTesting
  bool testIsLocalOverride = false;
  @visibleForTesting
  LLMService? testWorkerLlmServiceOverride;
}

/// The Realism graph's, the session store's, the entry door's and the
/// prompt assembler's state and behaviour under the names the rest of this
/// library still uses. Each line is debt WP11 retires by calling the door
/// itself.
extension _ChatServiceDoorNames on ChatService {
  // State the graph owns.
  set _isGrowthPassRunning(bool v) => realism.growthPassRunning = v;
  ToolTransportProbe get _toolProbe => realism.transport.probe;

  // The leaves.
  ExpressionService get _expressionService => realism.expression;
  ToolSupportTester get _toolSupportTester => realism.toolSupportTester;

  // Behaviour.
  String get _evalBackendIdentity => realism.transport.backendIdentity;

  // The open chat and the entry door.
  GroupChat? get _activeGroup => _session.activeGroup;
  List<CharacterCard> get _groupCharacters => _session.groupCharacters;
  set _groupChatRepository(GroupChatRepository? repo) =>
      entryDoor.groupRepository = repo;

  // The session store.
  set _summaryPaused(bool v) => sessionStore.summaryPaused = v;
  set _isSummaryGenerating(bool v) => sessionStore.isSummaryGenerating = v;

  // The today line (TodaySentence).
  set _onTodayAbandoned(void Function(String? held)? v) =>
      sessionStore.today.onTodayAbandoned = v;
  void _clearTodayPointer() => sessionStore.today.clearTodayPointer();

  // Load, save and the window.
  Future<void> _saveChat({bool replaceAll = false}) =>
      sessionStore.save(replaceAll: replaceAll);
}

/// The cast door's state and behaviour under the names the rest of this
/// library still uses. Each line is debt WP11 retires by calling
/// [ChatService.castDoor] itself.
extension _ChatServiceCastNames on ChatService {
  SceneGuestState get _sceneGuest => castDoor.guests.state;

  bool _sceneChanged(String? token) => castDoor.sceneChanged(token);
  void _setGuestStatus(
    String? msg, {
    bool isError = false,
    bool sticky = false,
  }) => castDoor.guests.setStatus(msg, isError: isError, sticky: sticky);
  Future<void> _resolveSceneGuestCards() =>
      castDoor.guests.resolveSceneGuestCards();
  void _cancelIdleTimer() => castDoor.idle.cancelIdleTimer();
}

/// Builds the message-edits door.
extension ChatServiceEditsWiring on ChatService {
  /// The message-edits door. Each hook is debt (see edit_hooks.dart).
  EditsDoor _buildEditsDoor() {
    final door = EditsDoor(
      EditDeps(
        session: _session,
        view: EditsView(
          messages: () => messages,
          activeCharacter: () => activeCharacter,
          isGroupMode: () => isGroupMode,
          activeGroup: () => activeGroup,
          groupCharacters: () => groupCharacters,
          observerMode: () => observerMode,
          greetingIndex: () => greetingIndex,
          isGenerating: () => isGenerating,
          isSettlingTurn: () => isSettlingTurn,
          isEvaluatingRealism: () => isEvaluatingRealism,
          realismEnabled: () => realismEnabled,
          needsActive: () => needsActive,
        ),
        services: EditServices(
          db: () => _db,
          storage: () => _storageService,
          personas: () => _userPersonaService,
          graph: () => realism,
          history: () => sessionStore.history,
          macroResolver: () => promptAssembler.macros,
          objectives: () => objectivesDoor,
          media: () => mediaDoor,
          lanes: _lanes,
        ),
        characterIdFor: _getCharacterIdFromCard,
        saveChat: _saveChat,
        notify: notifyListeners,
        engine: () => turnEngine,
        send: () => sendSpine,
        cast: EditCastHooks(
          guestBusy: () => castDoor.guests.state.busy,
          isGuestAuthored: (m) => castDoor.guests.isGuestAuthoredMessage(m),
          guestFor: (m) => castDoor.guests.sceneGuestForMessage(m),
          setStatus: (text, {isError = false}) =>
              _setGuestStatus(text, isError: isError),
          greetingIndex: () => castDoor.greetings.greetingIndex,
          setGreetingIndex: (index) => castDoor.greetings.greetingIndex = index,
          greetingOwner: () => castDoor.greetings.greetingOwnerCard(),
          firstMessage: (card, {greetingText}) => castDoor.greetings
              .buildFirstMessage(card, greetingText: greetingText),
          invalidateGreetingEval: () async {
            await castDoor.greetings.invalidateGreetingEval();
            turnEngine.greetingEval.clearEntered();
          },
          stampGreetingIndex: (i) => castDoor.greetings.stampGreetingIndex(i),
          isOpeningGreetingChat: () => castDoor.greetings.isOpeningGreetingChat,
          seedGroupGreeting: (i) =>
              castDoor.greetings.applyGroupCustomGreetingSeed(i),
          seedGreeting: ({required card, required index}) => castDoor.greetings
              .applyGreetingOpeningSeed(card: card, index: index),
        ),
        sessions: () => sessionStore,
        prompts: () => promptAssembler,
      ),
    );
    _forwardDoorNotify(door);
    return door;
  }
}

/// Builds the cast door. Each hook is debt (see [CastShellHooks]).
extension ChatServiceCastWiring on ChatService {
  CastDoor _buildCastDoor() => CastDoor(
    CastDeps(
      session: _session,
      storage: _storageService,
      personas: _userPersonaService,
      macros: promptAssembler.macros,
      database: () => _db,
      characters: () => _characterRepository,
      groupRepository: () => entryDoor.groupRepository,
      imageGen: () => _imageGenService,
      graph: () => realism,
      realism: () => realism.scope,
      evals: () => realism.evals,
      snapshot: () => realism.snapshot,
      dance: () => realism.dance,
      judges: () => realism.judges,
      mood: () => realism.mood,
      clockWriter: () => realism.clockWriter,
      chaos: () => realism.chaos,
      evalEngine: () => realism.llmEvalEngine,
      journal: () => realism.journalStore,
      growthStore: () => realism.growthStore,
      growthDesk: () => realism.growthDesk,
      objectives: () => objectivesDoor,
      prompts: () => promptAssembler,
      turn: () => turnEngine,
      send: () => sendSpine,
      characterIdFor: _getCharacterIdFromCard,
      saveChat: _saveChat,
      notify: notifyListeners,
      hooks: _castHooks(),
    ),
  );

  CastShellHooks _castHooks() => CastShellHooks(
    disposed: () => _disposed,
    deleteMessage: deleteMessage,
    ttsSpeaking: () => _ttsService != null && _ttsService!.isSpeaking,
    mouthReady: () => _lanes.mouth.isReady,
    directing: () => entryDoor.director.directing,
    setObserverMode: (on) => entryDoor.director.observerMode = on,
    nextCharacter: () => entryDoor.director.nextCharacter,
    reloadGroupRoster: () => entryDoor.roster.reloadGroupRoster(),
    addToGroup: (card, repo, {asLite = false}) =>
        entryDoor.roster.addCharacterToGroup(card, repo, asLite: asLite),
    removeFromGroup: (card, repo) =>
        entryDoor.roster.removeCharacterFromGroup(card, repo),
    forkToGroup:
        (
          additional,
          repo, {
          entrances = const {},
          liteArrivalKeys = const {},
        }) => entryDoor.fork.forkToGroupChat(
          additional,
          repo,
          entrances: entrances,
          liteArrivalKeys: liteArrivalKeys,
        ),
    forgetMember: (id) => entryDoor.forgetMember(id),
    setActiveCharacter: (card) => entryDoor.chat.setActiveCharacter(card),
    loadSession: (id) => sessionStore.loader.loadSession(id),
    ragCharacterId: _getCharacterId,
    parseJsonMap: _tryParseJsonMap,
    selectGreeting: selectGreeting,
    openingAllGreetings: () => openingAllGreetings,
    resolvedOpeningGreetings: editsDoor.swipes.resolvedOpeningGreetings,
    guestDirector: () => turnEngine.entry.sceneGuestDirector(),
    mintLlm: () => testLlmServiceOverride ?? _llmProvider?.activeService,
  );
}

/// Builds the media and actions doors and, below, the objectives and entry
/// doors. Each callback stands in for a private member of another part
/// until that part becomes a door too.
extension ChatServiceDoorWiring on ChatService {
  MediaDoor _buildMediaDoor() => MediaDoor(
    session: _session,
    storage: _storageService,
    personas: _userPersonaService,
    worlds: _worldRepository,
    imageGen: () => _imageGenService,
    llmProvider: () => _llmProvider,
    craftLlm: () => testLlmServiceOverride ?? _llmProvider?.activeService,
    saveChat: _saveChat,
    isBusy: () => turnEngine.isTurnBusy || castDoor.guests.state.busy,
    setStatus: (msg, {isError = false, sticky = false}) =>
        castDoor.guests.setStatus(msg, isError: isError, sticky: sticky),
    sceneChanged: (token) => castDoor.sceneChanged(token),
    guestCards: () => castDoor.guests.state.cards,
    characterIdFor: _getCharacterIdFromCard,
    expressionLabel: () => currentExpressionLabel,
    timeOfDay: () => realism.time.timeOfDay,
  );

  ActionsDoor _buildActionsDoor() => ActionsDoor(
    session: _session,
    personas: _userPersonaService,
    lanes: _lanes,
  );

  /// The objectives door. Each hook is debt (see [ObjectiveShellHooks]).
  ObjectivesDoor _buildObjectivesDoor() {
    final door = ObjectivesDoor(
      ObjectiveDeps(
        session: _session,
        database: () => _db,
        personas: () => _userPersonaService,
        storage: () => _storageService,
        characterIdFor: _getCharacterIdFromCard,
        saveChat: _saveChat,
        proposal: () => realism.objectiveProposal,
        mood: () => realism.mood,
        journal: () => realism.journalStore,
        time: () => realism.time,
        maxSecondaryObjectives: kMaxSecondaryObjectives,
        hooks: ObjectiveShellHooks(
          objectivesActive: () => objectivesActive,
          nextSpeaker: () => entryDoor.director.nextCharacter,
          hasChatModel: () => _llmProvider != null,
          pendingMetadata: () => realism.registers.pending ??= {},
          historyBase: () => sessionStore.history.basePosition,
          realismActiveThisMode: () => realism.realismActiveThisMode,
          setStatus: (text) => _setGuestStatus(text),
          zeroSessionFlags: () {
            _summaryPaused = false;
            _isSummaryGenerating = false;
            _isGrowthPassRunning = false;
          },
          groupRepository: () => entryDoor.groupRepository,
          rebindToday: () => realism.planner.rebindTodayObjectiveFromDb(),
          clearToday: _clearTodayPointer,
          holdToday: (id) => realism.planner.persistTodayObjectiveId(id),
          releaseToday: (id) => realism.planner.releaseHeldToday(id),
          revertToday: (entry) => realism.planner.revertTodayPointer(entry),
        ),
      ),
    );
    _forwardDoorNotify(door);
    return door;
  }

  /// The entry door. Its shared hooks are the session store's own
  /// ([_sessionHooks]).
  EntryDoor _buildEntryDoor() => EntryDoor(
    EntryDeps(
      session: _session,
      sessions: () => sessionStore,
      services: EntryServices(
        db: () => _db,
        storage: _storageService,
        personas: _userPersonaService,
        worlds: _worldRepository,
        macros: promptAssembler.macros,
        characters: () => _characterRepository,
        llmProvider: () => _llmProvider,
        graph: () => realism,
        controls: () => controlsDoor,
        realism: () => realism.scope,
        snapshot: () => realism.snapshot,
        mood: () => realism.mood,
        chaos: () => realism.chaos,
        needsPass: () => realism.needsPass,
        expression: () => realism.expression,
        lorebook: () => realism.lore.scanner,
        clockWriter: () => realism.clockWriter,
        growthDesk: () => realism.growthDesk,
        birthdays: () => realism.birthdays,
        cast: () => castDoor,
        objectives: () => objectivesDoor,
        media: () => mediaDoor,
        turn: () => turnEngine,
        send: () => sendSpine,
        sceneMoves: realism.places.sceneMoves,
      ),
      shared: _sessionHooks(),
      notify: notifyListeners,
    ),
  );
}

/// Builds the session store and the transfer doors that call it. Each
/// session hook stands in for a private member of another part.
extension ChatServiceSessionWiring on ChatService {
  SessionStore _buildSessionStore() => SessionStore(
    SessionDeps(
      session: _session,
      services: SessionServices(
        db: () => _db,
        storage: _storageService,
        personas: _userPersonaService,
        worlds: _worldRepository,
        macros: promptAssembler.macros,
        characters: () => _characterRepository,
        groupRepository: () => entryDoor.groupRepository,
        graph: () => realism,
        controls: () => controlsDoor,
        realism: () => realism.scope,
        cast: () => castDoor,
        objectives: () => objectivesDoor,
        media: () => mediaDoor,
        lorebook: () => realism.lore.scanner,
        loreTimers: () => realism.lore.timedEffects,
        expression: () => realism.expression,
        clockReader: () => realism.clockReader,
        clockWriter: () => realism.clockWriter,
        growthStore: () => realism.growthStore,
        growthDesk: () => realism.growthDesk,
        journal: () => realism.journalStore,
        porchImport: () => realism.porchImport,
        birthdays: () => realism.birthdays,
        chaos: () => realism.chaos,
        needsPass: () => realism.needsPass,
        pocketsRewinds: () => realism.pocketsRewinds,
        dance: () => realism.dance,
        mood: () => realism.mood,
        sceneMoves: realism.places.sceneMoves,
        autoChat: entryDoor.autoChat,
        prompts: () => promptAssembler,
        turn: () => turnEngine,
      ),
      hooks: _sessionHooks(),
      notify: notifyListeners,
    ),
  );

  /// The session store's hooks; the entry door takes the same ones.
  SessionShellHooks _sessionHooks() => SessionShellHooks(
    characterIdFor: _getCharacterIdFromCard,
    ragCharacterId: _getCharacterId,
    resetDirectorModeToDefault: () =>
        entryDoor.director.resetDirectorModeToDefault(),
    rekeyGroupStores: () => entryDoor.rekey.rekeyGroupStores(),
    setActiveCharacter: (card) => entryDoor.chat.setActiveCharacter(card),
    setActiveGroup: (group, {groupRepo}) =>
        entryDoor.group.setActiveGroup(group, groupRepo: groupRepo),
    beginSessionLoad: () => entryDoor.cover.beginSessionLoad(),
    endSessionLoad: () => entryDoor.cover.endSessionLoad(),
  );

  ChatImporter _buildChatImporter() => ChatImporter(
    _session,
    _buildTransferHost(),
    saveChat: _saveChat,
    notify: notifyListeners,
  );

  ChatPackager _buildChatPackager() =>
      ChatPackager(_session, _buildTransferHost(), importer: chatImporter);

  /// What the transfer doors reach besides the session store. Every entry
  /// past the services and the Realism graph is debt the turn engine (WP10)
  /// retires.
  TransferHost _buildTransferHost() => TransferHost(
    db: () => _db,
    storage: _storageService,
    personas: _userPersonaService,
    imageGen: () => _imageGenService,
    memory: () => _memoryService,
    characters: () => _characterRepository,
    journalStore: () => realism.journalStore,
    growthDesk: () => realism.growthDesk,
    sceneGuests: castDoor.guests.state,
    sessions: () => sessionStore,
    graph: () => realism,
    turn: () => turnEngine,
    invalidateGreetingEval: castDoor.greetings.invalidateGreetingEval,
    characterIdFor: _getCharacterIdFromCard,
    ragCharacterId: _getCharacterId,
    reloadGroupRoster: () => entryDoor.roster.reloadGroupRoster(),
    enterSceneGuestSilently: (guest) =>
        castDoor.guests.enterSceneGuest(guest, speak: false),
    loadActiveObjectives: objectivesDoor.loadActiveObjectives,
    loadSpeakerObjectives: objectivesDoor.loadObjectivesForCurrentSpeaker,
    setActiveCharacter: (card) => entryDoor.chat.setActiveCharacter(card),
    deleteSessionQuietly: (id) =>
        editsDoor.editor.deleteSession(id, startReplacement: false),
  );
}
