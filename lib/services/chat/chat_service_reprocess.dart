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
          realismScope: _realismScope,
          history: () => _history,
          timeline: () => _timeline,
          clockReader: () => _clockReader,
          clockWriter: () => _clockWriter,
          needsRewinds: () => _needsRewinds,
          needsReprocess: () => _needsReprocess,
          pocketsRewinds: () => _pocketsRewinds,
          itemCards: () => _itemCards,
          afterglow: () => _afterglow,
          realismDance: () => _realismDance,
          realismJudges: () => _realismJudges,
          realismSnapshot: () => _realismSnapshot,
          mood: () => _mood,
          expression: () => _expressionService,
          lorebookInjector: () => _lorebookInjector,
          growthDesk: () => _growthDesk,
          macroResolver: () => _macroResolver,
          objectives: () => objectivesDoor,
          media: () => mediaDoor,
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
          mouthIsLocal: () => _mouthIsLocal,
          setGenerating: (on) => _isGenerating = on,
          setPhase: (phase) => _generationPhase = phase,
          cancelRequested: () => _cancelRequested,
          setCancelRequested: (on) => _cancelRequested = on,
          mouthStream: _mouthGenerateStream,
          withWorkerLane: (work) => _withWorkerLane(work),
          mouthIdle: () => _llmProvider?.koboldService.waitForIdle(),
        ),
        realism: EditRealismHooks(
          realismActiveThisMode: () => _realismActiveThisMode,
          evalCancelled: () => _realismEvalCancelled,
          setEvalCancelled: (on) => _realismEvalCancelled = on,
          setEvaluatingRealism: (on) => _isEvaluatingRealism = on,
          clearEvalStream: () => _realismEvalStreamText = '',
          onEvalChunk: (chunk) {
            _realismEvalStreamText += chunk;
            _evalChunkTimer?.cancel();
            _evalChunkTimer = Timer(const Duration(milliseconds: 150), () {
              try {
                notifyListeners();
              } catch (_) {}
            });
          },
          stopEvalChunkTimer: () {
            _evalChunkTimer?.cancel();
            _evalChunkTimer = null;
          },
          restoreForSpeaker: _restoreRealismStateForSpeaker,
          keepingLiveSpeaker: _keepingLiveSpeaker,
          rewindToLastAcceptedReply: _rewindRelationshipToLastAcceptedReply,
          restoreScoredRegisters: _restoreScoredRegisters,
          applyMoodDecay: _applyMoodDecay,
          plantTierCrossing: _plantTierCrossing,
          revertRegenBaseline: _revertRegenRealismBaseline,
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
        sessions: EditSessionHooks(
          loadSession: loadSession,
          sessions: getSessions,
          startNewChat: startNewChat,
          awaitHistoryHydrated: _awaitHistoryHydrated,
        ),
        prompt: ImpersonatePromptHooks(
          groupBasePrompt: () => _groupBasePrompt,
          oneToOneBase: _resolveOneToOneBase,
          amendmentsAllowed: () => _amendmentsAllowed,
          sessionGenSettings: () => _sessionGenSettings,
          userPersonaBlock: _buildUserPersonaBlock,
          chatHistory: _buildChatHistory,
          authorNote: () => _authorNote,
          authorNoteBlock: _buildAuthorNoteBlock,
          macroContext: _buildChatMacroContext,
          countTokens: _countTokens,
          historyWithin: (budget, depthLore) async =>
              (await _buildChatHistoryWithBudget(
                budget,
                depthLore: depthLore,
              )).history,
          overflowHistory: () => _overflowContinuityHistory().history,
        ),
      ),
    );
    _forwardDoorNotify(door);
    return door;
  }
}
