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

/// The shell's half of a Dynamic Responses ("AFK") idle turn: the clock's
/// away pace, the speaker pick and their bars as the chip's baseline, and
/// the cue built for that speaker. The timer, its guards and the turn
/// dispatch are [IdleAutonomy] (doors/cast/idle_autonomy.dart). This part
/// stays because test/services/chat/afk_cue_speaker_test.dart reads it to
/// prove the cue is built from the picked speaker.
extension ChatServiceIdleAutonomous on ChatService {
  /// Called by [IdleAutonomy] once its readiness guards pass.
  ({CharacterCard? speaker, String cue}) _stageIdleTurn() {
    // Advance narrative time by the user-set away pace (Living Time: 1 =
    // a few hours, 3 = half the day, 6 = a full day). Deterministic — the
    // model never chooses the span. Day crossings fire dreams and fresh
    // weather exactly as in-play advancement does.
    // Needs are NOT decayed automatically during AFK — the evaluator is the
    // sole source of need changes, so the character isn't stuck firefighting
    // survival needs and has room for varied activities.
    // AFK advance is deterministic (the user's own away pace, no model call),
    // so it follows the clock's driver rather than the engine specifically.
    if (_clockRunning) {
      _timeService.advanceTimePeriods(
        _storageService.generationSettings.dynamicResponsePacePeriods,
      );
    }

    // Group: pick the speaker at the new clock, load THAT member's
    // needs, then stamp the chip baseline. The scalar vector is whoever
    // last spoke — stamping it first made AFK chips subtract the wrong
    // member. Pass forceSpeaker so generate cannot pick a second time.
    CharacterCard? afkSpeaker;
    if (_activeGroup != null) {
      afkSpeaker = _pickPresentGroupSpeaker();
      final sid = _getCharacterIdFromCard(afkSpeaker);
      if (sid.isNotEmpty) _realismDance.loadIntoScalars(sid);
    }

    // Capture pre-AFK needs vector so the needs delta chip has a baseline.
    // Soft group speakers skip Needs — do not park a leftover vector.
    if (_needsPass.active &&
        _needsSimulation.vector.isNotEmpty &&
        (afkSpeaker == null || !_speakerIsSoft(afkSpeaker))) {
      _pendingRealismMetadata ??= {};
      _pendingRealismMetadata!['needs_pre_turn_vector'] = Map<String, int>.from(
        _needsSimulation.vector,
      );
    }

    return (speaker: afkSpeaker, cue: _buildAutonomousCue(afkSpeaker));
  }

  String _buildAutonomousCue(CharacterCard? speaker) {
    final who = AfkCueSpeaker.resolve(
      picked: speaker,
      host: _session.activeCharacter,
    );
    final charName = who.name;
    // Ambitions give off-screen time direction (Living Time §6): a character
    // with a long-term end sometimes spends AFK moments working toward it
    // instead of only meals-and-naps. Optional flavor, never a demand.
    final ambitions = who.ambitions;
    final ambitionStr = ambitions.isEmpty
        ? ''
        : '\n\nIf it fits naturally, part of this time may go toward '
              '$charName\'s long-term ambition: ${ambitions.first}.';
    // Living Time flavor (afk_flavor.dart): 1–2 deterministic directives so
    // the snapshot USES the hour, the weather, the fixation, and the diary
    // already present in the prompt — plus montage guidance when the away
    // pace spans more than a couple of hours.
    final pace = _storageService.generationSettings.dynamicResponsePacePeriods;
    final flavorLines = AfkFlavor.directives(
      timeOfDay: _timeService.timeOfDay,
      weather: currentWeather,
      fixation: _relationshipService.activeFixation,
      snapshotIndex: castDoor.idle.consecutiveAutoResponses,
    );
    final span = AfkFlavor.spanDirective(pace);
    final flavorStr =
        '\n\n${[...flavorLines, if (span.isNotEmpty) span].join('\n')}';
    // Only announce elapsed time when the clock actually moved this cycle. Time
    // advances iff the clock has a driver (the guard in _onIdleTimerFired) AND
    // passage of time is enabled (the guard inside advanceTimePeriods) — both
    // of which _clockRunning states directly. If we announced "a few hours have
    // passed" while Passage of Time was off, the cue would contradict the
    // unchanging time on every AFK turn.
    final timeAdvancing = _clockRunning;
    final timeStr = timeAdvancing
        ? '${_timeService.timeOfDay} (Day ${_timeService.dayCount})'
        : '';

    if (!_needsPass.active || _needsSimulation.vector.isEmpty) {
      final preamble = timeAdvancing
          ? '*${AfkFlavor.timePhrase(pace)} It is now $timeStr.\n\n'
          : '*A while has passed.\n\n';
      return '$preamble'
          'Describe a quiet snapshot from part of $charName\'s day '
          '— something they have been doing, a moment of rest, '
          'a personal routine. Reference what they have been up to '
          'naturally, so the scene feels like part of a lived-in day.'
          '$flavorStr$ambitionStr\n\n'
          'Write ONLY narrative action and internal thought — '
          'NO dialogue, do NOT address or refer to the user, '
          'do NOT have $charName notice the user. '
          'This is a solitary scene observed from outside the chat.*';
    }

    // Full autonomous cue with needs data — words only, like every other
    // generation-facing surface (spec §5d): a raw "(41/100)" here was the
    // last place a meter could leak into prose ("my hunger at 41…").
    final lowNeeds = _needsSimulation.getLowNeedsForInjection(
      _needsSimulation.vector,
      enjoysLowHygieneOverride: who.enjoysLowHygiene,
    );
    String needsStr = '';
    if (lowNeeds.isNotEmpty) {
      needsStr = lowNeeds
          .map((n) {
            final desc = switch (n.effectiveStep) {
              0 || 1 => 'urgently pressing',
              2 => 'weighing heavily',
              3 => 'noticeably felt',
              _ => 'starting to stir',
            };
            return '${n.key} is $desc';
          })
          .join(', ');
    }

    final preamble = timeAdvancing
        ? '*${AfkFlavor.timePhrase(pace)} It is now $timeStr.\n\n'
        : '*A while has passed.\n\n';
    return '$preamble'
        'While you were away, $charName has been going about their day '
        '— handling meals, rest, and personal needs as life went on.'
        '${needsStr.isNotEmpty ? "\n\n$charName\'s current state — $needsStr." : ""}\n\n'
        'Describe a quiet snapshot from $charName\'s day, touching on '
        'some of what they have been up to (a meal, bathroom, rest, bath, '
        'or similar daily routines) so the scene feels like part of a '
        'lived-in day.'
        '$flavorStr$ambitionStr\n\n'
        'IMPORTANT: Write ONLY narrative action and internal thought — '
        'NO dialogue, do NOT address or refer to the user, '
        'do NOT have $charName notice the user. '
        'This is a solitary scene observed from outside the chat.*';
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
    groupSpeakerSkips: _groupSpeakerSkips,
    setNextCharacter: setNextCharacter,
    nextCharacter: () => entryDoor.director.nextCharacter,
    pickPresentSpeaker: _pickPresentGroupSpeaker,
    workFieldsFor: _workFieldsFor,
    memberInScene: _memberInScene,
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
    stageIdleTurn: _stageIdleTurn,
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

  /// The entry door. Each hook is debt (see [EntryShellHooks]); the
  /// shared hooks are the session store's own ([_sessionHooks]).
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
        sceneMoves: realism.places.sceneMoves,
      ),
      hooks: EntryShellHooks(
        skipAsked: () => _skipAsked,
        upcomingSpeaker: () => _upcomingGroupSpeaker,
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
