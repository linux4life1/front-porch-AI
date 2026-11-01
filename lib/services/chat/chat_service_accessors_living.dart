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

/// Weather, ambitions, cast, and session-theme accessors.
/// Setters, gates, and init/dispose stay on [ChatServiceAccessors].
/// `objectivesActive` stays the live AND on that shell.
extension ChatServiceAccessorsLiving on ChatService {
  /// Today's story weather, or null when off (living-time-features.md §3).
  /// The story clock's current day, for consumers outside the service — the
  /// Pockets sidebar rows and the web facade filter set-aside clothing by it
  /// (yesterday's outfit must not survive the story's morning). One
  /// forwarder rather than exposing TimeService whole.
  ///
  /// MORNING-anchored since 2026-08-15 (maintainer-approved): every consumer
  /// of this accessor is a set-aside surface, and the calendar day flipping
  /// at 00:00 deleted the outfit mid-scene the moment a night ran past
  /// midnight — the docs always promised "the next story morning". Story
  /// stamps (journal cards, calendars) keep the calendar `dayCount`.
  int get storyDayCount => _timeService.morningAnchoredDayCount;

  /// The app's appearance choices, read live by the Ambient Stage
  /// (`sceneTokensFor`) so the chat page and the web chat state agree.
  AppearanceSettings get appearance => _storageService.appearance;

  /// The picture behind the chat: the Setting place's cover, or the nearest
  /// ancestor's, read live from the Setting's chain so a scene move paints
  /// the new place at once (`sceneBackdropOf`). Null when the chat has no
  /// Setting or no place in its chain has a picture, and the chat keeps the
  /// background it chose. Independent of the Ambient scene level: the
  /// picture is the ground the weather paints on, not part of the weather.
  SceneBackdrop? get sceneBackdrop {
    final primaryId = _chatPlaceSlots.primaryId;
    if (primaryId == null) return null;
    return sceneBackdropOf(_worldRepository.chainFor(primaryId));
  }

  /// The top-level world holding the chat's Setting, for a story made from
  /// this chat. The story's `worldName` names the world, not the place
  /// (stories-in-worlds §3.1), and `chainFor` is leaf-first, so this is the
  /// chain's last entry. Null when the chat has no Setting or its place is
  /// gone from the library.
  String? get chatSettingWorldName {
    final primaryId = _chatPlaceSlots.primaryId;
    if (primaryId == null) return null;
    return _worldRepository.chainFor(primaryId).lastOrNull?.name.trim();
  }

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

  /// Stream text with think blocks stripped (for display) — memoized on
  /// string identity (the overlay + web broadcast read it every notify).
  /// The `_evalCleanSrc`/`_evalCleanOut` memo fields stay on the class body.
  String get _realismEvalStreamTextCleanImpl =>
      identical(_realismEvalStreamText, _evalCleanSrc)
      ? _evalCleanOut!
      : _evalCleanOut = stripEvalThinkBlocks(
          _evalCleanSrc = _realismEvalStreamText,
        );
}

/// The group-realism test hooks (Reprocess Needs is on the edits bridge).
/// Public extension members: no fake overrides them.
extension ChatServiceRealismDoors on ChatService {
  /// Test-only: pin the group speaker the same way `_generateResponse` does
  /// ([GroupRealismStore.turnSpeakerId]). Do not assign `_session.activeCharacter`.
  @visibleForTesting
  void debugPinTurnSpeakerForRealism(String? charId) {
    _groupStore.turnSpeakerId = charId;
  }

  /// Test-only: set the glance bit on a group member slot.
  @visibleForTesting
  void debugSetGroupWithUser(String charId, bool? v) {
    _groupStore.memberForWrite(charId).withUser = v;
  }

  /// Test-only: live position injection through the wired BehavioralInjection.
  /// Does not stub `getOccupationBrief`.
  @visibleForTesting
  String debugBuildPositionInjection() =>
      _behavioralInjection.buildPositionInjection();

  /// Test-only: first-speaker [RealismDance.loadIntoScalars] without a turn.
  @visibleForTesting
  void debugReloadFirstGroupSpeakerScalars() {
    if (_groupCharacters.isEmpty) return;
    _realismDance.loadIntoScalars(
      _getCharacterIdFromCard(_groupCharacters.first),
    );
  }

  /// Test-only: emotion sitting in a group member slot (not live scalars).
  @visibleForTesting
  String debugGroupSlotEmotion(String charId) =>
      _groupRealism[charId]?.emotion ?? '';

  /// Test-only: stored needs for a group member. Empty when the slot has
  /// never carried a vector (does not invent [NeedsSimulation.needDefaults]).
  @visibleForTesting
  Map<String, int> debugGroupNeeds(String charId) =>
      _groupStore.needsOf(charId);

  /// Test-only: mark the in-flight post-gen as rejected so lite/engine
  /// finalize can prove they skip wear (same flag `_yieldSettlingTurn` sets).
  @visibleForTesting
  void debugRequestPostGenAbort() {
    _postGenAbortRequested = true;
  }

  /// Test-only: seed a member slot so a later soft turn can prove it does
  /// not leak this member's Needs / bond into the guest prompt, or so the
  /// member card can show that member's own mood, Lust and recovery.
  @visibleForTesting
  void debugSeedGroupSpeakerState(
    String charId, {
    Map<String, int>? needs,
    int? longTermTier,
    String? emotion,
    int? arousal,
    Refractory? refractory,
  }) {
    if (needs != null) _groupStore.setNeeds(charId, needs);
    if (longTermTier != null) {
      _groupStore.memberForWrite(charId).longTermTier = longTermTier;
    }
    if (emotion != null) _groupStore.memberForWrite(charId).emotion = emotion;
    if (arousal != null) _groupStore.memberForWrite(charId).arousal = arousal;
    if (refractory != null) {
      _groupStore.memberForWrite(charId).refractory = refractory;
    }
  }
}

/// Pockets & Wardrobe and Growth Rings doors for the sidebar, the web facade
/// and the other parts (bodies in [PocketsLedger] and [GrowthDesk]). Public
/// extension members: no fake overrides them.
extension ChatServiceMemoryDoors on ChatService {
  /// Combined Pockets gate: Porch Life global AND this character's card flag.
  /// The global is read through the class member first, as the extension
  /// body always did: the golden FakeChatService answers it (false) and the
  /// sidebar must not reach the ledger on a fake.
  bool pocketsEnabledFor(String characterId) =>
      pocketsFeatureEnabled && _pocketsLedger.pocketsEnabledFor(characterId);

  /// Put one item into a character's kit by hand (gift, conjured, or a
  /// record correction). The gate is read here first, as the extension body
  /// did, so a fake with Pockets off returns before reaching the ledger.
  Future<void> addPocketItem(
    String characterId, {
    required PocketSection section,
    required String name,
    bool gift = false,
    bool correction = false,
  }) async {
    if (!pocketsEnabledFor(characterId)) return;
    return _pocketsLedger.addPocketItem(
      characterId,
      section: section,
      name: name,
      gift: gift,
      correction: correction,
    );
  }

  /// Strike one item off by hand; also retires its item-memory card. No
  /// record (the class [pocketsFor], which fakes answer) returns first.
  Future<void> removePocketItem(
    String characterId, {
    required PocketSection section,
    required int index,
  }) async {
    if (pocketsFor(characterId) == null) return;
    return _pocketsLedger.removePocketItem(
      characterId,
      section: section,
      index: index,
    );
  }

  /// Persist [p] back to wherever that character's record lives.
  void setPocketsFor(String characterId, Pockets p) =>
      _pocketsLedger.setPocketsFor(characterId, p);

  /// What [c]'s card says they START a chat with.
  Pockets startingPocketsFor(CharacterCard c) =>
      PocketsLedger.startingPocketsFor(c);

  /// Seed every speaker's card kit unless the chat already has one. Every
  /// conversation entry path calls this.
  void seedPocketsFromCards() {
    if (!pocketsFeatureEnabled) return;
    _pocketsLedger.seedPocketsFromCards();
  }

  /// Review parking door for the sidebar banner + review dialog.
  GrowthReview get growthReview => _growthDesk.growthReview;

  /// Every ring for one owner in the current chat (active first, then past).
  List<GrowthRingData> growthRingsForOwner(String ownerId) =>
      _growthDesk.growthRingsForOwner(ownerId);

  /// Active-ring count for badges (group member cards, sidebar).
  int growthRingCountFor(CharacterCard card) =>
      _growthDesk.growthRingCountFor(card);

  /// Whether an owner still has an undistilled legacy evolved blob.
  bool hasLegacyGrowthBlobFor(String ownerId) =>
      _growthDesk.hasLegacyGrowthBlobFor(ownerId);

  /// Manually plant a pinned, user-authored ring.
  Future<void> plantGrowthRingFor(
    String ownerId,
    String text, {
    String category = 'trait',
  }) => _growthDesk.plantGrowthRingFor(ownerId, text, category: category);

  /// Edit a ring's wording/category in place.
  Future<void> editGrowthRing(
    GrowthRingData ring, {
    required String text,
    String? category,
  }) => _growthDesk.editGrowthRing(ring, text: text, category: category);

  Future<void> setGrowthRingPinned(String ringId, bool pinned) =>
      _growthDesk.setGrowthRingPinned(ringId, pinned);

  /// Demote a ring to Past growth (reversible).
  Future<void> retireGrowthRing(String ringId) =>
      _growthDesk.retireGrowthRing(ringId);

  /// Bring a Past ring back into the active set.
  Future<void> unretireGrowthRing(GrowthRingData ring) =>
      _growthDesk.unretireGrowthRing(ring);

  /// Hard-delete one ring.
  Future<void> deleteGrowthRing(String ringId) =>
      _growthDesk.deleteGrowthRing(ringId);

  /// Reset one owner's growth in this chat (rings and legacy blob).
  Future<void> resetGrowthFor(String ownerId) =>
      _growthDesk.resetGrowthFor(ownerId);

  /// Manual "Check now". Force-runs even on an empty window.
  Future<void> forceGrowthPass() => _growthDesk.forceGrowthPass();
}

/// Builds the Realism graph. Each hook stands in for a member of another
/// part until that part becomes a door (see [RealismShellHooks]); the
/// chat's own switches come from the session store's hooks, wired once.
extension ChatServiceRealismWiring on ChatService {
  RealismGraph _buildRealismGraph() {
    final shared = _sessionHooks();
    return RealismGraph(
      RealismDeps(
        session: _session,
        services: RealismServices(
          db: () => _db,
          storage: _storageService,
          personas: _userPersonaService,
          worlds: _worldRepository,
          macros: _macroResolver,
          kobold: _koboldService,
          characters: () => _characterRepository,
          memory: () => _memoryService,
          llmProvider: () => _llmProvider,
          maxSecondaryObjectives: kMaxSecondaryObjectives,
          evalStagger: _kEvalDispatchStagger,
        ),
        doors: RealismDoors(
          cast: () => castDoor,
          entry: () => entryDoor,
          edits: () => editsDoor,
          objectives: () => objectivesDoor,
          sessions: () => sessionStore,
        ),
        hooks: RealismShellHooks(
          characterIdFor: shared.characterIdFor,
          ragCharacterId: shared.ragCharacterId,
          disposed: () => _disposed,
          realismEnabled: shared.realismEnabled,
          chatRealism: shared.chatRealism,
          setChatRealism: shared.setChatRealism,
          needsSimEnabled: () => _needsSimEnabled,
          setNeedsSimEnabled: shared.setNeedsSimEnabled,
          objectivesActive: () => objectivesActive,
          enjoysLowHygiene: () => enjoysLowHygiene,
          afterglowSwitch: () => _afterglowSwitchForLoadedImpl,
          hardLockFor: _hardLockForSpeakerNamed,
          clockRunning: () => _clockRunning,
          oneShotActive: () => _oneShotActive,
          evalCancelled: () => _realismEvalCancelled,
          setEvalCancelled: (on) => _realismEvalCancelled = on,
          staleGreetingEval: _isStaleGreetingEval,
          memoryPassEpoch: () => _memoryPassEpoch,
          fireLLMEval: _fireLLMEval,
          withWorkerLane: _withWorkerLane,
          sideLaneLlm: () => _sideLaneLlm,
          sideLaneIsKobold: () => _sideLaneIsKobold,
          mouthLlm: () => _mouthLlm,
          mouthIsLocal: () => _mouthIsLocal,
          workerLaneActive: () => _workerLaneActive,
          testLlm: () => testLlmServiceOverride,
          testWorkerLlm: () => testWorkerLlmServiceOverride,
          testIsLocal: () => testIsLocalOverride,
          recordTodayPointerOp: _recordTodayPointerOp,
          journalResolvedToday: _journalResolvedToday,
          deactivateTodayObjective: _deactivateTodayObjective,
          upsertTodayObjective: _upsertTodayObjective,
          isHeldTodayObjective: _isHeldTodayObjective,
          onTodayObjectiveCompleted: _onTodayObjectiveCompleted,
          persistTodayObjectiveId: _persistTodayObjectiveId,
          macroContext: _buildChatMacroContext,
          isGenerating: () => _isGenerating,
          isTurnBusy: () => _isTurnBusy,
          chanceTimeSpeaker: () => chanceTimeSpeakerName,
          stampGroupUserTurnBaseline: _stampGroupUserTurnBaseline,
        ),
        notify: notifyListeners,
      ),
    );
  }
}

/// The Realism graph's state and objects under the names the rest of this
/// library still uses. Each line is debt its caller's package retires by
/// calling [ChatService.realism] itself (WP9b to WP10c).
extension _ChatServiceRealismNames on ChatService {
  // State the graph owns.
  Map<String, dynamic>? get _pendingRealismMetadata =>
      realism.registers.pending;
  set _pendingRealismMetadata(Map<String, dynamic>? v) =>
      realism.registers.pending = v;
  String get _characterEmotion => realism.registers.emotion;
  String get _emotionIntensity => realism.registers.intensity;
  set _isGrowthPassRunning(bool v) => realism.growthPassRunning = v;
  bool get _isEvaluatingRealism => realism.evalStatus.evaluating;
  set _isEvaluatingRealism(bool v) => realism.evalStatus.evaluating = v;
  bool get _isCancellingRealismEval => realism.evalStatus.cancelling;
  set _isCancellingRealismEval(bool v) => realism.evalStatus.cancelling = v;
  String get _realismEvalStreamText => realism.evalStatus.streamText;
  set _realismEvalStreamText(String v) => realism.evalStatus.streamText = v;
  Timer? get _evalChunkTimer => realism.evalStatus.chunkTimer;
  set _evalChunkTimer(Timer? t) => realism.evalStatus.chunkTimer = t;
  ChatPlaceSlots get _chatPlaceSlots => realism.places.slots;
  SceneMoveState get _sceneMoves => realism.places.sceneMoves;
  LorebookTimedEffects get _loreTimedEffects => realism.lore.timedEffects;
  ToolTransportProbe get _toolProbe => realism.transport.probe;
  FireToolEval get _fireToolEval => realism.transport.fireToolEval;

  // The leaves.
  LorebookScanner get _lorebookScanner => realism.lore.scanner;
  LorebookInjector get _lorebookInjector => realism.lore.injector;
  TimeService get _timeService => realism.time;
  StoryClockReader get _clockReader => realism.clockReader;
  StoryClockWriter get _clockWriter => realism.clockWriter;
  EpisodeCrumbMinter get _episodeCrumbs => realism.episodeCrumbs;
  BirthdaySync get _birthdaySync => realism.birthdays;
  ChaosModeService get _chaosModeService => realism.chaos;
  NsfwService get _nsfwService => realism.nsfw;
  NeedsSimulation get _needsSimulation => realism.needs;
  GroupRealismStore get _groupStore => realism.groups;
  Map<String, GroupMemberRealism> get _groupRealism => realism.groups.members;
  NeedsPass get _needsPass => realism.needsPass;
  StandingMood get _standingMood => realism.standingMood;
  MoodRegisters get _mood => realism.mood;
  RealismSnapshot get _realismSnapshot => realism.snapshot;
  RealismJudges get _realismJudges => realism.judges;
  RealismDance get _realismDance => realism.dance;
  RelationshipService get _relationshipService => realism.relationship;
  ExpressionService get _expressionService => realism.expression;
  AuthorNoteBuilder get _authorNoteBuilder => realism.authorNotes;
  BehavioralInjection get _behavioralInjection => realism.behavioralInjection;
  InventoryInjection get _inventoryInjection => realism.inventoryInjection;
  PocketsLedger get _pocketsLedger => realism.pocketsLedger;
  PocketsRewinds get _pocketsRewinds => realism.pocketsRewinds;
  PocketsPass get _pocketsPass => realism.pocketsPass;
  ItemCardJournal get _itemCards => realism.itemCards;
  ReplyFacts get _replyFacts => realism.replyFacts;
  AfterglowPass get _afterglow => realism.afterglow;
  PromiseDebtService get _promiseDebtService => realism.promiseDebt;
  DreamService get _dreamService => realism.dreams;
  ChaosInjection get _chaosInjection => realism.chaosInjection;
  RealismStateInjection get _realismStateInjection =>
      realism.realismStateInjection;
  LlmEvalEngine get _llmEvalEngine => realism.llmEvalEngine;
  RealismEvals get _realismEvals => realism.evals;
  ObjectiveProposal get _objectiveProposal => realism.objectiveProposal;
  CastFeelingsJudge get _castFeelingsJudge => realism.castFeelingsJudge;
  JournalStore get _journalStore => realism.journalStore;
  PorchMemoryImportService get _porchMemoryImport => realism.porchImport;
  ToolSupportTester get _toolSupportTester => realism.toolSupportTester;
  JournalMaintenance get _journalMaintenance => realism.journalMaintenance;
  JournalInjection get _journalInjection => realism.journalInjection;
  GrowthStore get _growthStore => realism.growthStore;
  GrowthDesk get _growthDesk => realism.growthDesk;

  // Behaviour.
  RealismScope _realismScope() => realism.scope;
  bool get _realismActiveThisMode => realism.realismActiveThisMode;
  String get _evalBackendIdentity => realism.transport.backendIdentity;
  String _mouthEvalIdentity({String remoteModel = ''}) =>
      realism.transport.mouthIdentity(remoteModel: remoteModel);
  String? get _localModelPath => realism.transport.localModelPath;
  Future<LlmToolResponse?> _fireToolEvalUnheld(
    ToolEvalSpec spec, {
    LLMService? via,
    String? identity,
  }) =>
      realism.transport.fireToolEvalUnheld(spec, via: via, identity: identity);
  PlayerSkip _buildPlayerSkip() => realism.playerSkip();
  List<LoreEntryRef> _collectLoreRefs({bool? inheritOverride}) =>
      realism.lore.collectLoreRefs(inheritOverride: inheritOverride);
  void _restoreRealismStateForSpeaker(
    ChatMessage msg, {
    bool restoreClock = false,
  }) => realism.restores.forSpeaker(msg, restoreClock: restoreClock);
  void _restoreRealismStateFromMessage(
    ChatMessage? msg, {
    String? groupSpeakerId,
    bool restoreClock = false,
  }) => realism.restores.fromMessage(
    msg,
    groupSpeakerId: groupSpeakerId,
    restoreClock: restoreClock,
  );
  Future<void> _runPostGenNeedsChecks(String responseText) =>
      realism.restores.runPostGenNeedsChecks(responseText);
  void _applyMoodDecay() => realism.restores.applyMoodDecay();
}
