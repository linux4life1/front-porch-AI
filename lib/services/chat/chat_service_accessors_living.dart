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

  /// Pure recompute from existing state — nothing stored, so save/load and
  /// group re-entry agree for free. Gate: a MOVING clock + the global toggle.
  /// Weather is deterministic math over the day count and needs no eval of its
  /// own, so its realism term was only ever standing in for "the clock is
  /// frozen"; [_clockRunning] says that directly, and the Porch Life tab has
  /// always told users weather depends on Passage of Time. Consumed by the
  /// injection leaf, the needs decay modifiers, the sidebar TimeStrip, and the
  /// web facade — one source.

  DailyWeather? get _currentWeatherImpl {
    if (!_clockRunning || !_storageService.realismSettings.weatherEnabled) {
      return null;
    }
    // The Setting's chain owns weather (locations slice 2): the nearest
    // climate-enabled ancestor authors it. Empty chain OR an all-lore-only
    // chain ⇒ off. Lore climate-on (e.g. Mars in Lore) never turns weather
    // on — a chain walk only ever reaches the Setting's own ancestors.
    final primaryId = _chatPlaceSlots.primaryId;
    final chain = primaryId == null
        ? const <World>[]
        : _worldRepository.chainFor(primaryId);
    if (!chainAllowsClimate(chain)) {
      return null;
    }
    final seed = _currentSessionId;
    if (seed == null) return null;
    return WeatherEngine.weatherFor(
      sessionSeed: seed,
      dayCount: _timeService.dayCount,
      date: _timeService.clock,
      biomeAtDay: _biomeAtDay,
    );
  }

  /// Tomorrow's story weather under the same gate as [currentWeather].
  /// Because the engine is a prefix-stable deterministic walk, this forecast
  /// is exactly what day dayCount+1 will be when the story clock reaches it
  /// (dayCount is derived from the calendar date, so +1 day ⇔ +1 dayCount) —
  /// foreshadowed fronts always arrive (except the first day of a mid-chat
  /// climate switch — see [WeatherInjection.suppressForeshadow]).
  /// Recompute is O(dayCount) integer math, called once per turn by the
  /// injection and once per facade read.
  DailyWeather? get _upcomingWeatherImpl {
    if (currentWeather == null) return null;
    return WeatherEngine.weatherFor(
      sessionSeed: _currentSessionId!,
      dayCount: _timeService.dayCount + 1,
      date: _timeService.clock.add(const Duration(days: 1)),
      biomeAtDay: _biomeAtDay,
    );
  }

  /// The current DAY-PART's weather (Living Time §3 v3): the day script's
  /// condition for the story-clock hour plus the deterministic °C. Same gate
  /// and recompute contract as [currentWeather] — nothing stored. Consumed
  /// by the injection, the needs decay view below, the sidebar chip, and the
  /// web facade.
  SegmentWeather? get _currentSegmentWeatherImpl {
    if (currentWeather == null) return null;
    return WeatherSegments.segmentWeatherFor(
      sessionSeed: _currentSessionId!,
      dayCount: _timeService.dayCount,
      date: _timeService.clock,
      hour: _timeService.clock.hour,
      biomeAtDay: _biomeAtDay,
    );
  }

  /// Sidebar/web read surface (Living Time §6): [card]'s ambitions with
  /// live progress — triggers the lazy cache warm, so first render may show
  /// "just beginning" and correct itself one notify later. The ONE merge of
  /// card-authored definitions + per-chat progress; desktop and web both
  /// read through it so they can't drift.
  List<({String text, int progress})> _ambitionsForImpl(CharacterCard card) {
    final sessionId = _currentSessionId;
    final list = card.frontPorchExtensions?.ambitions ?? const [];
    if (sessionId == null || list.isEmpty) return const [];
    final cid = _getCharacterIdFromCard(card);
    _ambitionService.ensureCacheWarm(sessionId, cid);
    final progress =
        _ambitionService.cachedProgress(sessionId, cid) ?? const {};
    return [for (final a in list) (text: a, progress: progress[a] ?? 0)];
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
    final host = _activeCharacter;
    return [
      if (host != null) ChatParticipant(card: host, isHost: true),
      for (final g in _sceneGuest.cards)
        ChatParticipant(card: g, isHost: false),
    ];
  }

  /// Index of the most recent host (main character) message that is buried only
  /// under Scene Guest (Lite NPC) chime-in replies — i.e. the tail of the chat
  /// is one or more guest messages sitting directly on top of it. Returns null
  /// when the last message is already the host's (use the normal last-message
  /// regen), when a user/System message breaks the guest tail, or outside a 1:1
  /// scene. The UI uses this to offer "regenerate the main character" on a host
  /// bubble that the last-message-only regen button can no longer reach.
  int? get _regenerableHostBelowGuestsIndexImpl {
    if (_activeGroup != null || _messages.isEmpty) return null;
    if (!_isGuestAuthoredMessage(_messages.last)) return null;
    for (int i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      if (m.isUser || m.sender == 'System') return null;
      if (!_isGuestAuthoredMessage(m)) return i;
    }
    return null;
  }

  void _editMessageImpl(int index, String newText) async {
    if (index >= 0 && index < _messages.length) {
      final msg = _messages[index];
      // text setter keeps swipe + realism metadata (chips survive edit).
      msg.text = newText;
      // Persist index — on-screen 0..23 is a tail window, not the diary cite.
      _timeline.invalidateFrom(
        persistMessagePosition(base: _history.basePosition, index: index),
      );
      await _saveChat();
      notifyListeners();
    }
  }

  void _setSessionGenSettingsImpl(ChatGenerationSettings value) {
    _sessionGenSettings = value;
    _saveChat();
    notifyListeners();
  }

  void _setSessionThemeOverridesImpl(ChatThemeOverrides value) {
    _sessionThemeOverrides = value;
    // Persist only when a chat is actually open. The web facade already guards
    // this, but a bare `_currentSessionId!` would crash any other caller that
    // sets the theme with no active session (session close mid-save, tests).
    final sid = _currentSessionId;
    if (sid != null) {
      _db.setThemeOverrides(sid, value.toJsonString());
    }
    notifyListeners();
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

/// Reprocess Needs (body in needs_reprocess.dart) and the group-realism test
/// hooks. Public extension members: no fake overrides them.
extension ChatServiceRealismDoors on ChatService {
  /// Re-evaluate a message's needs deltas under a user critique; see
  /// [NeedsReprocess.manualReprocessNeeds] for [onlyNeeds] scoping.
  Future<bool> manualReprocessNeeds(
    int index,
    String critique, {
    Set<String> onlyNeeds = const <String>{},
  }) => _needsReprocess.manualReprocessNeeds(
    index,
    critique,
    onlyNeeds: onlyNeeds,
  );

  /// Revert a prior manual reprocess on the given message.
  Future<bool> revertNeedsReprocess(int index) =>
      _needsReprocess.revertNeedsReprocess(index);

  /// Test-only: pin the group speaker the same way `_generateResponse` does
  /// ([GroupRealismStore.turnSpeakerId]). Do not assign `_activeCharacter`.
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
  /// not leak this member's Needs / bond into the guest prompt.
  @visibleForTesting
  void debugSeedGroupSpeakerState(
    String charId, {
    Map<String, int>? needs,
    int? longTermTier,
  }) {
    if (needs != null) _groupStore.setNeeds(charId, needs);
    if (longTermTier != null) {
      _groupStore.memberForWrite(charId).longTermTier = longTermTier;
    }
  }
}

/// Pockets & Wardrobe and Growth Rings doors for the sidebar, the web facade
/// and the other parts (bodies in [PocketsLedger] and [GrowthDesk]), plus
/// the Journal / Growth / Pockets builders. Public extension members: no
/// fake overrides them.
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

  ItemCardJournal _buildItemCardJournal() => ItemCardJournal(
    messages: _messages,
    history: _history,
    currentSessionId: () => _currentSessionId,
    journalStore: () => _journalStore,
    db: () => _db,
    time: () => _timeService,
    memorySettings: () => _storageService.memorySettings,
    activeCharacterName: () => _activeCharacter?.name,
  );

  GrowthDesk _buildGrowthDesk() => GrowthDesk(
    messages: _messages,
    macroResolver: _macroResolver,
    store: () => _growthStore,
    review: () => _growthReview,
    service: () => _growthService,
    journalMaintenance: () => _journalMaintenance,
    currentSessionId: () => _currentSessionId,
    activeCharacter: () => _activeCharacter,
    activeGroup: () => _activeGroup,
    groupCharacters: () => _groupCharacters,
    sceneGuestCards: () => _sceneGuest.cards,
    characterIdFor: _getCharacterIdFromCard,
    memorySettings: () => _storageService.memorySettings,
    hasLlm: () => _llmProvider != null,
    isGrowthPassRunning: () => _isGrowthPassRunning,
    awaitHistoryHydrated: _awaitHistoryHydrated,
    setPending: (v) => _pendingRealismMetadata = v,
    notify: notifyListeners,
  );

  TimelineInvalidator _buildTimelineInvalidator() => TimelineInvalidator(
    messages: _messages,
    currentSessionId: () => _currentSessionId,
    summary: () => _summary,
    setSummary: (v) => _summary = v,
    armRecapClear: () => _recapClearArmed = true,
    summaryLastIndex: () => _summaryLastIndex,
    setSummaryLastIndex: (v) => _summaryLastIndex = v,
    journalStore: () => _journalStore,
    journalReview: () => _journalReview,
    journalMaintenance: () => _journalMaintenance,
    growthStore: () => _growthStore,
    growthReview: () => _growthReview,
    growth: () => _growthDesk,
    itemCards: () => _itemCards,
    db: () => _db,
    disposed: () => _disposed,
    notify: notifyListeners,
  );
}
