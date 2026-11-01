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

/// Turn-progression surfaces that sit outside the [ChatServiceSend] spine:
/// group speaker picking, the web/mobile Chance Time reveal surface and the
/// Journal recap controls. TTS-paced auto-play, background RAG embedding and
/// the periodic cast scan run after a reply, on the turn engine
/// (doors/turn/). Extracted verbatim from `chat_service.dart` — zero
/// behaviour change.
extension ChatServiceTurnFlow on ChatService {
  /// Trigger the next character to speak in group mode.
  Future<void> triggerNextCharacter() async {
    if (_activeGroup == null || _groupCharacters.isEmpty || _isTurnBusy) {
      return;
    }
    // Bucket brigade: this speaker announces the time the last reply
    // decided, then post-decides for whoever speaks next.
    await turnEngine.generate(GenerationMode.normal);
  }

  /// Manually select which character speaks next in group mode.
  /// Delegated to GroupTurnManager.
  void setNextCharacter(CharacterCard character) {
    _session.groupManager?.setNextSpeaker(character);
    notifyListeners(); // ensure UI updates even if manager didn't notify

    // In group mode, switch the active objectives to this character's personal ones.
    if (_activeGroup != null) {
      objectivesDoor.loadObjectivesForCurrentSpeaker();
    }
  }

  /// Pick which character speaks next based on turn order.
  /// A _forcedNextSpeakerId (set by manual user choice) is consumed first
  /// and works for both TurnOrder.random and roundRobin. After consumption
  /// we resume normal cycling / random behavior.
  CharacterCard _pickNextGroupCharacter() {
    if (_session.groupManager == null) {
      throw StateError('No active group');
    }
    return _session.groupManager!.pickNextSpeaker();
  }

  /// At work (and Away when we know they are not in scene). 1:1 never skips.
  bool _groupSpeakerSkips(CharacterCard card) {
    if (_activeGroup == null) return false;
    final work = _workFieldsFor(card);
    final where = derivePresence(
      occupation: work.occupation,
      hours: work.hours,
      clockMinutes: _timeService.clockMinutes,
      weekday: _timeService.clock.weekday,
      workDays: work.workDays,
      inScene: _memberInScene(card),
    );
    return groupTurnSkips(where);
  }

  /// Next member who is With you. A forced @name is not swapped. Random
  /// turn order must not re-roll the same At-work member and miss the
  /// only free one — walk the roster once.
  CharacterCard _pickPresentGroupSpeaker() {
    // Forced / @ of a present member wins over a quiet Away return.
    // Serving pendingReturnSpeakId first stole @Bea when Ana flipped.
    final forced = _session.groupManager?.hasForcedSpeaker ?? false;
    if (forced) {
      return _pickNextGroupCharacter();
    }
    final returnId = _awayPulse.pendingReturnSpeakId;
    if (returnId != null) {
      for (final card in _groupCharacters) {
        if (_getCharacterIdFromCard(card) == returnId) {
          _awayPulse.consumingReturnSpeak = true;
          _session.groupManager?.advanceAfterRegeneration(card);
          return card;
        }
      }
    }
    final first = _pickNextGroupCharacter();
    final present = _presentFrom(first);
    if (present == null || identical(present, first)) return first;
    _session.groupManager?.advanceAfterRegeneration(present);
    return present;
  }

  /// Who [_pickPresentGroupSpeaker] will pick, without taking the turn.
  /// The Next tooltip, sidebar badge and web cast chip read this, so they
  /// name the member who actually speaks.
  CharacterCard? get _upcomingGroupSpeaker {
    final manager = _session.groupManager;
    if (manager == null || !manager.isActive) return null;
    final head = manager.nextSpeaker;
    if (manager.hasForcedSpeaker) return head;
    final returnId = _awayPulse.pendingReturnSpeakId;
    if (returnId != null) {
      for (final card in _groupCharacters) {
        if (_getCharacterIdFromCard(card) == returnId) return card;
      }
    }
    if (head == null) return null;
    return _presentFrom(head) ?? head;
  }

  /// First member With you walking the rotation from [head]: the member
  /// after a skipped one, not the roster's first (that parked the rotation
  /// on the skipped member and starved everyone behind them). Null when
  /// the whole roster skips.
  CharacterCard? _presentFrom(CharacterCard head) {
    final cast = _groupCharacters;
    final start = cast.indexWhere((c) => identical(c, head));
    if (start < 0) return _groupSpeakerSkips(head) ? null : head;
    for (var i = 0; i < cast.length; i++) {
      final card = cast[(start + i) % cast.length];
      if (!_groupSpeakerSkips(card)) return card;
    }
    return null;
  }

  String _presenceSkipBanner(CharacterCard card) {
    final work = _workFieldsFor(card);
    final where = derivePresence(
      occupation: work.occupation,
      hours: work.hours,
      clockMinutes: _timeService.clockMinutes,
      weekday: _timeService.clock.weekday,
      workDays: work.workDays,
      inScene: _memberInScene(card),
    );
    if (where == PresenceWhere.atWork) {
      final range = parseWorkHoursRange(work.hours);
      final until = range == null
          ? ''
          : ' until ${StoryClock.formatClock(DateTime.utc(2000, 1, 1, range.$2 ~/ 60, range.$2 % 60))}';
      final job = work.occupation.trim();
      return '${card.name} is at work${job.isEmpty ? '' : ' as a $job'}$until.';
    }
    return '${card.name} is away.';
  }

  ({
    String occupation,
    String hours,
    String occupationBrief,
    List<int>? workDays,
  })
  _workFieldsFor(CharacterCard card) => workFieldsForMember(
    card,
    _characterRepository?.characters ?? const <CharacterCard>[],
  );

  /// Skip path only. 1:1 never skips (caller returns false first).
  /// Group: judge bit, else recent line, or stance that does not say they left.
  bool _memberInScene(CharacterCard card) {
    if (_activeGroup == null) return true;
    final id = _getCharacterIdFromCard(card);
    final judged = _groupRealism[id]?.withUser;
    if (judged != null) return judged;
    var seen = 0;
    for (final m in _session.messages.reversed) {
      if (m.isUser) continue;
      if (m.sender == card.name) return true;
      if (++seen >= 8) break;
    }
    final stance = _groupRealism[id]?.spatialStance ?? '';
    return !stanceSaysAway(stance);
  }

  /// True when auto-trigger fires. UI reads then calls consumeChanceTimeTrigger().
  bool get chanceTimePendingTrigger => _chance.pendingTrigger;

  /// True when a chaos event is queued for the next response (blocks manual spin + auto-trigger).
  bool get hasPendingChaosEvent => _chaosModeService.hasPendingChaosEvent;

  /// Called by the overlay once it has opened. Clears the auto-trigger flag.
  void consumeChanceTimeTrigger() => _chance.pendingTrigger = false;

  // ── Web/mobile Chance Time surface ──────────────────────────────────────
  // The desktop pops its wheel from the one-shot [chanceTimePendingTrigger] via
  // a ChangeNotifier. Web clients (which drive the same shared ChatService over
  // HTTP/WS) have no such hook and no spinning wheel, so they observe the park
  // through these accessors and resolve it with [acceptPendingChanceTime]. All
  // of this is UI-coordination glue for the completer above — the simulation is
  // untouched, so 1:1/group parity is unaffected.

  /// True from the moment a Chance Time parks [sendMessage] until it is
  /// accepted. The durable signal the web surface uses to show — and, after a
  /// phone wakes and reconnects, re-show — the reveal modal.
  bool get isAwaitingChanceTime =>
      _chance.webEvent != null ||
      (_chance.completer != null && !_chance.completer!.isCompleted);

  /// Manual SPIN NOW. Parks a pre-picked event until accept. No-op when
  /// chaos is off, an event is already queued, or a park is already live.
  bool requestManualChanceTime() {
    if (!_chaosModeService.chaosModeEnabled) return false;
    if (_chaosModeService.hasPendingChaosEvent) return false;
    if (_chance.webEvent != null) return false;
    final wheel = spinWheelEvents();
    if (wheel.isEmpty) return false;
    _chance.webEvent = wheel.first;
    _chance.webName = chanceTimeSpeakerName;
    notifyListeners();
    return true;
  }

  /// The speaker a Chance Time event is attributed to: the upcoming group
  /// speaker (a spin picks one ahead in random turn order), else the 1:1 host.
  /// Shared by the desktop wheel overlay and the web accept path so both
  /// attribute the event identically.
  String get chanceTimeSpeakerName =>
      nextCharacter?.name ?? activeCharacter?.name ?? 'Character';

  /// The pre-picked pending event with its placeholders resolved, for the web reveal
  /// modal. Null when nothing is parked.
  String? get webChanceTimeDisplay => _chance.webEvent == null
      ? null
      : resolveChanceTimeEvent(
          _chance.webEvent!,
          _chance.webName ?? chanceTimeSpeakerName,
        );

  /// Web/mobile "Accept Your Fate": applies the pre-picked pending event using
  /// the same attribution the desktop wheel uses, then lets generation resume.
  /// No-op if nothing is parked (e.g. the desktop already accepted).
  Future<void> acceptPendingChanceTime() async {
    final raw = _chance.webEvent;
    if (raw == null) return;
    // The name the reveal showed, even if a turn has passed since the spin.
    await applyChanceTimeResult(raw, _chance.webName ?? chanceTimeSpeakerName);
  }

  // ── The Journal recap ("Where we are") ──────────────────────────────
  // The recap reuses the _summary scalar + Sessions.summary persistence the
  // old summary system used, so the public surface below (sidebar, web
  // facade, the growth pass's getRecap cb) is unchanged. The generator is
  // the Journal maintenance pass (journal_maintenance leaf), which also
  // produces the per-character memory cards in the same LLM call.

  /// Manually set the recap text.
  void setSummary(String text) {
    _rememberRecapEdit(text);
    final id = _session.currentSessionId;
    if (id != null) {
      unawaited(_journalStore.persistRecap(id, text));
    }
    _saveChat();
    notifyListeners();
  }

  /// Pause or resume the automatic Journal maintenance pass.
  void setSummaryPaused(bool paused) {
    _summaryPaused = paused;
    notifyListeners();
  }

  /// Force an immediate Journal maintenance pass (cards + recap), bypassing
  /// the interval. Backs the sidebar/web "Regenerate" button (name kept for
  /// the existing public surface).
  Future<void> forceSummaryUpdate() async {
    if (_isSummaryGenerating) return;
    await _awaitHistoryHydrated();
    await realism.journalMaintenance.runMaintenancePass(force: true);
  }
}

/// Builds the Realism graph, the controls door, the model lanes, the prompt
/// assembler and the turn engine. Each hook stands in for a member of
/// another part until that part becomes a door (see [RealismShellHooks],
/// [ControlsShellHooks], [PromptShellHooks] and [TurnShellHooks]).
extension ChatServiceRealismWiring on ChatService {
  RealismGraph _buildRealismGraph() => RealismGraph(
    RealismDeps(
      session: _session,
      services: RealismServices(
        db: () => _db,
        storage: _storageService,
        personas: _userPersonaService,
        worlds: _worldRepository,
        macros: promptAssembler.macros,
        kobold: _koboldService,
        characters: () => _characterRepository,
        memory: () => _memoryService,
        llmProvider: () => _llmProvider,
        maxSecondaryObjectives: kMaxSecondaryObjectives,
        evalStagger: kEvalDispatchStagger,
        lanes: _lanes,
      ),
      doors: RealismDoors(
        cast: () => castDoor,
        entry: () => entryDoor,
        edits: () => editsDoor,
        objectives: () => objectivesDoor,
        sessions: () => sessionStore,
        controls: () => controlsDoor,
        prompts: () => promptAssembler,
        turn: () => turnEngine,
      ),
      hooks: RealismShellHooks(
        characterIdFor: _getCharacterIdFromCard,
        ragCharacterId: _getCharacterId,
        disposed: () => _disposed,
        stampGroupUserTurnBaseline: _stampGroupUserTurnBaseline,
      ),
      notify: notifyListeners,
    ),
  );

  ControlsDoor _buildControlsDoor() => ControlsDoor(
    ControlsDeps(
      session: _session,
      storage: _storageService,
      personas: _userPersonaService,
      db: () => _db,
      characters: () => _characterRepository,
      graph: () => realism,
      cast: () => castDoor,
      lanes: _lanes,
      turn: this,
      engine: () => turnEngine,
      saveChat: _saveChat,
      notify: notifyListeners,
      hooks: ControlsShellHooks(
        disposed: () => _disposed,
        characterIdFor: _getCharacterIdFromCard,
        exitCallModelSwap: () => promptAssembler.callSwap.exit(),
        upcomingSpeaker: () => _upcomingGroupSpeaker,
        speakerName: () => chanceTimeSpeakerName,
      ),
    ),
  );

  LlmLanes _buildLanes() => LlmLanes(
    kobold: () => _koboldService,
    provider: () => _llmProvider,
    testMouth: () => testLlmServiceOverride,
    testWorker: () => testWorkerLlmServiceOverride,
    testIsLocal: () => testIsLocalOverride,
    isGenerating: () => turnEngine.progress.isGenerating,
    transport: () => realism.transport,
    notify: notifyListeners,
  );

  /// The prompt assembler. Each hook is debt (see [PromptShellHooks]).
  PromptAssembler _buildPromptAssembler() => PromptAssembler(
    PromptDeps(
      session: _session,
      services: PromptServices(
        db: () => _db,
        storage: _storageService,
        personas: _userPersonaService,
        worlds: _worldRepository,
        kobold: _koboldService,
        characters: () => _characterRepository,
        llmProvider: () => _llmProvider,
        memory: () => _memoryService,
        lanes: _lanes,
      ),
      doors: PromptDoors(
        graph: () => realism,
        controls: () => controlsDoor,
        sessions: () => sessionStore,
        media: () => mediaDoor,
        cast: () => castDoor,
        entry: () => entryDoor,
        edits: () => editsDoor,
        turn: () => turnEngine,
      ),
      hooks: PromptShellHooks(
        characterIdFor: _getCharacterIdFromCard,
        ragCharacterId: _getCharacterId,
      ),
      notify: notifyListeners,
    ),
  );

  /// The turn engine. Each hook is debt (see [TurnShellHooks]).
  TurnEngine _buildTurnEngine() => TurnEngine(
    TurnDeps(
      session: _session,
      services: TurnServices(
        storage: _storageService,
        personas: _userPersonaService,
        kobold: _koboldService,
        llmProvider: () => _llmProvider,
        tts: () => _ttsService,
        memory: () => _memoryService,
        lanes: _lanes,
      ),
      doors: TurnDoors(
        graph: () => realism,
        prompts: () => promptAssembler,
        controls: () => controlsDoor,
        sessions: () => sessionStore,
        cast: () => castDoor,
        entry: () => entryDoor,
        objectives: () => objectivesDoor,
        media: () => mediaDoor,
        importer: () => chatImporter,
      ),
      characterIdFor: _getCharacterIdFromCard,
      ragCharacterId: _getCharacterId,
      hooks: TurnShellHooks(
        skipAsked: () => _skipAsked,
        pickPresentSpeaker: _pickPresentGroupSpeaker,
        groupSpeakerSkips: _groupSpeakerSkips,
        presenceSkipBanner: _presenceSkipBanner,
      ),
      notify: notifyListeners,
    ),
  );
}
