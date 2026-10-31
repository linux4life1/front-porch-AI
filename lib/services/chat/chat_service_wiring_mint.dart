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
    loadSession: loadSession,
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

/// The cast door's state and behaviour under the names the rest of this
/// library still uses. Each line is debt its caller's package retires by
/// calling [ChatService.castDoor] itself (WP5, WP7 to WP10).
extension _ChatServiceCastNames on ChatService {
  SceneGuestState get _sceneGuest => castDoor.guests.state;
  AwayPulseState get _awayPulse => castDoor.away.state;
  DirectorScene get _directorScene => castDoor.directorScene;
  bool get _narrating => castDoor.narrating;
  String? get _entranceDirective => castDoor.entranceDirective;
  set _entranceDirective(String? v) => castDoor.entranceDirective = v;
  set _stoppedReplyAnchor(ChatMessage? v) =>
      castDoor.guests.stoppedReplyAnchor = v;
  set _greetingIndex(int v) => castDoor.greetings.greetingIndex = v;
  int get _greetingIndex => castDoor.greetings.greetingIndex;
  bool get _greetingEvalPending => castDoor.baseline.greetingEvalPending;
  set _greetingEvalPending(bool v) => castDoor.baseline.greetingEvalPending = v;
  bool get _isProcessingGreeting => castDoor.baseline.isProcessingGreeting;
  set _isProcessingGreeting(bool v) =>
      castDoor.baseline.isProcessingGreeting = v;
  String? get _pendingIdleCue => castDoor.idle.pendingIdleCue;
  set _pendingIdleCue(String? v) => castDoor.idle.pendingIdleCue = v;
  bool get _autoResponseInProgress => castDoor.idle.autoResponseInProgress;
  set _hasCompletedExchange(bool v) => castDoor.idle.hasCompletedExchange = v;
  int get _consecutiveAutoResponses => castDoor.idle.consecutiveAutoResponses;
  set _consecutiveAutoResponses(int v) =>
      castDoor.idle.consecutiveAutoResponses = v;

  bool _sceneChanged(String? token) => castDoor.sceneChanged(token);
  void _setGuestStatus(
    String? msg, {
    bool isError = false,
    bool sticky = false,
  }) => castDoor.guests.setStatus(msg, isError: isError, sticky: sticky);
  void _noteStoppedReply({required bool replyKept}) =>
      castDoor.guests.noteStoppedReply(replyKept: replyKept);
  void _resetGuestActivityState() => castDoor.guests.resetActivityState();
  void _clearExitUndo() => castDoor.guests.clearExitUndo();
  bool _isGuestAuthoredMessage(ChatMessage m) =>
      castDoor.guests.isGuestAuthoredMessage(m);
  CharacterCard? _sceneGuestForMessage(ChatMessage m) =>
      castDoor.guests.sceneGuestForMessage(m);
  CharacterCard? _directAddressRoutedGuest(String promptText) =>
      castDoor.guests.directAddressRoutedGuest(promptText);
  Future<void> _resolveSceneGuestCards() =>
      castDoor.guests.resolveSceneGuestCards();
  Future<void> _addGuestWithStatus({
    required String displayName,
    CharacterCard? existing,
    Future<GuestMintResult> Function(void Function(String step) onStatus)? mint,
  }) => castDoor.guests.addGuestWithStatus(
    displayName: displayName,
    existing: existing,
    mint: mint,
  );
  Future<GuestMintResult> _mintSceneGuest(
    String name,
    String concept, {
    void Function(String step)? onStatus,
  }) => castDoor.joins.mintSceneGuest(name, concept, onStatus: onStatus);
  Future<bool> _generateMemberEntrance(CharacterCard card, String intent) =>
      castDoor.joins.generateMemberEntrance(card, intent);

  Future<void> _commitPendingMemberExit() =>
      castDoor.roster.commitPendingMemberExit();
  Future<void> _deleteMemberCleanup(String charId, String? avatarFilename) =>
      castDoor.roster.deleteMemberCleanup(charId, avatarFilename);
  bool _speakerIsSoft(CharacterCard speaker) =>
      castDoor.roster.speakerIsSoft(speaker);
  Future<bool> _collapseGroupToSolo(GroupChatRepository repo) =>
      castDoor.collapse.collapseGroupToSolo(repo);
  Future<void> _carryHostStateIntoForkedGroup(
    String hostName,
    String originalCharId,
    String? hostSessionId,
    Map<String, dynamic> state,
  ) => castDoor.collapse.carryHostStateIntoForkedGroup(
    hostName,
    originalCharId,
    hostSessionId,
    state,
  );
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

  Future<void> _seedOpeningPosture() => castDoor.baseline.seedOpeningPosture();
  Future<void> _runPostGreetingEval() =>
      castDoor.baseline.runPostGreetingEval();
  Future<void> _runRetroactiveBaselineEval() =>
      castDoor.baseline.runRetroactiveBaselineEval();
  Future<void> _invalidateGreetingEval() =>
      castDoor.greetings.invalidateGreetingEval();
  String _buildFirstMessage(CharacterCard character, {String? greetingText}) =>
      castDoor.greetings.buildFirstMessage(
        character,
        greetingText: greetingText,
      );
  String _memberOpeningGreetingText(CharacterCard member) =>
      castDoor.greetings.memberOpeningGreetingText(member);
  CharacterCard? _greetingOwnerCard() => castDoor.greetings.greetingOwnerCard();
  bool get _isOpeningGreetingChat => castDoor.greetings.isOpeningGreetingChat;
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
  void _restoreGreetingIndex() => castDoor.greetings.restoreGreetingIndex();
  Future<void> _reapplyOpeningOverlayIfNeeded() =>
      castDoor.greetings.reapplyOpeningOverlayIfNeeded();

  Future<void> _runAwayPulse({
    required String userText,
    required bool fromUserSend,
  }) => castDoor.away.runAwayPulse(
    userText: userText,
    fromUserSend: fromUserSend,
  );
  void _releaseHeldAway(CharacterCard card) =>
      castDoor.away.releaseHeldAway(card);
  void _resetIdleTimer() => castDoor.idle.resetIdleTimer();
  void _cancelIdleTimer() => castDoor.idle.cancelIdleTimer();
}
