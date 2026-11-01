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

/// Turn stops and the delete rewinds hygiene tests pin to this file:
/// Continue's entry, the settling yield, [stopGeneration],
/// [cancelRealismEval], and delete's Needs baseline and Pockets rewind.
/// Edit, delete, swipe and the session clears live in the edits door
/// (lib/services/chat/doors/edits/).
extension ChatServiceTurnStops on ChatService {
  /// Abort in-flight post-gen evals so a mutation (regen/continue) can
  /// start. Streaming (`_isGenerating`) and import still refuse — those
  /// are not "I already have the reply and I don't want it scored."
  void _clearPostGenAbortFlags() {
    _postGenAbortRequested = false;
    _isCancellingRealismEval = false;
    _realismEvalCancelled = false;
  }

  Future<bool> _yieldSettlingTurn() async {
    if (_isGenerating || isImporting || _skipAsked) return false;
    if (!_isPostGenerating) {
      // Fast path used to return without touching the flags, so a leftover
      // latch from a prior yield survived into the next regen.
      _clearPostGenAbortFlags();
      return true;
    }
    _postGenAbortRequested = true;
    _isCancellingRealismEval = true;
    _realismEvalCancelled = true;
    _lanes.abortAll();
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (_isPostGenerating && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    // Timeout: post-gen is still running and must keep skipping applies.
    // Success: the next turn starts clean so regen can tick the clock.
    final done = !_isPostGenerating;
    if (done) _clearPostGenAbortFlags();
    return done;
  }

  Future<void> continueGeneration() async {
    if (_session.messages.isEmpty || _sceneGuest.busy) return;
    // Continue KEEPS the reply. Aborting its scoring would leave the first
    // half unbookkept and only score the new fragment. Wait like Send.
    if (_isGenerating || isImporting || _skipAsked) return;
    if (_isPostGenerating) await _waitForTurnToSettle();

    // Only continue if the last message is from a bot (non-user, non-system).
    // Narration banners (dreams, Chance Time) are excluded: continue_ streams
    // straight into _session.messages.last, which would append a chat reply to the
    // banner (the dream-corruption class, 2026-07-28).
    if (!_session.messages.last.isUser &&
        _session.messages.last.sender != 'System' &&
        _session.messages.last.activeMetadata?['is_dream'] != true &&
        _session.messages.last.activeMetadata?['is_chance_time_narration'] !=
            true) {
      await _generateResponse(GenerationMode.continue_);
    }
  }

  void stopGeneration() {
    // Discard before plan consume so the next speaker cannot inherit a
    // Needs catastrophe armed for a turn that never ran. 1:1 evals happen
    // before `_isGenerating`, so this is not gated on that flag.
    _needsSimulation.consumePendingCatastrophe();
    if (_isGenerating) {
      _cancelRequested = true;
      // A waiting reply leaves the line, and nothing of this turn is on the
      // wire to cut. Otherwise abort mouth speech and side-lane evals/clerk.
      if (!_lanes.dropWaitingReplies()) _lanes.abortAll();
    }
  }

  /// Cancel any in-flight generation and wait for it to fully stop.
  Future<void> _cancelAndWaitForGeneration() async {
    _needsSimulation.consumePendingCatastrophe();
    if (!_isGenerating) return;
    _cancelRequested = true;
    _lanes
        .dropWaitingReplies(); // not held up by the pass ahead; nothing is aborted
    // Spin until _generateResponse finishes its cleanup
    while (_isGenerating) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  void _rewindPocketsForDeletedMessage(
    ChatMessage deleted, {
    required bool wasTail,
  }) {
    if (wasTail) {
      _pocketsRewinds.restoreFromStamp(deleted, after: false);
      return;
    }
    unawaited(_itemCards.replant(deleted, key: 'item_cards_retired'));
    if (!pocketsFeatureEnabled) return;
    final before = deleted.metadata?['pockets_before'];
    if (before is! Map) return;
    final speakerId = before['char'];
    if (speakerId is! String || speakerId.isEmpty) return;
    final othersBefore = <String, Pockets>{};
    final rawOthers = before['others'];
    if (rawOthers is List) {
      for (final o in rawOthers) {
        if (o is Map && o['char'] is String) {
          othersBefore[o['char'] as String] = Pockets.fromJson(o['record']);
        }
      }
    }
    final othersAfter = <String, Pockets>{};
    final rawAfter = deleted.activeMetadata?['pockets_after_others'];
    if (rawAfter is List) {
      for (final o in rawAfter) {
        if (o is Map && o['char'] is String) {
          othersAfter[o['char'] as String] = Pockets.fromJson(o['record']);
        }
      }
    }
    final ids = <String>{
      speakerId,
      ...othersBefore.keys,
      ...othersAfter.keys,
      if (_activeGroup != null)
        for (final c in _groupCharacters) _getCharacterIdFromCard(c),
      if (_activeGroup == null && _session.activeCharacter != null)
        _getCharacterIdFromCard(_session.activeCharacter!),
    };
    final live = <String, Pockets>{
      for (final id in ids)
        if (id.isNotEmpty && _pocketsLedger.pocketsWriteAllowed(id))
          id: (pocketsFor(id) ?? Pockets()).copy(),
    };
    invertDeletedPocketTurn(
      speakerId: speakerId,
      speakerBefore: Pockets.fromJson(before['record']),
      speakerAfter: pocketsStamp(deleted.activeMetadata?['pockets_after']),
      othersBefore: othersBefore,
      othersAfter: othersAfter,
      live: live,
    );
    for (final e in live.entries) {
      if (!_pocketsLedger.pocketsWriteAllowed(e.key)) continue;
      setPocketsFor(e.key, e.value);
    }
  }

  /// The deleted speaker's Needs before a delete's restores run, for the
  /// refund the editor settles last (NeedsRewinds.revertForDeletedMessage).
  /// In a group, refund ONLY when the speaker resolved unambiguously —
  /// falling back to the live scalars there would credit whichever member
  /// happens to be loaded, i.e. refund the wrong character. An empty
  /// baseline makes the revert a no-op. Reads the chat's stored switch: this
  /// rewinds state, it does not run Needs.
  Map<String, int> _needsBeforeDelete(String? deletedSid) =>
      (!_needsSimEnabled || (_activeGroup != null && deletedSid == null))
      ? const <String, int>{}
      : (deletedSid != null
            ? Map<String, int>.from(_groupStore.needsOf(deletedSid))
            : Map<String, int>.from(_needsSimulation.vector));

  /// Cancel an in-flight Realism eval or post-gen tick. No-op when idle.
  Future<void> cancelRealismEval() async {
    // Always tear down both lanes first — a fused/clerk call on the
    // worker can still be in flight when the mouth flags look idle.
    _lanes.abortAll();
    _needsSimulation.consumePendingCatastrophe();

    // No-op if there is nothing to cancel. Post-gen clock/wear is
    // cancellable too — a regen abort mid-tick must put the captured
    // clock back and drop the aborted slot's after.
    if (!_isEvaluatingRealism && !_isProcessingGreeting && !_isPostGenerating) {
      debugPrint('[Realism] Cancel request ignored — no active realism eval.');
      return;
    }

    _isCancellingRealismEval = true;
    // Signal to any ongoing realism evaluation that a cancel has been requested.
    _realismEvalCancelled = true;
    _postGenAbortRequested = true;
    notifyListeners();

    // Transient banner only — NEVER a chat message. The old code appended an
    // "evaluation interrupted" line attributed to the character, which then
    // permanently rode chat history, prompts, RAG, and journal windows.
    // Regen holds _isPostGenerating from the first revert through
    // post-gen. Cancel during the pre-reply judges is still a regen:
    // the popped reply is put back. Do not require !_isEvaluatingRealism.
    // No reply: a notice that stays until the chat moves on (not a timer).
    _noteStoppedReply(
      replyKept: _isPostGenerating && !_answeringUnansweredLine,
    );

    debugPrint('[Realism] Realism eval cancel requested');
    _realismEvalStreamText = '';
    _pendingRealismMetadata = null;
    _isEvaluatingRealism = false;
    _isProcessingGreeting = false;
    _isCancellingRealismEval = false;
    // Keep _realismEvalCancelled so sendMessage returns early.
    notifyListeners();
  }
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
        autoChat: entryDoor.autoChat,
        prompts: () => promptAssembler,
      ),
      hooks: _sessionHooks(),
      notify: notifyListeners,
    ),
  );

  /// The session store's hooks; the entry door takes the same ones.
  SessionShellHooks _sessionHooks() => SessionShellHooks(
    characterIdFor: _getCharacterIdFromCard,
    ragCharacterId: _getCharacterId,
    waitForTurnToSettle: () => entryDoor.cover.waitForTurnToSettle(),
    cancelAndWaitForGeneration: _cancelAndWaitForGeneration,
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
    journalStore: () => _journalStore,
    growthDesk: () => _growthDesk,
    sceneGuests: castDoor.guests.state,
    sessions: () => sessionStore,
    graph: () => realism,
    isTurnBusy: () => _isTurnBusy,
    isGenerating: () => _isGenerating,
    invalidateGreetingEval: castDoor.greetings.invalidateGreetingEval,
    characterIdFor: _getCharacterIdFromCard,
    ragCharacterId: _getCharacterId,
    reloadGroupRoster: () => entryDoor.roster.reloadGroupRoster(),
    enterSceneGuestSilently: (guest) =>
        castDoor.guests.enterSceneGuest(guest, speak: false),
    loadActiveObjectives: objectivesDoor.loadActiveObjectives,
    loadSpeakerObjectives: objectivesDoor.loadObjectivesForCurrentSpeaker,
    formatForRagEmbedding: _formatMessagesForRagEmbedding,
    setActiveCharacter: (card) => entryDoor.chat.setActiveCharacter(card),
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
  int get _summaryLastIndex => sessionStore.summaryLastIndex;
  bool get _summaryPaused => sessionStore.summaryPaused;
  set _summaryPaused(bool v) => sessionStore.summaryPaused = v;
  bool get _isSummaryGenerating => sessionStore.isSummaryGenerating;
  set _isSummaryGenerating(bool v) => sessionStore.isSummaryGenerating = v;
  ChatGenerationSettings get _sessionGenSettings => sessionStore.genSettings;
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

/// The model lanes' test surface and the studio wizards' tool check (bodies
/// in [LlmLanes]). Public extension members: no fake overrides them.
extension ChatServiceLlmLanes on ChatService {
  @visibleForTesting
  LLMService get debugMouthLlm => _lanes.mouth;

  @visibleForTesting
  LLMService get debugSideLaneLlm => _lanes.sideLane;

  @visibleForTesting
  String get debugEvalBackendIdentity => _evalBackendIdentity;

  @visibleForTesting
  bool get debugOneShotActive => _oneShotActive;

  @visibleForTesting
  void debugMarkEvalToolsSupported() =>
      _toolProbe.markSupported(_evalBackendIdentity);

  @visibleForTesting
  Future<String?> debugFireSideLaneEval(String prompt) =>
      realism.transport.fireLLMEval(prompt, label: 'test-worker');

  /// The tool-calling verdict for the one model a studio wizard runs on
  /// (see [LlmLanes.toolCheckFor]).
  StudioToolCheck toolCheckFor({
    LLMService? via,
    String remoteModel = '',
    bool autoAsk = true,
  }) =>
      _lanes.toolCheckFor(via: via, remoteModel: remoteModel, autoAsk: autoAsk);

  /// Ask the wizard's model again now (its "Check now").
  Future<void> retestToolsFor({LLMService? via, String remoteModel = ''}) =>
      _lanes.retestToolsFor(via: via, remoteModel: remoteModel);
}
