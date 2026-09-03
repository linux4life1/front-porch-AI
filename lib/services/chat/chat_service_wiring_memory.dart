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

/// Builders for the memory-adjacent leaf services (The Journal, Growth
/// Rings, Ambitions, the Promise & Debt ledger, Dreams) plus the three
/// lazily-built command/director/detector helpers that already used the
/// `??=` pattern before this split. Extracted verbatim from
/// `chat_service.dart` — zero behaviour change.
extension ChatServiceWiringMemory on ChatService {
  // ── The Journal (docs/design/journal-memory.md) ──
  // Per-chat, per-character memory cards + "Where we are" recap. One periodic
  // maintenance pass (journal_maintenance leaf) replaces the old summary +
  // fact-extraction jobs; the recap reuses the _summary/_summaryLastIndex/
  // _isSummaryGenerating scalars (and their persistence + reset hygiene) so
  // no new god state is introduced. Cards live in the journal_memories table
  // via journal_store; the injection builder renders the speaker's pinned +
  // hot cards into the prompt. Strictly session-scoped — no memory ever
  // crosses chats. 1:1 ↔ group parity by construction (same owner loop).
  JournalStore _buildJournalStore() {
    return JournalStore(
      getDb: () => _db,
      // Availability-guarded single-text embedder; null when RAG is off or the
      // sidecar is down, which just disables cold-card recall (no-RAG floor).
      embedText: (text) async => await _memoryService?.embedText(text),
    );
  }

  /// LLMerta → Journal porch-memory import + one-shot force-ack arming.
  /// Design: docs/design/llmerta-porch-memories.md.
  PorchMemoryImportService _buildPorchMemoryImport() {
    return PorchMemoryImportService(
      journalStore: _journalStore,
      getFpaRootPath: () => _storageService.rootPath,
      isImportEnabled: () =>
          _storageService.memorySettings.importLlmertaPorchMemories,
      getMaxCards: () => _storageService.memorySettings.journalMaxCards,
      libraryStableGroupIds: () {
        final repo = _characterRepository;
        if (repo == null) return <String>{};
        return {for (final c in repo.characters) _getCharacterIdFromCard(c)};
      },
      getConsumedBlockKeys: () =>
          _storageService.memorySettings.porchConsumedBlockKeys,
      setConsumedBlockKeys: (keys) =>
          _storageService.memorySettings.setPorchConsumedBlockKeys(keys),
    );
  }

  // Review-first parking + the ONE proposal applier (both modes go through
  // it). Public via [journalReview] for the sidebar banner + review dialog.
  JournalReview _buildJournalReview() {
    return JournalReview(
      store: _journalStore,
      getSessionId: () => _currentSessionId,
      setRecap: (t) => _summary = t,
      setCursor: (i) => _summaryLastIndex = i,
      onSaveChat: _saveChat,
      onNotify: notifyListeners,
      getMaxCards: () => _storageService.memorySettings.journalMaxCards,
    );
  }

  JournalMaintenance _buildJournalMaintenance() {
    return JournalMaintenance(
      store: _journalStore,
      review: _journalReview,
      probe: _toolProbe,
      fireLLMEval: (p) => _fireLLMEval(p, label: 'journal'),
      fireToolEval: _fireToolEval,
      getPreferTextEvals: () => _storageService.realismSettings.preferTextEvals,
      getPassEpoch: () => _memoryPassEpoch,
      getReviewFirst: () => _storageService.memorySettings.journalReviewFirst,
      getBackendIdentity: () => _evalBackendIdentity,
      stripThinkBlocks: _stripThinkBlocks,
      getSessionId: () => _currentSessionId,
      getActiveCharacter: () => _activeCharacter,
      getActiveGroup: () => _activeGroup,
      getGroupCharacters: () => _groupCharacters,
      getCharacterIdFromCard: _getCharacterIdFromCard,
      getMessages: () => _messages,
      getUserName: () => _userPersonaService.persona.name,
      getCursor: () => _summaryLastIndex,
      setCursor: (i) => _summaryLastIndex = i,
      getRecap: () => _summary,
      setRecap: (t) => _summary = t,
      getIsPassRunning: () => _isSummaryGenerating,
      setIsPassRunning: (v) => _isSummaryGenerating = v,
      getMaxCards: () => _storageService.memorySettings.journalMaxCards,
      onNotify: notifyListeners,
      onSaveChat: _saveChat,
      getCurrentStoryDay: () => _timeService.dayCount,
      getCurrentStoryClockIso: () => _timeService.storyClockIso,
    );
  }

  JournalInjection _buildJournalInjection() {
    return JournalInjection(
      store: _journalStore,
      getSessionId: () => _currentSessionId,
      // Two-tier memory: receipts → live verbatim lines (positions are the
      // stable indices cards already store).
      getMessageAt: (p) => p >= 0 && p < _messages.length ? _messages[p] : null,
      // Same scalar EmotionInjection reads — in group non-obs the pre-gen
      // load-into-scalars dance has set it to the upcoming speaker's emotion
      // by assembly time, so mood-congruent recall is per-speaker (parity).
      getCurrentEmotion: () => _realismEnabled ? _characterEmotion : '',
      getCurrentStoryDay: () => _timeService.dayCount,
      getStoryStartDate: () => _timeService.startDate,
    );
  }

  // ── Growth Rings (docs/design/growth-rings.md) ──
  // Per-chat, per-character growth entries — replaced EvolutionService's
  // whole-personality rewrites (the evolved* session columns are dormant;
  // their content is distilled into rings by the first growth pass). Rings
  // live in the growth_rings table via growth_store, which also keeps the
  // sync injection cache (_getEffectivePersonality runs inside synchronous
  // prompt assembly). The pass is its own small background job with its own
  // cursor (growth_state) — deliberately NOT a rider on the Journal pass,
  // whose per-pass cooling is tuned to journalInterval. Scenario evolution
  // is retired: the recap owns "where we are" (_getEffectiveScenario below).
  // Trigger/cache/UI surface live in chat_service_growth.dart (part file).
  GrowthStore _buildGrowthStore() {
    return GrowthStore(
      getDb: () => _db,
      // Ring text is stored with real names, never {{char}}/{{user}} macros
      // (the timeline displays it verbatim on both surfaces). {{char}} maps to
      // the ring OWNER's name — active char, group member, or scene guest by
      // stable id; unknown owners (departed cast) keep the macro rather than
      // guessing, and {{user}} always resolves to the persona.
      resolveMacros: (charId, text) {
        String? name;
        if (_activeCharacter != null &&
            _getCharacterIdFromCard(_activeCharacter!) == charId) {
          name = _activeCharacter!.name;
        }
        if (name == null) {
          for (final c in _groupCharacters) {
            if (_getCharacterIdFromCard(c) == charId) {
              name = c.name;
              break;
            }
          }
        }
        if (name == null) {
          for (final g in _sceneGuest.cards) {
            if (_getCharacterIdFromCard(g) == charId) {
              name = g.name;
              break;
            }
          }
        }
        return resolveGrowthMacros(
          text,
          charName: name,
          userName: _userPersonaService.persona.name,
        );
      },
    );
  }

  GrowthReview _buildGrowthReview() {
    return GrowthReview(
      store: _growthStore,
      getSessionId: () => _currentSessionId,
      getIsGroup: () => _activeGroup != null,
      onApplied: () => _refreshGrowthCache(),
      onNotify: notifyListeners,
    );
  }

  GrowthService _buildGrowthService() {
    return GrowthService(
      store: _growthStore,
      review: _growthReview,
      probe: _toolProbe,
      fireLLMEval: (p) => _fireLLMEval(p, label: 'growth'),
      fireToolEval: _fireToolEval,
      getPreferTextEvals: () => _storageService.realismSettings.preferTextEvals,
      getPassEpoch: () => _memoryPassEpoch,
      stripThinkBlocks: _stripThinkBlocks,
      getBackendIdentity: () => _evalBackendIdentity,
      getSessionId: () => _currentSessionId,
      getActiveCharacter: () => _activeCharacter,
      getActiveGroup: () => _activeGroup,
      getGroupCharacters: () => _groupCharacters,
      getSceneGuestCards: () => _sceneGuest.cards,
      getCharacterIdFromCard: _getCharacterIdFromCard,
      getMessages: () => _messages,
      getUserName: () => _userPersonaService.persona.name,
      getRecap: () => _summary,
      getJournalCards: (sessionId, charId) =>
          _journalStore.cardsFor(sessionId, charId),
      getGrowthEnabled: () =>
          _storageService.memorySettings.characterEvolutionEnabled,
      getReviewFirst: () => _storageService.memorySettings.growthReviewFirst,
      getIsPassRunning: () => _isGrowthPassRunning,
      setIsPassRunning: (v) => _isGrowthPassRunning = v,
      refreshCache: () => _refreshGrowthCache(),
      onNotify: notifyListeners,
    );
  }

  // ── Ambitions (Living Time §6) ──
  AmbitionService _buildAmbitionService() {
    return AmbitionService(
      journalStore: _journalStore,
      growthStore: _growthStore,
      fireEval: (prompt) async {
        final raw = await _llmEvalEngine.fireLLMEval(prompt, label: 'ambition');
        return raw == null ? null : _llmEvalEngine.stripThinkBlocks(raw);
      },
      getMaxCards: () => _storageService.memorySettings.journalMaxCards,
      onWaypoint: () {
        _journalMaintenance.eventKickPending = true;
        _growthService.eventKickPending = true;
      },
      onCacheWarmed: () {
        if (!_disposed) notifyListeners();
      },
    );
  }

  // ── Promise & debt ledger (Train B) ──
  PromiseDebtService _buildPromiseDebtService() {
    return PromiseDebtService(
      journalStore: _journalStore,
      fireEval: (prompt) async {
        final raw = await _llmEvalEngine.fireLLMEval(prompt, label: 'promise');
        return raw == null ? null : _llmEvalEngine.stripThinkBlocks(raw);
      },
      getMaxCards: () => _storageService.memorySettings.journalMaxCards,
      // Purity gate (maintainer, 2026-08-07). Promises work fine without the
      // engine — detection, the ledger, the Journal card, kept/broken status
      // and the milestone all run — but bond and trust are ENGINE scalars, and
      // with the engine off every other writer is gated. That left a kept
      // promise as the sole thing moving those numbers, in a chat whose own
      // sidebar says "Realism Mode is off": invisible movement the user was
      // told was not being tracked. The promise still resolves; only the score
      // write is skipped.
      applyTrustDelta: (d) {
        if (_realismEnabled) _relationshipService.applyTrustDelta(d);
      },
      applyBondDelta: (d) {
        if (_realismEnabled) _relationshipService.applyScoreDelta(d);
      },
      onSalienceKick: () {
        // Rate-limited (salience_kick_gate.dart): a hot scene clears the
        // salience bar turn after turn, and every clear used to fire a full
        // Journal AND Growth pass immediately. A suppressed kick just waits
        // for the ordinary scheduled cadence.
        if (!_growthService.salienceKickGate.allow(
          sessionId: _currentSessionId,
          messageCount: _messages.length,
        )) {
          debugPrint(
            '[Journal] salient kick suppressed — within '
            '$kSalienceKickMinGapMessages messages of the last one',
          );
          return;
        }
        _journalMaintenance.eventKickPending = true;
        _growthService.eventKickPending = true;
      },
      onCacheWarmed: () {
        if (!_disposed) notifyListeners();
      },
    );
  }

  // ── Dreams (Living Time §1) ──
  DreamService _buildDreamService() {
    return DreamService(
      fireEval: (prompt) async {
        final raw = await _llmEvalEngine.fireLLMEval(prompt, label: 'dream');
        return raw == null ? null : _llmEvalEngine.stripThinkBlocks(raw);
      },
      // Dreams fire on day crossings, so what they need is a clock that
      // crosses days — not the engine. _clockRunning is that condition for
      // either driver; with both off it is false, i.e. exactly the old gate.
      isEnabled: () =>
          _clockRunning &&
          _storageService.journalEnabled &&
          _storageService.dreamsEnabled,
    );
  }

  /// Slash-command dispatcher (lazily built). All cross-state mutations route
  /// back here via small callbacks so the handler stays pure and never imports
  /// this god file or any heavy service.
  ChatCommandHandler _ensureCommandHandler() {
    return _commandHandler ??= ChatCommandHandler(
      setExpression: (label) => _expressionService.setManualExpression(label),
      activeCharacterIsSet: () =>
          _activeCharacter != null && _activeGroup == null,
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
      armExitUndo: armSceneGuestExitUndo,
      getGroupMembers: () =>
          _activeGroup != null ? _groupCharacters : const <CharacterCard>[],
      getGroupJoinableCharacters: () => joinableGroupCharacters,
      removeGroupMember: (member) async {
        final repo = _groupChatRepository;
        if (repo == null) return false;
        // Narrate the member's goodbye + arm a deferred-deletion UNDO; the real
        // removal commits when the user continues (mirrors the Lite-NPC exit).
        return exitGroupMember(member, repo);
      },
      speakGroupMember: (member) async {
        // /speak <name> in a full group: force that member to take their turn now
        // (jump the rotation), mirroring the Lite-NPC /speak. Same setNextSpeaker
        // + generate path the goodbye narration uses, minus the removal/directive.
        if (_activeGroup == null || _isTurnBusy) return;
        _groupManager?.setNextSpeaker(member);
        // Same bucket brigade as Next Character: announce the last
        // decided clock, then post-decide for whoever speaks next.
        await _generateResponse(GenerationMode.normal);
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
      generateImage: (args) => _ensureImageCommand().handle(args),
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
        for (final m in _messages.reversed) {
          if (!m.isUser && m.sender != 'System') return m.displayText;
        }
        return '';
      },
      fireGateEval: (prompt) => _fireLLMEval(
        prompt,
        repeatPenalty: kScalarEvalRepeatPenalty,
        label: 'guest_gate',
      ),
      stripThinkBlocks: _stripThinkBlocks,
      extractJsonBool: _extractJsonBool,
      getHostName: () => _activeCharacter?.name ?? 'the character',
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
        for (final m in _messages.reversed) {
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
      stripThinkBlocks: _stripThinkBlocks,
      getHostName: () => _activeCharacter?.name ?? '',
      getUserName: () => _userPersonaService.persona.name,
      getSceneGuestNames: () => _sceneGuest.cards.map((g) => g.name).toList(),
      getOfferedOrIgnoredNames: () => _sceneGuest.offeredOrIgnoredNames,
    );
  }

  /// "Our Story" timeline read-model (Living Time §7) — pure aggregation
  /// over data already persisted; the journal dialog's timeline tab and the
  /// web facade both read through this one instance.
  MilestoneFeed _buildMilestoneFeed() =>
      MilestoneFeed(getDb: () => _db, getMessages: () => _messages);
}
