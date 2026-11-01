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

/// User-facing notice for "managed backend stopped + auto-start off". Const
/// so [_abortIfBackendDown]'s dedupe can compare against the last message.
const _kBackendDownNotice =
    'Backend is not running. Start it in Settings → Backend, '
    "or enable 'Auto-start on chat open'.";

/// The core response generation orchestrator (`_generateResponse`): speaker
/// selection, the single per-speaker realism eval trigger (group path), and
/// the six-phase turn pipeline (system prompt/lore/persona/scenario/Scene-
/// Guest/summary/Journal assembly → macro pass + PromptPlan registration +
/// history budget → RAG retrieval + joint budget → request dispatch →
/// streaming → post-generation Realism/Needs/Journal/Growth/TTS wiring).
/// Decomposed from a single ~1.9k-line method into the prompt assembler's
/// phases ([PromptAssembler], doors/turn/) and the stream and post-gen parts
/// of this library (god-file split, docs/design/god-file-elimination.md) —
/// every phase method is the ORIGINAL code moved verbatim (mechanical `x` →
/// `t.x` carrier rename via [GenTurn] only). Zero behaviour change. See that
/// doc's map for the full hazard list (H1–H12) if you need to touch a phase
/// boundary.
extension ChatServiceGeneration on ChatService {
  /// True when generation must not proceed: the managed local backend is not
  /// running and auto-start on chat open is off. Appends ONE system notice
  /// naming the toggle (deduped against the last message so group
  /// auto-advance and idle retries can't stack copies), so every entry point
  /// — send, regenerate, continue, swipe, group advance, impersonate — fails
  /// the same friendly way instead of a connection error or silent cancel.
  ///
  /// Deliberately does NOT _saveChat: the notice is transient status, and
  /// persisting here from inside _generateResponse would write the transcript
  /// mid-mutation for callers that pop a message before generating (regen
  /// popped the last AI reply, abort saved the hole — permanent data loss).
  /// Callers that pop MUST also run this check BEFORE their pop (regen paths
  /// do); this deep guard is the backstop for the non-mutating entries.
  Future<bool> _abortIfBackendDown() async {
    if (_llmProvider?.hasManagedProcess != true ||
        _storageService.backendSettings.autostartOnChatOpen ||
        _llmProvider?.hasAnyManagedProcessRunning == true) {
      return false;
    }
    if (_session.messages.isEmpty ||
        _session.messages.last.text != _kBackendDownNotice) {
      _session.messages.add(statusBannerMessage(_kBackendDownNotice));
      notifyListeners();
    }
    return true;
  }

  Future<void> _generateResponse(
    GenerationMode mode, {
    CharacterCard? guestSpeaker,
    CharacterCard? forceSpeaker,
    bool autonomous = false,
    bool directUserSend = false,
    bool skipSpeakerEval = false,
    String regenCritique = '',
  }) async {
    final (forcedWeb, forcedWiki) = mediaDoor.takeForcedLookup();
    // Raise before the first await so an unawaited caller (AFK idle)
    // is visible to drain / _isTurnBusy immediately. A refused turn is
    // lowered inside _admitTurn (chat_service_generation_entry.dart).
    _isGenerating = true;
    notifyListeners();
    final speakers = await _admitTurn(mode, guestSpeaker, forceSpeaker);
    if (speakers == null) return;
    guestSpeaker = speakers.guest;
    forceSpeaker = speakers.force;
    // regenerateLastMessage holds the settling flag; the finally restores it.
    final callerHeldSettling = _isPostGenerating;
    final epoch = ++_generationEpoch;
    _isGenerating = true;
    _generationProgress = 0.0;
    _tokensGenerated = 0;
    _maxTokens = _sessionGenSettings.resolveMaxLength(_storageService);
    _generationStartTime = DateTime.now();
    _generationPhase = GenerationPhase.preparing;
    _prefillStartTime = null;
    _lastPerfData = null;
    _sentenceBuffer = '';
    notifyListeners();

    final t = GenTurn(
      mode: mode,
      guestSpeaker: guestSpeaker,
      epoch: epoch,
      autonomous: autonomous,
      directUserSend: directUserSend,
      forcedWebQuery: forcedWeb,
      forcedWikiQuery: forcedWiki,
    );
    t.regenCritique = regenCritique;

    try {
      final userName = _userPersonaService.persona.name;
      t.userName = userName;

      // Determine the speaking character first (needed for system prompt priority)
      CharacterCard speakingCharacter;
      if (guestSpeaker != null) {
        // Scene Guest (Lite NPC) turn — stays in 1:1 (_activeGroup remains null),
        // the guest speaks in its own bubble. Carries NO Realism/Needs work
        // (see the guestSpeaker == null guards in the post-gen block below).
        speakingCharacter = guestSpeaker;
      } else if (_activeGroup != null) {
        // Continue resolved forceSpeaker above (id-first, refuse on
        // duplicates). Regen already passes it. Fresh turns pick present.
        // Auto-play / trigger-next: quiet-pulse Away members on the N=3
        // cadence. User send already pulsed in send_handoff.
        if (mode == GenerationMode.normal &&
            !directUserSend &&
            forceSpeaker == null) {
          await _runAwayPulse(
            userText: _awayPulse.lastUserText,
            fromUserSend: false,
          );
        }
        if (forceSpeaker == null) {
          t.rotationBeforePick = _session.groupManager?.rotation;
        }
        speakingCharacter = forceSpeaker ?? _pickPresentGroupSpeaker();
      } else {
        speakingCharacter = _session.activeCharacter!;
      }
      t.speakingCharacter = speakingCharacter;

      if (guestSpeaker == null &&
          _activeGroup != null &&
          mode != GenerationMode.continue_ &&
          forceSpeaker == null &&
          AwayPulse.shouldWriteSkipBanner(
            speakerSkips: _groupSpeakerSkips(speakingCharacter),
            hasUnconsumedReturn: _awayPulse.pendingReturnSpeakId != null,
          )) {
        // Whole roster (or a forced @name) is Away / At work. Do not eat
        // the send: write a glance line. No reply to score, so the clock
        // takes the failure-drift step (bucket brigade still moves) and
        // Today is not rewritten.
        if (_clockRunning) {
          await _timeService.applyFailureDrift(
            minutes: directUserSend
                ? StoryClock.conversationalFloorMinutes
                : StoryClock.failureDriftMinutes,
          );
          // F3: persist the drift on the tip so reopen cannot rewind it.
          _clockWriter.writeSlotClock(
            _clockReader.visibleTipMessage(),
            kind: SlotClockWrite.tick,
          );
        }
        _session.messages.add(
          ChatMessage(
            text: _presenceSkipBanner(speakingCharacter),
            sender: 'System',
            isUser: false,
          ),
        );
        debugPrint(
          '[Presence] skip-turn ${speakingCharacter.name} — banner, no reply',
        );
        t.rotationBeforePick = null; // the skip is that member's turn
        _isGenerating = false;
        _generationPhase = GenerationPhase.idle;
        await _saveChat();
        notifyListeners();
        return;
      }

      // Pin the realism speaker for the whole turn so prompt injection + decay
      // key on the character actually generating — not nextCharacter (the
      // *upcoming* speaker, null for random turn order). Soft group members
      // are pinned too: leaving them null made the fallback steal the next
      // full member's Needs/bond. 1:1 scene guests (guestSpeaker) stay null.
      // Cleared in the finally below. Lite turns still skip the realism
      // dance and the realism/objective prompt blocks.
      _groupStore.turnSpeakerId = (_activeGroup != null && guestSpeaker == null)
          ? _getCharacterIdFromCard(speakingCharacter)
          : null;

      // SINGLE realism eval path (group trigger). 1:1 evals live in sendMessage
      // so regen/_generateResponse does not re-score the host. Continue, and
      // user-last regen on a line from before per-speaker stamps, skip the
      // dance but still LOAD this speaker's scalars. A new group turn and a
      // stamped user-last regen (rewound first) dance. Guests carry no realism.
      if (guestSpeaker == null &&
          _activeGroup != null &&
          !_isLiteTurn(t) &&
          _realismActiveThisMode) {
        if (mode == GenerationMode.continue_ || skipSpeakerEval) {
          final sid = _getCharacterIdFromCard(speakingCharacter);
          if (sid.isNotEmpty) _realismDance.loadIntoScalars(sid);
        } else {
          await _realismDance.evaluateForUpcomingSpeaker(speakingCharacter);
          // Cancel-aborts-generation, group edition: consume the flag and
          // abort before any prompt is built. Entry-state flags are reset
          // by hand — the normal clears live in completion/catch.
          if (_realismEvalCancelled) {
            _clockReader.applyTipClock();
            _pendingRealismMetadata = null;
            _needsSimulation.consumePendingCatastrophe();
            _realismEvalCancelled = false;
            _isGenerating = false;
            _generationPhase = GenerationPhase.idle;
            _generationStartTime = null;
            await _saveChat();
            notifyListeners();
            return;
          }
        }
      } else if (guestSpeaker == null && _directing && !_isLiteTurn(t)) {
        _realismDance.prepareDirectedSpeaker(
          speakingCharacter,
          stamp: mode != GenerationMode.continue_ && !skipSpeakerEval,
        );
      }

      // ── The six-phase turn pipeline: four prompt phases on the prompt
      // assembler (doors/turn/), then the stream and post-gen parts ──
      // Fixed order — `late` carrier fields make an out-of-order call a loud
      // LateInitializationError, not silent corruption.
      await promptAssembler.assembleBlocks(t);
      await promptAssembler.buildPlan(t);
      await promptAssembler.retrieveMemories(t);
      await promptAssembler.dispatch(t);
      if (await _consumeGenerationStream(t)) {
        return; // user cancel: turn halted (H2)
      }
      await _finalizeGenerationTurn(t);
    } catch (e) {
      _clockWriter.restoreCapturedThroughReader();
      // A stream that threw mid-think must not leave its live start behind.
      if (t.thinkStartedAt != null) t.sealThinkClock();
      final wasCancelled = _cancelRequested;
      _drainTimer?.cancel();
      _drainTimer = null;
      _tokenBuffer.clear();
      _isGenerating = false;
      _cancelRequested = false;
      _generationProgress = 0.0;
      _generationPhase = GenerationPhase.idle;
      _prefillStartTime = null;
      _prefillPromptTokens = 0;
      _generationStartTime = null;

      // "Connection closed before full header was received" is thrown by the http package
      // when the HTTP client is closed mid-stream (either by abortGeneration() or a process
      // crash/restart). Treat it the same as a user cancel — keep the partial response.
      final treatAsCancel = wasCancelled || looksLikeBackendUnreachable(e);

      // User-initiated cancel (or forced client close) — keep the partial response, no error message
      if (treatAsCancel) {
        // A think-start stamp means the reply was being painted: close its
        // thought like the stream-loop Stop does.
        await _haltStoppedTurn(
          t,
          t.thinkStartedAt != null ? t.streamTarget : null,
        );
        return;
      }

      // Build user-friendly error message (mapping lives in the pure leaf
      // generation_error_messages.dart, not a part — zero ChatService access).
      final errorMsg = friendlyGenerationError(e.toString());

      _session.messages.add(statusBannerMessage(errorMsg));

      // Signal error to SSE listeners
      _tokenBroadcast.add('__ERROR__');
      // '__ERROR__' is a TOKEN-stream sentinel only. The sentence stream must
      // still be told the turn is over — its consumer (call_overlay →
      // TtsService.speakStreaming) closes on '__DONE__' and on nothing else,
      // so without this a non-socket failure (OpenRouter 429/402/5xx, a
      // malformed reply) leaves the voice call stuck on "Thinking…" forever.
      // The buffered fragment is dropped, not spoken: the reply the user gets
      // is the error banner, not a half sentence.
      _sentenceBuffer = '';
      _sentenceBroadcast.add('__DONE__');

      // Restore original model if swapped for call mode
      if (t.originalModelName != null && _llmProvider != null) {
        _llmProvider!.openRouterService.configure(
          modelName: t.originalModelName,
        );
      }

      notifyListeners();
    } finally {
      _llmProvider?.endMouthSpeech();
      // The per-turn realism speaker pin lives only while we generate. Clear it
      // on every exit (normal completion, early return, or error) so the next
      // turn's pre-pick window (e.g. _applyMoodDecay) keeps its prior
      // nextCharacter-based behaviour instead of seeing a stale speaker.
      _groupStore.turnSpeakerId = null;
      // Stopped, refused or failed before the reply landed: the picked
      // member never spoke, so Try again (or the next send) is theirs.
      final rotation = t.rotationBeforePick;
      if (rotation != null && !t.replyLanded) {
        _session.groupManager?.restoreRotation(rotation);
      }
      _awayPulse.finishTurn();
      // Settling over, on EVERY exit — restore the CALLER's hold (regen keeps
      // it raised across its swipe-merge); a latched flag would wedge input.
      _isPostGenerating = callerHeldSettling;
      if (!_isPostGenerating) {
        _postGenAbortRequested = false;
        _isCancellingRealismEval = false;
        _realismEvalCancelled = false;
        // Listeners (web isSettlingTurn → chat_updated) only see the clear
        // through a notification. The flag alone does not broadcast.
        notifyListeners();
      }
    }
  }
}
