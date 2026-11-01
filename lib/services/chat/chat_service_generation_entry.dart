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

/// Turn admission for `_generateResponse`: the checks between raising
/// `_isGenerating` and the turn's own try/finally.
extension ChatServiceGenerationEntry on ChatService {
  /// The speakers to run the turn with, or null when it may not run: the
  /// backend is down, or a Continue whose speaker has left or is unclear.
  ///
  /// Every refusal (and a throw) leaves through the one `finally`, which
  /// ends the turn that never ran. A refusal that only returned left the
  /// flag up: Send then did nothing and a chat switch waited forever.
  Future<({CharacterCard? guest, CharacterCard? force})?> _admitTurn(
    GenerationMode mode,
    CharacterCard? guestSpeaker,
    CharacterCard? forceSpeaker,
  ) async {
    var admitted = false;
    try {
      if (await _abortIfBackendDown()) return null;
      // Continue is regen's sibling for WHO is speaking. Infer guest / group
      // member from the bubble; refuse rather than guess.
      if (mode == GenerationMode.continue_ && _session.messages.isNotEmpty) {
        final last = _session.messages.last;
        guestSpeaker ??= _sceneGuestForMessage(last);
        if (guestSpeaker == null && _isGuestAuthoredMessage(last)) {
          _setGuestStatus(
            'Can’t continue "${last.sender}" — they have left the scene.',
            isError: true,
          );
          return null;
        }
        if (guestSpeaker == null && _activeGroup != null) {
          forceSpeaker ??= _resolveGroupSpeakerForMessage(last);
          if (forceSpeaker == null) {
            _setGuestStatus(
              'Can’t continue "${last.sender}" — who said it is ambiguous.',
              isError: true,
            );
            return null;
          }
        }
      }
      admitted = true;
      return (guest: guestSpeaker, force: forceSpeaker);
    } finally {
      if (!admitted) {
        // No turn will run — terminate BOTH live streams. The sentence
        // stream has no error sentinel: `call_overlay` closes its controller
        // on '__DONE__' alone, and `TtsService.speakStreaming` blocks in
        // `await for` until that close, so a silent bail freezes a voice call
        // on "Thinking…" with the mic never re-armed. The phone's chat ends
        // its pending reply on the token sentinel.
        _tokenBroadcast.add('__ERROR__');
        _sentenceBroadcast.add('__DONE__');
        _isGenerating = false;
        notifyListeners();
      }
    }
  }
}

/// The promise ledger: the post-reply commitment pass and the diary's
/// manual "Mark kept / broken".
extension ChatServicePromiseLedger on ChatService {
  /// Manual "Mark kept / broken" from the diary's Promises tab (desktop) and
  /// the web Promises panel. Same applier as automatic detection — the
  /// trust/bond effects apply too, restoring what a missed detection should
  /// have done.
  Future<bool> resolvePromiseManually({
    required String characterId,
    required String cardId,
    required bool kept,
  }) async {
    final sessionId = _session.currentSessionId;
    if (sessionId == null) return false;
    // Never mid-turn: the scalar dance below would fight the active
    // speaker's own load/save.
    if (_isTurnBusy) return false;
    // Group parity: the service's trust/bond callbacks land on whichever
    // member's scalars are LOADED. Manual resolution can come from any
    // member's diary at any time, so run the same load → apply → save
    // dance the post-gen checks use, scoped to that member.
    final isGroupMember =
        _activeGroup != null &&
        _groupCharacters.any((c) => _getCharacterIdFromCard(c) == characterId);
    if (isGroupMember) _realismDance.loadIntoScalars(characterId);
    final ok = await _promiseDebtService.resolveManually(
      sessionId: sessionId,
      characterId: characterId,
      cardId: cardId,
      kept: kept,
      storyDay: _timeService.dayCount,
      storyClock: _timeService.storyClockIso,
    );
    if (isGroupMember) _realismDance.saveScalarsIntoGroup(characterId);
    if (ok) await _saveChat();
    return ok;
  }

  /// Train B — promise/debt ledger pass (fire-and-forget). Detects new
  /// commitments or kept/broken resolutions for the current speaker's diary.
  /// Gated on the Journal and its own switch, NOT on the Realism Engine. It
  /// used to require realism, but nothing here consumes realism state: the pass
  /// reads the recent exchange text and writes a journal card. The story day
  /// and clock it stamps are nullable and nothing reads them back, so a frozen
  /// clock costs nothing. The Journal genuinely is required — a commitment IS a
  /// journal card — and the separate switch exists because this is one extra
  /// model call per reply, which a user who turned realism off to save calls
  /// deserves to opt into rather than inherit.
  void _maybeRunPromiseDebtPass() {
    if (!_storageService.realismSettings.promiseLedgerEnabled) return;
    if (!_storageService.memorySettings.journalEnabled) return;
    final sessionId = _session.currentSessionId;
    if (sessionId == null) return;
    final charId = _groupStore.currentSpeakerId();
    if (charId.isEmpty) return;

    String characterName = _session.activeCharacter?.name ?? 'the character';
    if (_activeGroup != null) {
      final card = _groupCharacters
          .where((c) => _getCharacterIdFromCard(c) == charId)
          .firstOrNull;
      if (card != null) characterName = card.name;
    }

    // 6, not the judges' 4: a promise often spans a couple of exchanges
    // (missed KEPT if it scrolls out — 2026-08-04). recentExchange is the
    // one window builder (clamp, photo markers, think-strip).
    final recent = recentExchange(_session.messages, take: 6);
    if (recent.trim().isEmpty) return;

    unawaited(
      _promiseDebtService.evaluateTurn(
        sessionId: sessionId,
        characterId: charId,
        characterName: characterName,
        userName: _userPersonaService.persona.name,
        recentExchange: recent,
        receiptPosition: persistTipCite(
          base: _history.basePosition,
          length: _session.messages.length,
        ).firstOrNull,
        storyDay: _timeService.dayCount,
        storyClock: _timeService.storyClockIso,
      ),
    );
  }
}

/// Approach A′ soft members on the turn path (the two checks take the
/// library-private turn record `_GenTurn`, the turn engine's, WP10b), and
/// the lazily built slash-command handler, guest director and cast
/// detector. All cross-state routes back here through callbacks so the
/// leaves never import this library.
extension ChatServiceTurnHelpers on ChatService {
  /// 1:1 guest turn **or** a soft group member speaking. Do not set
  /// `guestSpeaker` for the latter — that skip would drop Away / pick.
  bool _isLiteTurn(_GenTurn t) =>
      t.guestSpeaker != null || _speakerIsSoft(t.speakingCharacter);

  /// After the clock commits; body in [AfterglowPass.tickAfterClock]. A lite
  /// beat (guest or soft member) has no speaker refractory to open.
  void _tickRefractoryAfterClock(_GenTurn t) => _afterglow.tickAfterClock(
    t.mode,
    speakerIdOf: () =>
        _isLiteTurn(t) ? null : _getCharacterIdFromCard(t.speakingCharacter),
    reply: () => t.streamTarget,
  );

  /// Slash-command dispatcher (lazily built). All cross-state mutations route
  /// back here via small callbacks so the handler stays pure and never imports
  /// this god file or any heavy service.
  ChatCommandHandler _ensureCommandHandler() {
    return _commandHandler ??= ChatCommandHandler(
      setExpression: (label) => _expressionService.setManualExpression(label),
      activeCharacterIsSet: () =>
          _session.activeCharacter != null && _activeGroup == null,
      getSceneGuestCards: () => _sceneGuest.cards,
      setPendingGuestDeparture: (name) => _sceneGuest.pendingDeparture = name,
      onSystemMessage: (message) =>
          // Surface usage hints / errors as the transient inline banner instead
          // of a saved 'System' chat message (no litter). '⚠' prefix = error.
          _setGuestStatus(message, isError: message.startsWith('⚠')),
      generatePrimaryTurn: () => _generateResponse(GenerationMode.normal),
      createGuest: (name, concept) => _addGuestWithStatus(
        displayName: name,
        mint: (onStatus) => _mintSceneGuest(name, concept, onStatus: onStatus),
      ),
      exitGuest: (guest) async {
        _sceneGuest.ids.remove(guest.dbId);
        await _resolveSceneGuestCards();
        await _saveChat();
      },
      getJoinableCharacters: () => joinableGuestCharacters,
      joinGuest: joinSceneGuest,
      joinFull: joinFull,
      promoteScene: promoteSceneToFull,
      requestGuestPicker: (filter, full) {
        _sceneGuest.pendingPickerFilter = filter;
        _sceneGuest.pendingPickerFull = full;
        notifyListeners();
      },
      runCastScan: runCastDetectionNow,
      speakGuest: speakGuestNow,
      getHostCharacter: () => _session.activeCharacter,
      isTurnBusy: () => _isTurnBusy || _sceneGuest.busy,
      armExitUndo: armSceneGuestExitUndo,
      getGroupMembers: () =>
          _activeGroup != null ? _groupCharacters : const <CharacterCard>[],
      getGroupJoinableCharacters: () => joinableGroupCharacters,
      removeGroupMember: (member) async {
        final repo = _groupChatRepository;
        if (repo == null) return false;
        if (!canRemoveCastMember) {
          _setGuestStatus(kDirectorCastFloorNote, isError: true);
          return true; // answered: the floor note says why
        }
        // Narrate the member's goodbye + arm a deferred-deletion UNDO; the real
        // removal commits when the user continues (mirrors the Lite-NPC exit).
        return exitGroupMember(member, repo);
      },
      speakGroupMember: (member) async {
        // /speak <name> in a full group: force that member to take their turn
        // now (jump the rotation), including Away/at-work (forceSpeaker).
        if (_activeGroup == null) return;
        if (_isTurnBusy) {
          _setGuestStatus('Busy — try again in a moment.', isError: true);
          return;
        }
        _releaseHeldAway(member);
        _session.groupManager?.setNextSpeaker(member);
        final tipBefore = _session.messages.lastOrNull;
        await _generateResponse(GenerationMode.normal, forceSpeaker: member);
        // forceSpeaker skips the pick, so close the turn here once the
        // member's reply landed: the rotation carries on after them. A
        // refused or failed turn keeps them up next for the retry.
        final tip = _session.messages.lastOrNull;
        final said = tip == null || identical(tip, tipBefore) || tip.isUser
            ? null
            : _resolveGroupSpeakerForMessage(tip);
        final spoke =
            said != null &&
            _getCharacterIdFromCard(said) == _getCharacterIdFromCard(member);
        if (spoke) {
          _session.groupManager?.clearForcedSpeaker();
          _session.groupManager?.advanceAfterRegeneration(member);
        }
      },
      isGroupTurnOrderRandom: () => isGroupTurnOrderRandom,
      setGroupTurnOrder: (random, customOrder) =>
          setGroupTurnOrder(random, customOrder),
      configureAfk: (enabled, maxMessages, intervalSeconds) {
        // Drive the same persisted Dynamic Responses settings the sidebar panel
        // uses (single source of truth — no parallel AFK state). Returns the
        // effective values so the handler can word its confirmation.
        final gen = _storageService.generationSettings;
        if (!enabled) {
          gen.setDynamicResponses(false);
          pauseDynamicResponses();
          return (
            enabled: false,
            maxMessages: gen.dynamicResponseMaxMessages,
            intervalSeconds: gen.dynamicResponseInterval,
          );
        }
        if (intervalSeconds != null) {
          gen.setDynamicResponseInterval(intervalSeconds);
        }
        if (maxMessages != null) gen.setDynamicResponseMaxMessages(maxMessages);
        gen.setDynamicResponses(true);
        // Fresh AFK run. resumeDynamicResponses arms now if an exchange already
        // happened this session; otherwise the timer arms after the next reply.
        _consecutiveAutoResponses = 0;
        resumeDynamicResponses();
        return (
          enabled: true,
          maxMessages: gen.dynamicResponseMaxMessages,
          intervalSeconds: gen.dynamicResponseInterval,
        );
      },
      generateImage: (args) => mediaDoor.ensureImageCommand().handle(args),
      director: DirectorCommands(
        isGroup: () => _activeGroup != null,
        hasSceneGuests: () => _sceneGuest.cards.isNotEmpty,
        isDirecting: () => _directing,
        promoteSceneToGroup: promoteSceneToFull,
        stepUserOffStage: stepUserOffStage,
        stepUserOnStage: stepUserOnStage,
        getCast: () => _groupCharacters,
        setWhisper: (member, text) =>
            setDirectorWhisper(_getCharacterIdFromCard(member), text),
        setGoal: setDirectorGoal,
        narrate: narrateScene,
        onSystemMessage: (m) => _setGuestStatus(m, isError: m.startsWith('⚠')),
      ),
    );
  }

  /// Auto chime-in director (lazily built). Pure leaf — all cross-state routes
  /// back via callbacks so it never imports this god file. Reuses the existing
  /// `LlmEvalEngine` fire/strip/extract surface for its relevance gate (no new
  /// LLM-firing path) and only triggers parity-safe guest turns.
  SceneGuestDirector _ensureSceneGuestDirector() {
    return _sceneGuest.director ??= SceneGuestDirector(
      getSceneGuestCards: () => _sceneGuest.cards,
      generateGuestTurn: generateGuestTurn,
      getLatestAssistantText: () {
        for (final m in _session.messages.reversed) {
          if (!m.isUser && m.sender != 'System') return m.displayText;
        }
        return '';
      },
      fireGateEval: (prompt) => _fireLLMEval(
        prompt,
        repeatPenalty: kScalarEvalRepeatPenalty,
        label: 'guest_gate',
      ),
      stripThinkBlocks: stripEvalThinkBlocks,
      extractJsonBool: evalJsonBool,
      getHostName: () => _session.activeCharacter?.name ?? 'the character',
      isEnabled: () => autoChimeEnabled,
    );
  }

  /// Cast detector (lazily built). Pure leaf — all cross-state routes back via
  /// callbacks so it never imports this god file. Reuses the existing
  /// `LlmEvalEngine` fire/strip surface (no new LLM-firing path).
  CastDetector _ensureCastDetector() {
    return _sceneGuest.castDetector ??= CastDetector(
      // Shared tools transport (one probe per backend identity, app-wide).
      fireToolEval: _fireToolEval,
      probe: _toolProbe,
      getBackendIdentity: () => _evalBackendIdentity,
      getRecentPrimaryTexts: () {
        // HOST narration only — exclude user, System, AND Scene Guest messages.
        // The detector prompt says "read <host>'s narration", so feeding it a
        // guest's lines would let a guest "introduce" a character or get a guest
        // misattributed to the host.
        final out = <String>[];
        for (final m in _session.messages.reversed) {
          if (!m.isUser &&
              m.sender != 'System' &&
              !_isGuestAuthoredMessage(m)) {
            out.add(m.displayText);
          }
          if (out.length >= 6) break;
        }
        return out.reversed.toList();
      },
      fireLLMEval: (prompt) => _fireLLMEval(
        prompt,
        repeatPenalty: kScalarEvalRepeatPenalty,
        label: 'cast',
      ),
      stripThinkBlocks: stripEvalThinkBlocks,
      getHostName: () =>
          _session.activeCharacter?.name ??
          nextCharacter?.name ??
          _groupCharacters.firstOrNull?.name ??
          '',
      getUserName: () => _userPersonaService.persona.name,
      getSceneGuestNames: () => [
        ..._sceneGuest.cards.map((g) => g.name),
        ..._groupCharacters.map((c) => c.name),
      ],
      getOfferedOrIgnoredNames: () => _sceneGuest.offeredOrIgnoredNames,
    );
  }
}
