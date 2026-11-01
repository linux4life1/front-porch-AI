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

/// Bumped on regen / settling abort so a fire-and-forget Journal or Growth
/// pass started against the rejected window cannot apply (or fall through
/// to XML) after abortGeneration tore the tools call down.
int _memoryPassEpoch = 0;

/// The regen pieces hygiene tests pin to this file: 1:1 regen's decay and
/// judge replay (trust_repair_regen_latch_test reads the shared dispatch
/// here). The regen itself is the edits door's RegenController
/// (lib/services/chat/doors/edits/); [_buildEditsDoor] wires it.
extension ChatServiceRegenReplay on ChatService {
  /// Which cast member said [msg]. See [resolveGroupSpeakerForMessage].
  CharacterCard? _resolveGroupSpeakerForMessage(ChatMessage msg) =>
      resolveGroupSpeakerForMessage(_groupCharacters, msg);

  /// 1:1 regen: replay decay + the realism eval for the popped reply's user
  /// line, from the baseline the revert restored. Groups replay inside the
  /// generation via the per-speaker dance. False when the user cancelled:
  /// the popped reply is then back, with the state it was accepted under.
  Future<bool> _replayRegenJudges(ChatMessage lastMsg) async {
    // Set UI streaming state
    _isEvaluatingRealism = true;
    _realismEvalStreamText = '';
    notifyListeners();

    void handleChunk(String chunk) {
      _realismEvalStreamText += chunk;
      // Debounce: coalesce rapid token arrivals into one rebuild per 150 ms
      _evalChunkTimer?.cancel();
      _evalChunkTimer = Timer(const Duration(milliseconds: 150), () {
        try {
          notifyListeners();
        } catch (_) {
          // Widget was deactivated — timer fired after navigation
        }
      });
    }

    // Record the (restored) needs baseline as the pre-turn vector BEFORE
    // the decay tick below — sendMessage stamps pre-tick and the group
    // dance stamps preDecay, so a regen's chips must count the decay the
    // same way or they understate the turn by exactly the decay component
    // (and deleting the regenerated reply under-refunds by it — caught by
    // regen_chip_attach_test: the original showed a hygiene chip, the
    // regen didn't).
    if (_needsPass.active && _needsSimulation.vector.isNotEmpty) {
      _pendingRealismMetadata ??= {};
      _pendingRealismMetadata!['needs_pre_turn_vector'] = Map<String, int>.from(
        _needsSimulation.vector,
      );
      _pendingRealismMetadata![kNeedsPreTurnCarry] = Map<String, double>.from(
        _needsSimulation.wearCarry,
      );
    }

    // Wear waits until the clock commits on the replayed reply.
    _applyMoodDecay();
    _afterglow.tickPerReply();

    await _realismJudges.runPreGenJudges(
      onChunk: handleChunk,
      logSpeakerName: _session.activeCharacter?.name,
    );

    // Check for cancellation after evals complete
    if (_realismEvalCancelled) {
      debugPrint('[Realism] Evaluation cancelled during regenerate, aborting');
      // Put the popped reply back BEFORE bailing. The regen removed it at
      // the top so the outbound prompt wouldn't contain it, and
      // _generateResponse — the thing that appends the replacement — is
      // still below us. Returning without this destroys the message and
      // every swipe it carried. It is the same hazard the backend gate
      // further up already guards ("aborting after removeLast would drop
      // the popped reply"); the cancel path just never learned it.
      //
      // Putting the TEXT back is only half of it. Everything above already
      // un-applied the accepted turn — bond/trust/arousal reverted, needs
      // restored from needs_pre_turn_vector, the baseline pulled from the
      // PREVIOUS accepted message, the stance rewound, pockets rolled to
      // the pre-turn record — and then charged a fresh decay tick. Bailing
      // here without the same restore the two success paths run (see
      // `if (regenGuest == null) _restoreRealismStateForSpeaker(lastMsg)`
      // below) left the message displaying chips the sidebar and the
      // session row no longer agreed with, and `_saveChat()` persisted the
      // wrong scalars. 1:1-only branch, host-only (guests never get here).
      _session.messages.add(lastMsg);
      _clockReader.applyTipClock();
      _restoreRealismStateForSpeaker(lastMsg);
      _pocketsRewinds.restoreFromStamp(lastMsg, after: true);
      _pendingRealismMetadata = null;
      _realismEvalCancelled = false;
      _evalChunkTimer?.cancel();
      _evalChunkTimer = null;
      _isEvaluatingRealism = false;
      notifyListeners();
      await _saveChat();
      return false;
    }

    // Cancel any pending debounce notify before closing the overlay
    _evalChunkTimer?.cancel();
    _evalChunkTimer = null;
    _isEvaluatingRealism = false;
    notifyListeners();
    return true;
  }

  /// The opening greets as the bubble shows them (body in the edits door's
  /// SwipeVariants); the greeting seed restores the picked index from it.
  List<String> _resolvedOpeningGreetings() =>
      editsDoor.swipes.resolvedOpeningGreetings();

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
          history: () => _history,
          macroResolver: () => promptAssembler.macros,
          objectives: () => objectivesDoor,
          media: () => mediaDoor,
          lanes: _lanes,
        ),
        characterIdFor: _getCharacterIdFromCard,
        saveChat: _saveChat,
        notify: notifyListeners,
        turn: EditTurnHooks(
          isTurnBusy: () => _isTurnBusy,
          setPostGenerating: (on) => _isPostGenerating = on,
          yieldSettlingTurn: _yieldSettlingTurn,
          clearPostGenAbortFlags: _clearPostGenAbortFlags,
          abortIfBackendDown: _abortIfBackendDown,
          generate: _generateResponse,
          answerTrailingUserLine: _generateFromTrailingUserTurn,
          bumpMemoryEpoch: () => _memoryPassEpoch++,
          setGenerating: (on) => _isGenerating = on,
          setPhase: (phase) => _generationPhase = phase,
          cancelRequested: () => _cancelRequested,
          setCancelRequested: (on) => _cancelRequested = on,
        ),
        realism: EditRealismHooks(
          rewindToLastAcceptedReply: _rewindRelationshipToLastAcceptedReply,
          restoreScoredRegisters: _restoreScoredRegisters,
          replayRegenJudges: _replayRegenJudges,
          needsBeforeDelete: _needsBeforeDelete,
          rewindPocketsForDelete: _rewindPocketsForDeletedMessage,
        ),
        cast: EditCastHooks(
          guestBusy: () => _sceneGuest.busy,
          isGuestAuthored: _isGuestAuthoredMessage,
          guestFor: _sceneGuestForMessage,
          setStatus: (text, {isError = false}) =>
              _setGuestStatus(text, isError: isError),
          guestChimeIns: _maybeRunSceneGuestChimeIns,
          pickPresentSpeaker: _pickPresentGroupSpeaker,
          greetingIndex: () => _greetingIndex,
          setGreetingIndex: (index) => _greetingIndex = index,
          greetingOwner: _greetingOwnerCard,
          firstMessage: _buildFirstMessage,
          invalidateGreetingEval: () async {
            await _invalidateGreetingEval();
            testPostGreetingEvalEntered = false;
          },
          stampGreetingIndex: _stampGreetingIndex,
          isOpeningGreetingChat: () => _isOpeningGreetingChat,
          seedGroupGreeting: _applyGroupCustomGreetingSeed,
          seedGreeting: _applyGreetingOpeningSeed,
        ),
        sessions: () => sessionStore,
        prompts: () => promptAssembler,
      ),
    );
    _forwardDoorNotify(door);
    return door;
  }
}

/// Builds the Realism graph, the controls door, the model lanes and the
/// prompt assembler. Each hook stands in for a member of another part until
/// that part becomes a door (see [RealismShellHooks], [ControlsShellHooks]
/// and [PromptShellHooks]).
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
      ),
      hooks: RealismShellHooks(
        characterIdFor: _getCharacterIdFromCard,
        ragCharacterId: _getCharacterId,
        disposed: () => _disposed,
        staleGreetingEval: _isStaleGreetingEval,
        memoryPassEpoch: () => _memoryPassEpoch,
        isGenerating: () => _isGenerating,
        isTurnBusy: () => _isTurnBusy,
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
      saveChat: _saveChat,
      notify: notifyListeners,
      hooks: ControlsShellHooks(
        disposed: () => _disposed,
        characterIdFor: _getCharacterIdFromCard,
        isTurnBusy: () => _isTurnBusy,
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
    isGenerating: () => _isGenerating,
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
      ),
      hooks: PromptShellHooks(
        characterIdFor: _getCharacterIdFromCard,
        ragCharacterId: _getCharacterId,
        cancelRequested: () => _cancelRequested,
        enterPrefill: _enterPrefill,
      ),
      notify: notifyListeners,
    ),
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
        proposal: () => _objectiveProposal,
        mood: () => _mood,
        journal: () => _journalStore,
        time: () => _timeService,
        maxSecondaryObjectives: kMaxSecondaryObjectives,
        hooks: ObjectiveShellHooks(
          objectivesActive: () => objectivesActive,
          nextSpeaker: () => entryDoor.director.nextCharacter,
          hasChatModel: () => _llmProvider != null,
          pendingMetadata: () => _pendingRealismMetadata ??= {},
          historyBase: () => _history.basePosition,
          realismActiveThisMode: () => _realismActiveThisMode,
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
        snapshot: () => _realismSnapshot,
        mood: () => _mood,
        chaos: () => _chaosModeService,
        needsPass: () => _needsPass,
        expression: () => _expressionService,
        lorebook: () => _lorebookScanner,
        clockWriter: () => _clockWriter,
        growthDesk: () => _growthDesk,
        birthdays: () => _birthdaySync,
        cast: () => castDoor,
        objectives: () => objectivesDoor,
        media: () => mediaDoor,
        sceneMoves: _sceneMoves,
      ),
      hooks: EntryShellHooks(
        isTurnBusy: () => _isTurnBusy,
        bumpGenerationEpoch: () => _generationEpoch++,
        generate: () => _generateResponse(GenerationMode.normal),
        skipAsked: () => _skipAsked,
        upcomingSpeaker: () => _upcomingGroupSpeaker,
      ),
      shared: _sessionHooks(),
      notify: notifyListeners,
    ),
  );
}
