// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Slice 7 mint seam: the chat-side half of "minted places" — hold the
// proposal, hand it to PlaceFactory on the tap, remember ignores.
// Split from wiring_injection (the 500-line ratchet and one-responsibility
// per seam file); the move seam stayed there because it is two methods
// deep in the slots law. The door builders (WP2 of
// docs/design/chat-service-decomposition.md) sit at the end.

part of '../chat_service.dart';

extension ChatServicePlaceMint on ChatService {
  /// A proposed NEW place the judge heard named in the narration,
  /// awaiting the tap. Nothing exists in the library until then.
  ProposedPlace? get pendingPlaceMint => _sceneMoves.mints.pending;

  void flagSuggestedPlaceMint(String name, String descriptor) {
    if (name.trim().isEmpty) return;
    final setting = chatPrimaryWorldId == null
        ? null
        : _worldRepository.worldById(chatPrimaryWorldId!);
    _sceneMoves.mints.pending = ProposedPlace(
      name: name.trim(),
      descriptor: descriptor.trim(),
      settingName: setting?.name ?? '',
    );
    debugPrint('[Realism:Mint] suggested place pending: $name');
    notifyListeners();
  }

  /// Add (and optionally move the scene into) the minted place. The
  /// mint reads the live narration window for grounding, saves through
  /// the ONE repository law, and on 'alsoMove' runs the SAME slot swap
  /// a manual move runs (old setting demotes to top of Lore). Returns
  /// the result so the dialog can speak; the pending flag clears on
  /// success or honest failure — a refused draft must not nag, the
  /// author just declined a bad guess.
  Future<PlaceMintResult> acceptMintedPlace({required bool alsoMove}) async {
    final proposal = _sceneMoves.mints.pending;
    final settingId = chatPrimaryWorldId;
    if (proposal == null) {
      return const PlaceMintResult.failure('nothing is being proposed');
    }
    final setting = settingId == null
        ? null
        : _worldRepository.worldById(settingId);
    if (setting == null) {
      _sceneMoves.mints.resolve();
      notifyListeners();
      return const PlaceMintResult.failure(
        'the scene has no setting to place it under',
      );
    }
    final grounding = [
      for (final m
          in _session.messages.length <= 6
              ? _session.messages
              : _session.messages.sublist(_session.messages.length - 6))
        if (m.displayText.trim().isNotEmpty) m.displayText.trim(),
    ].join('\n');
    // Constructed at the call site like SceneGuestFactory (this file is
    // an extension and holds no fields); the eval seams make a local
    // KoboldCpp able to mint too — tools first, text floor (design §7).
    final factory = PlaceFactory(
      _worldRepository,
      fireToolEval: _fireToolEval,
      fireTextEval: (p, {onChunk}) => _fireLLMEval(p, onChunk: onChunk),
      probe: _toolProbe,
      getBackendIdentity: () => _evalBackendIdentity,
    );
    final result = await factory.mint(
      name: proposal.name,
      descriptor: proposal.descriptor,
      setting: setting,
      sceneGrounding: grounding,
    );
    _sceneMoves.mints.resolve();
    if (result.ok && alsoMove && result.world != null) {
      await setChatPlaceSlots(
        primaryId: result.world!.id,
        loreIds: [
          setting.id,
          for (final l in _chatPlaceSlots.loreIds)
            if (l != setting.id) l,
        ],
      );
    }
    notifyListeners();
    return result;
  }

  /// Ignore: remember the name for this chat — it will not be proposed
  /// again until the chat is re-opened (session-reset law, Scene-Guest
  /// names).
  void ignoreMintedPlace() {
    final proposal = _sceneMoves.mints.pending;
    if (proposal == null) return;
    _sceneMoves.mints.ignore(proposal.name);
    notifyListeners();
  }
}

/// Builds the doors the shell owns. Each callback below stands in for a
/// private member of another part until that part becomes a door too.
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
    isBusy: () => _isTurnBusy || castDoor.guests.state.busy,
    setStatus: (msg, {isError = false, sticky = false}) =>
        castDoor.guests.setStatus(msg, isError: isError, sticky: sticky),
    sceneChanged: (token) => castDoor.sceneChanged(token),
    guestCards: () => castDoor.guests.state.cards,
    characterIdFor: _getCharacterIdFromCard,
    expressionLabel: () => currentExpressionLabel,
    timeOfDay: () => _timeService.timeOfDay,
  );

  ActionsDoor _buildActionsDoor() => ActionsDoor(
    session: _session,
    personas: _userPersonaService,
    mouthLlm: () => _mouthLlm,
    mouthStream: _mouthGenerateStream,
  );

  /// The cast door. Each hook is debt (see [CastShellHooks]).
  CastDoor _buildCastDoor() => CastDoor(
    CastDeps(
      session: _session,
      storage: _storageService,
      personas: _userPersonaService,
      macros: _macroResolver,
      database: () => _db,
      characters: () => _characterRepository,
      groupRepository: () => _groupChatRepository,
      imageGen: () => _imageGenService,
      realism: _realismScope,
      evals: () => _realismEvals,
      snapshot: () => _realismSnapshot,
      dance: () => _realismDance,
      judges: () => _realismJudges,
      mood: () => _mood,
      clockWriter: () => _clockWriter,
      chaos: () => _chaosModeService,
      evalEngine: () => _llmEvalEngine,
      journal: () => _journalStore,
      growthStore: () => _growthStore,
      growthDesk: () => _growthDesk,
      objectives: () => objectivesDoor,
      characterIdFor: _getCharacterIdFromCard,
      saveChat: _saveChat,
      notify: notifyListeners,
      hooks: _castHooks(),
    ),
  );

  CastShellHooks _castHooks() => CastShellHooks(
    isTurnBusy: () => _isTurnBusy,
    disposed: () => _disposed,
    generate:
        ({
          guestSpeaker,
          forceSpeaker,
          autonomous = false,
          skipSpeakerEval = false,
        }) => _generateResponse(
          GenerationMode.normal,
          guestSpeaker: guestSpeaker,
          forceSpeaker: forceSpeaker,
          autonomous: autonomous,
          skipSpeakerEval: skipSpeakerEval,
        ),
    waitForTurnToSettle: _waitForTurnToSettle,
    deleteMessage: deleteMessage,
    embedFor: (id) => _maybeEmbedMessages(characterIdOverride: id),
    isEvaluatingRealism: () => _isEvaluatingRealism,
    ttsSpeaking: () => _ttsService != null && _ttsService!.isSpeaking,
    mouthReady: () => _mouthLlm.isReady,
    needsActive: () => _needsPass.active,
    directing: () => _directing,
    setObserverMode: (on) => _observerMode = on,
    groupSpeakerSkips: _groupSpeakerSkips,
    setNextCharacter: setNextCharacter,
    nextCharacter: () => nextCharacter,
    pickPresentSpeaker: _pickPresentGroupSpeaker,
    workFieldsFor: _workFieldsFor,
    memberInScene: _memberInScene,
    reloadGroupRoster: _reloadGroupRoster,
    addToGroup: (card, repo, {asLite = false}) =>
        addCharacterToGroup(card, repo, asLite: asLite),
    removeFromGroup: removeCharacterFromGroup,
    forkToGroup:
        (
          additional,
          repo, {
          entrances = const {},
          liteArrivalKeys = const {},
        }) => forkToGroupChat(
          additional,
          repo,
          entrances: entrances,
          liteArrivalKeys: liteArrivalKeys,
        ),
    forgetMember: (id) {
      _groupRealism.remove(id);
      _groupAuthorNotes.remove(id);
      _groupAuthorNoteStrengths.remove(id);
      _groupCharacterSystemPrompts.remove(id);
      _groupCharacterRAGPriorities.remove(id);
    },
    seedPromotedNeeds: _seedPromotedNeeds,
    setActiveCharacter: setActiveCharacter,
    loadSession: (id) => sessionStore.loader.loadSession(id),
    ragCharacterId: _getCharacterId,
    parseJsonMap: _tryParseJsonMap,
    captureSurvivor: _captureSurvivorScalars,
    carryHostScalars: _carryHostScalarsIntoMember,
    realismActiveThisMode: () => _realismActiveThisMode,
    oneShotActive: () => _oneShotActive,
    evalCancelled: () => _realismEvalCancelled,
    clearEvalCancelled: () => _realismEvalCancelled = false,
    greetingEvalGen: () => _greetingEvalGen,
    bumpGreetingEvalGen: () => _greetingEvalGen++,
    greetingZone: (token, index) => {
      _kGreetingEvalToken: token,
      _kGreetingEvalIndex: index,
    },
    markPostGreetingEvalEntered: () => testPostGreetingEvalEntered = true,
    cancelRealismEval: cancelRealismEval,
    evalStagger: _kEvalDispatchStagger,
    applySeededPassageOfTime: _applySeededPassageOfTime,
    seedGreetingNeeds: _seedGreetingNeeds,
    seedSlotNeeds: _seedSlotNeeds,
    pocketsEnabledFor: pocketsEnabledFor,
    setPocketsFor: setPocketsFor,
    clearHostPockets: () => _pockets = null,
    playerSkip: (line, {stale}) => _buildPlayerSkip().apply(line, stale: stale),
    mintEpisodeCrumbs: (before, after) =>
        _episodeCrumbs.maybeMint(before, after),
    timeSkipBridgeContext: _timeSkipBridgeContext,
    selectGreeting: selectGreeting,
    openingAllGreetings: () => openingAllGreetings,
    resolvedOpeningGreetings: _resolvedOpeningGreetings,
    guestDirector: _ensureSceneGuestDirector,
    mintLlm: () => testLlmServiceOverride ?? _llmProvider?.activeService,
    stageIdleTurn: _stageIdleTurn,
  );

  /// True while forked-in character entrances are still playing. The
  /// composer mirrors sendMessage's early return on it, so it does not
  /// consume an attached photo for a turn sendMessage would drop.
  bool get entrancesInFlight => _entrancesInFlight;

  /// From the start of a photo turn's captioning through the end of its send
  /// flow: the captions run while the generating flag is down, so this keeps
  /// a second sendMessage from interleaving. Photo turns only.
  bool get isPhotoTurnInFlight => mediaDoor.photoTurnInFlight;
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
        macros: _macroResolver,
        characters: () => _characterRepository,
        groupRepository: () => _groupChatRepository,
        realism: _realismScope,
        cast: () => castDoor,
        objectives: () => objectivesDoor,
        media: () => mediaDoor,
        lorebook: () => _lorebookScanner,
        loreTimers: () => _loreTimedEffects,
        expression: () => _expressionService,
        clockReader: () => _clockReader,
        clockWriter: () => _clockWriter,
        growthStore: () => _growthStore,
        growthDesk: () => _growthDesk,
        journal: () => _journalStore,
        porchImport: () => _porchMemoryImport,
        birthdays: () => _birthdaySync,
        chaos: () => _chaosModeService,
        needsPass: () => _needsPass,
        pocketsRewinds: () => _pocketsRewinds,
        dance: () => _realismDance,
        mood: () => _mood,
        sceneMoves: _sceneMoves,
        autoChat: _autoChatBudget,
      ),
      hooks: SessionShellHooks(
        characterIdFor: _getCharacterIdFromCard,
        ragCharacterId: _getCharacterId,
        waitForTurnToSettle: _waitForTurnToSettle,
        cancelAndWaitForGeneration: _cancelAndWaitForGeneration,
        realismEnabled: () => _realismEnabled,
        chatRealism: () => _realismChatSwitch,
        setChatRealism: (on) => _realismChatSwitch = on,
        setNeedsSimEnabled: (on) => _needsSimEnabled = on,
        objectivesEnabled: () => _objectivesEnabled,
        setObjectivesEnabled: (on) => _objectivesEnabled = on,
        enjoysLowHygiene: () => _enjoysLowHygiene,
        setEnjoysLowHygiene: (on) => _enjoysLowHygiene = on,
        afterglowChatSwitch: () => _afterglowChatSwitchImpl,
        applySeededPassageOfTime: _applySeededPassageOfTime,
        onRealismStarted: _onRealismStarted,
        setGrowthPassRunning: (on) => _isGrowthPassRunning = on,
        restoreForSpeaker: (msg, {restoreClock = false}) =>
            _restoreRealismStateForSpeaker(msg, restoreClock: restoreClock),
        restoreFromMessage: (msg, {restoreClock = false}) =>
            _restoreRealismStateFromMessage(msg, restoreClock: restoreClock),
        hostPockets: () => _pockets,
        setHostPockets: (record) => _pockets = record,
        seedPocketsFromCards: seedPocketsFromCards,
        setPocketsFor: setPocketsFor,
        pocketsEnabledFor: pocketsEnabledFor,
        resetDirectorModeToDefault: _resetDirectorModeToDefault,
        rekeyGroupStores: _rekeyGroupStores,
        reloadChatWorldIds: _reloadChatWorldIds,
        chatPlaceIds: () => _chatPlaceSlots.allIds,
        clearContextBudget: _clearContextBudget,
        loadContextBudget: _loadContextBudgetForSession,
        persistContextBudget: _persistContextBudgetForSession,
        armPromptPicker: _armPromptPickerIfDue,
        setActiveCharacter: setActiveCharacter,
        setActiveGroup: setActiveGroup,
        beginSessionLoad: beginSessionLoad,
        endSessionLoad: endSessionLoad,
      ),
      notify: notifyListeners,
    ),
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
  /// past the services is debt the Realism graph (WP9) and the turn engine
  /// (WP10) retire.
  TransferHost _buildTransferHost() => TransferHost(
    db: () => _db,
    storage: _storageService,
    personas: _userPersonaService,
    imageGen: () => _imageGenService,
    memory: () => _memoryService,
    characters: () => _characterRepository,
    journalStore: () => _journalStore,
    growthDesk: () => _growthDesk,
    sceneGuests: castDoor.guests.state,
    sessions: () => sessionStore,
    captureRealismState: () => _realismSnapshot.capture(),
    isTurnBusy: () => _isTurnBusy,
    isGenerating: () => _isGenerating,
    invalidateGreetingEval: castDoor.greetings.invalidateGreetingEval,
    characterIdFor: _getCharacterIdFromCard,
    ragCharacterId: _getCharacterId,
    reloadGroupRoster: _reloadGroupRoster,
    enterSceneGuestSilently: (guest) =>
        castDoor.guests.enterSceneGuest(guest, speak: false),
    loadActiveObjectives: objectivesDoor.loadActiveObjectives,
    loadSpeakerObjectives: objectivesDoor.loadObjectivesForCurrentSpeaker,
    formatForRagEmbedding: _formatMessagesForRagEmbedding,
    setActiveCharacter: setActiveCharacter,
    deleteSessionQuietly: (id) =>
        editsDoor.editor.deleteSession(id, startReplacement: false),
  );
}

/// The session store's state and behaviour under the names the rest of
/// this library still uses. Each line is debt its caller's package retires
/// by calling [ChatService.sessionStore] itself (WP8 to WP10).
extension _ChatServiceSessionNames on ChatService {
  SessionHistoryWindow get _history => sessionStore.history;
  String get _summary => sessionStore.summary;
  set _summary(String v) => sessionStore.summary = v;
  int get _summaryLastIndex => sessionStore.summaryLastIndex;
  set _summaryLastIndex(int v) => sessionStore.summaryLastIndex = v;
  bool get _summaryPaused => sessionStore.summaryPaused;
  set _summaryPaused(bool v) => sessionStore.summaryPaused = v;
  bool get _isSummaryGenerating => sessionStore.isSummaryGenerating;
  set _isSummaryGenerating(bool v) => sessionStore.isSummaryGenerating = v;
  set _recapClearArmed(bool v) => sessionStore.recapClearArmed = v;
  String get _authorNote => sessionStore.authorNote;
  set _authorNote(String v) => sessionStore.authorNote = v;
  int get _authorNoteStrength => sessionStore.authorNoteStrength;
  set _authorNoteStrength(int v) => sessionStore.authorNoteStrength = v;
  ChatGenerationSettings get _sessionGenSettings => sessionStore.genSettings;
  Map<String, String> get _selectedLooks => sessionStore.selectedLooks;
  String? get _sessionName => sessionStore.sessionName;
  String? get _sessionDescription => sessionStore.sessionDescription;
  set _parentSessionId(String? v) => sessionStore.parentSessionId = v;
  set _forkIndex(int? v) => sessionStore.forkIndex = v;
  bool get _isNewChat => sessionStore.isNewChat;
  set _isNewChat(bool v) => sessionStore.isNewChat = v;
  bool get _isLoadingSession => sessionStore.isLoadingSession;
  set _isLoadingSession(bool v) => sessionStore.isLoadingSession = v;
  int get _chatSwitches => sessionStore.chatSwitches;
  Future<void> get _saveChain => sessionStore.saveChain;
  bool get _absenceAckPending => sessionStore.absenceAckPending;
  set _absenceAckPending(bool v) => sessionStore.absenceAckPending = v;
  bool get _absenceAckConsumed => sessionStore.absenceAckConsumed;
  set _absenceAckConsumed(bool v) => sessionStore.absenceAckConsumed = v;

  // The today line (TodaySentence).
  String? get _todaySentence => sessionStore.today.todaySentence;
  String? get _todayObjectiveId => sessionStore.today.todayObjectiveId;
  set _todayObjectiveId(String? v) => sessionStore.today.todayObjectiveId = v;
  String? get _todayObjectiveText => sessionStore.today.todayObjectiveText;
  set _todayObjectiveText(String? v) =>
      sessionStore.today.todayObjectiveText = v;
  set _onTodayAbandoned(void Function(String? held)? v) =>
      sessionStore.today.onTodayAbandoned = v;
  void _clearTodayPointer() => sessionStore.today.clearTodayPointer();

  // A group's per-member settings (GroupSessionConfig).
  GroupSessionConfig get _groupConfig => sessionStore.groupConfig;
  Map<String, String> get _groupAuthorNotes => _groupConfig.authorNotes;
  set _groupAuthorNotes(Map<String, String> v) => _groupConfig.authorNotes = v;
  Map<String, int> get _groupAuthorNoteStrengths =>
      _groupConfig.authorNoteStrengths;
  set _groupAuthorNoteStrengths(Map<String, int> v) =>
      _groupConfig.authorNoteStrengths = v;
  Map<String, String> get _groupCharacterSystemPrompts =>
      _groupConfig.characterSystemPrompts;
  set _groupCharacterSystemPrompts(Map<String, String> v) =>
      _groupConfig.characterSystemPrompts = v;
  bool get _groupRagEnabled => _groupConfig.ragEnabled;
  set _groupRagEnabled(bool v) => _groupConfig.ragEnabled = v;
  int get _groupRetrievalCount => _groupConfig.retrievalCount;
  set _groupRetrievalCount(int v) => _groupConfig.retrievalCount = v;
  double get _groupMemoryBudgetPercent => _groupConfig.memoryBudgetPercent;
  set _groupMemoryBudgetPercent(double v) =>
      _groupConfig.memoryBudgetPercent = v;
  Map<String, double> get _groupCharacterRAGPriorities =>
      _groupConfig.characterRAGPriorities;
  set _groupCharacterRAGPriorities(Map<String, double> v) =>
      _groupConfig.characterRAGPriorities = v;

  // Load, save and the window.
  Future<void> _saveChat({bool replaceAll = false}) =>
      sessionStore.save(replaceAll: replaceAll);
  void _rememberRecapEdit(String text) => sessionStore.rememberRecapEdit(text);
  Future<void> _loadLastSession() => sessionStore.loader.loadLastSession();
  Future<bool> _loadGroupRealismStateFromSession(Session? session) =>
      sessionStore.groupState.loadGroupRealismState(session);
  Future<void> _awaitHistoryHydrated() =>
      sessionStore.window.awaitHistoryHydrated();
  Future<void> _seedChatWorldsForNewSession({List<String>? carryRefs}) =>
      sessionStore.forker.seedChatWorldsForNewSession(carryRefs: carryRefs);
}
