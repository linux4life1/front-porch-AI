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

/// Bumped by [_invalidateGreetingEval] (selectGreeting, startNewChat,
/// setActiveCharacter, setActiveGroup, loadSession, _loadLastSession,
/// importChatPackage, forkFromMessage) so a
/// late unawaited [_runPostGreetingEval] cannot stomp a later opening.
int _greetingEvalGen = 0;

const Object _kGreetingEvalToken = #_greetingEvalToken;
const Object _kGreetingEvalIndex = #_greetingEvalIndex;

/// Stale when THIS eval's captured token is no longer the live gen.
/// [_invalidateGreetingEval] always bumps [_greetingEvalGen], so a later
/// opening stale-gates the earlier apply without a shared nullable slot.
/// A missing Zone token is not a greeting apply (normal turn evals).
bool _isStaleGreetingEval() {
  final token = Zone.current[_kGreetingEvalToken] as int?;
  if (token == null) return false;
  return token != _greetingEvalGen;
}

/// Set when [_runPostGreetingEval] passes its guards (not skipped solely
/// because [_session.activeCharacter] is null). Tests prove group unauthored alts
/// reach the eval path.
@visibleForTesting
bool testPostGreetingEvalEntered = false;

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
      snapshotIndex: _consecutiveAutoResponses,
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
      groupRepository: () => _groupChatRepository,
      imageGen: () => _imageGenService,
      graph: () => realism,
      realism: () => realism.scope,
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
      prompts: () => promptAssembler,
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
    waitForTurnToSettle: () => entryDoor.cover.waitForTurnToSettle(),
    deleteMessage: deleteMessage,
    embedFor: (id) => _maybeEmbedMessages(characterIdOverride: id),
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
    greetingEvalGen: () => _greetingEvalGen,
    bumpGreetingEvalGen: () => _greetingEvalGen++,
    greetingZone: (token, index) => {
      _kGreetingEvalToken: token,
      _kGreetingEvalIndex: index,
    },
    markPostGreetingEvalEntered: () => testPostGreetingEvalEntered = true,
    cancelRealismEval: cancelRealismEval,
    selectGreeting: selectGreeting,
    openingAllGreetings: () => openingAllGreetings,
    resolvedOpeningGreetings: _resolvedOpeningGreetings,
    guestDirector: _ensureSceneGuestDirector,
    mintLlm: () => testLlmServiceOverride ?? _llmProvider?.activeService,
    stageIdleTurn: _stageIdleTurn,
  );
}

/// The cast door's state and behaviour under the names the rest of this
/// library still uses. Each line is debt its caller's package retires by
/// calling [ChatService.castDoor] itself (WP5, WP7 to WP10).
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
  int get _greetingIndex => castDoor.greetings.greetingIndex;
  bool get _isProcessingGreeting => castDoor.baseline.isProcessingGreeting;
  set _isProcessingGreeting(bool v) =>
      castDoor.baseline.isProcessingGreeting = v;
  set _pendingIdleCue(String? v) => castDoor.idle.pendingIdleCue = v;
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
