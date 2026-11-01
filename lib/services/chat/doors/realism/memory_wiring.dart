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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/doors/session/session_store.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/prompt_injection.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// Builders for the memory-adjacent leaves: the Journal, Growth Rings,
/// Ambitions, the Promise & Debt ledger, Dreams, the "Our Story" feed, the
/// item cards and the timeline invalidator.
extension RealismMemoryWiring on RealismGraph {
  // ── The Journal (docs/design/journal-memory.md) ──
  // Per-chat, per-character memory cards + "Where we are" recap. One periodic
  // maintenance pass (journal_maintenance leaf) replaces the old summary +
  // fact-extraction jobs; the recap reuses the session store's summary,
  // cursor and generating flag (and their persistence + reset hygiene), so
  // no new state is introduced. Cards live in the journal_memories table via
  // journal_store; the injection builder renders the speaker's pinned + hot
  // cards into the prompt. Strictly session-scoped — no memory ever crosses
  // chats. 1:1 ↔ group parity by construction (same owner loop).
  JournalStore buildJournalStore() {
    return JournalStore(
      getDb: deps.services.db,
      // Availability-guarded single-text embedder; null when RAG is off or the
      // sidecar is down, which just disables cold-card recall (no-RAG floor).
      embedText: (text) async => await deps.services.memory()?.embedText(text),
    );
  }

  /// LLMerta → Journal porch-memory import + one-shot force-ack arming.
  /// Design: docs/design/llmerta-porch-memories.md.
  PorchMemoryImportService buildPorchImport() {
    return PorchMemoryImportService(
      journalStore: journalStore,
      getFpaRootPath: () => _storageService.rootPath,
      isImportEnabled: () =>
          _storageService.memorySettings.importLlmertaPorchMemories,
      getMaxCards: () => _storageService.memorySettings.journalMaxCards,
      libraryStableGroupIds: () {
        final repo = deps.services.characters();
        if (repo == null) return <String>{};
        return {for (final c in repo.characters) _h.characterIdFor(c)};
      },
      getConsumedBlockKeys: () =>
          _storageService.memorySettings.porchConsumedBlockKeys,
      setConsumedBlockKeys: (keys) =>
          _storageService.memorySettings.setPorchConsumedBlockKeys(keys),
    );
  }

  // Review-first parking + the ONE proposal applier (both modes go through
  // it). Public via the service's journalReview for the sidebar banner and
  // the review dialog.
  JournalReview buildJournalReview() {
    return JournalReview(
      store: journalStore,
      getSessionId: () => session.currentSessionId,
      setRecap: (t) => _sessions.summary = t,
      setCursor: (i) => _sessions.summaryLastIndex = i,
      onSaveChat: _saveChat,
      onNotify: deps.notify,
      getMaxCards: () => _storageService.memorySettings.journalMaxCards,
    );
  }

  JournalMaintenance buildJournalMaintenance() {
    return JournalMaintenance(
      store: journalStore,
      review: journalReview,
      probe: transport.probe,
      fireLLMEval: (p) => transport.fireLLMEval(p, label: 'journal'),
      fireToolEval: transport.fireToolEval,
      getPreferTextEvals: () => _storageService.realismSettings.preferTextEvals,
      getPassEpoch: _h.memoryPassEpoch,
      getReviewFirst: () => _storageService.memorySettings.journalReviewFirst,
      getBackendIdentity: () => transport.backendIdentity,
      stripThinkBlocks: stripEvalThinkBlocks,
      getSessionId: () => session.currentSessionId,
      getActiveCharacter: () => session.activeCharacter,
      getActiveGroup: () => session.activeGroup,
      getGroupCharacters: () => session.groupCharacters,
      getCharacterIdFromCard: _h.characterIdFor,
      getMessages: () => session.messages,
      getUserName: () => deps.services.personas.persona.name,
      getCursor: () => _sessions.summaryLastIndex,
      setCursor: (i) => _sessions.summaryLastIndex = i,
      getRecap: () => _sessions.summary,
      setRecap: (t) => _sessions.summary = t,
      getIsPassRunning: () => _sessions.isSummaryGenerating,
      setIsPassRunning: (v) => _sessions.isSummaryGenerating = v,
      getMaxCards: () => _storageService.memorySettings.journalMaxCards,
      onNotify: deps.notify,
      onSaveChat: _saveChat,
      getCurrentStoryDay: () => time.dayCount,
      getCurrentStoryClockIso: () => time.storyClockIso,
    );
  }

  JournalInjection buildJournalInjection() {
    return JournalInjection(
      store: journalStore,
      getSessionId: () => session.currentSessionId,
      // Two-tier memory: receipts → live verbatim lines (positions are the
      // stable indices cards already store).
      getMessageAt: (p) =>
          p >= 0 && p < session.messages.length ? session.messages[p] : null,
      // Same register EmotionInjection reads — in group non-obs the pre-gen
      // load-into-scalars dance has set it to the upcoming speaker's emotion
      // by assembly time, so mood-congruent recall is per-speaker (parity).
      getCurrentEmotion: () => controls.realismEnabled ? registers.emotion : '',
      getCurrentStoryDay: () => time.dayCount,
      getStoryStartDate: () => time.startDate,
    );
  }

  // ── Growth Rings (docs/design/growth-rings.md) ──
  // Per-chat, per-character growth entries — replaced EvolutionService's
  // whole-personality rewrites (the evolved* session columns are dormant;
  // their content is distilled into rings by the first growth pass). Rings
  // live in the growth_rings table via growth_store, which also keeps the
  // sync injection cache (GrowthDesk.effectivePersonality runs inside
  // synchronous prompt assembly). The pass is its own small background job with its own
  // cursor (growth_state) — deliberately NOT a rider on the Journal pass,
  // whose per-pass cooling is tuned to journalInterval. Scenario evolution
  // is retired: the recap owns "where we are" (GrowthDesk.effectiveScenario).
  // Trigger/cache/UI surface live in GrowthDesk (growth_desk.dart).
  GrowthStore buildGrowthStore() {
    return GrowthStore(
      getDb: deps.services.db,
      // Ring text is stored with real names, never {{char}}/{{user}} macros
      // (the timeline displays it verbatim on both surfaces). {{char}} maps to
      // the ring OWNER's name — active char, group member, or scene guest by
      // stable id; unknown owners (departed cast) keep the macro rather than
      // guessing, and {{user}} always resolves to the persona.
      resolveMacros: (charId, text) {
        String? name;
        if (session.activeCharacter != null &&
            _h.characterIdFor(session.activeCharacter!) == charId) {
          name = session.activeCharacter!.name;
        }
        if (name == null) {
          for (final c in session.groupCharacters) {
            if (_h.characterIdFor(c) == charId) {
              name = c.name;
              break;
            }
          }
        }
        if (name == null) {
          for (final g in _guestCards) {
            if (_h.characterIdFor(g) == charId) {
              name = g.name;
              break;
            }
          }
        }
        return resolveGrowthMacros(
          text,
          charName: name,
          userName: deps.services.personas.persona.name,
        );
      },
    );
  }

  GrowthReview buildGrowthReview() {
    return GrowthReview(
      store: growthStore,
      getSessionId: () => session.currentSessionId,
      getIsGroup: () => session.activeGroup != null,
      onApplied: () => growthDesk.refreshCache(),
      onNotify: deps.notify,
    );
  }

  GrowthService buildGrowthService() {
    return GrowthService(
      store: growthStore,
      review: growthReview,
      probe: transport.probe,
      fireLLMEval: (p) => transport.fireLLMEval(p, label: 'growth'),
      fireToolEval: transport.fireToolEval,
      getPreferTextEvals: () => _storageService.realismSettings.preferTextEvals,
      getPassEpoch: _h.memoryPassEpoch,
      stripThinkBlocks: stripEvalThinkBlocks,
      getBackendIdentity: () => transport.backendIdentity,
      getSessionId: () => session.currentSessionId,
      getActiveCharacter: () => session.activeCharacter,
      getActiveGroup: () => session.activeGroup,
      getGroupCharacters: () => session.groupCharacters,
      getSceneGuestCards: () => _guestCards,
      getCharacterIdFromCard: _h.characterIdFor,
      getMessages: () => session.messages,
      getUserName: () => deps.services.personas.persona.name,
      getRecap: () => _sessions.summary,
      getJournalCards: (sessionId, charId) async => [
        for (final c in await journalStore.cardsFor(sessionId, charId))
          cooledForStoryDay(c, time.dayCount),
      ],
      getGrowthEnabled: () =>
          _storageService.memorySettings.characterEvolutionEnabled,
      getReviewFirst: () => _storageService.memorySettings.growthReviewFirst,
      getGrowthInterval: () => _storageService.memorySettings.growthInterval,
      getIsPassRunning: () => growthPassRunning,
      setIsPassRunning: (v) => growthPassRunning = v,
      refreshCache: () => growthDesk.refreshCache(),
      onNotify: deps.notify,
    );
  }

  GrowthDesk buildGrowthDesk() => GrowthDesk(
    messages: session.messages,
    macroResolver: deps.services.macros,
    store: () => growthStore,
    review: () => growthReview,
    service: () => growthService,
    journalMaintenance: () => journalMaintenance,
    currentSessionId: () => session.currentSessionId,
    activeCharacter: () => session.activeCharacter,
    activeGroup: () => session.activeGroup,
    groupCharacters: () => session.groupCharacters,
    sceneGuestCards: () => _guestCards,
    characterIdFor: _h.characterIdFor,
    memorySettings: () => _storageService.memorySettings,
    hasLlm: () => deps.services.llmProvider() != null,
    isGrowthPassRunning: () => growthPassRunning,
    awaitHistoryHydrated: () => _sessions.window.awaitHistoryHydrated(),
    setPending: (v) => registers.pending = v,
    notify: deps.notify,
  );

  ItemCardJournal buildItemCards() => ItemCardJournal(
    messages: session.messages,
    history: _sessions.history,
    currentSessionId: () => session.currentSessionId,
    journalStore: () => journalStore,
    db: deps.services.db,
    time: () => time,
    memorySettings: () => _storageService.memorySettings,
    activeCharacterName: () => session.activeCharacter?.name,
  );

  TimelineInvalidator buildTimeline() => TimelineInvalidator(
    messages: session.messages,
    currentSessionId: () => session.currentSessionId,
    summary: () => _sessions.summary,
    setSummary: (v) => _sessions.summary = v,
    armRecapClear: () => _sessions.recapClearArmed = true,
    summaryLastIndex: () => _sessions.summaryLastIndex,
    setSummaryLastIndex: (v) => _sessions.summaryLastIndex = v,
    journalStore: () => journalStore,
    journalReview: () => journalReview,
    journalMaintenance: () => journalMaintenance,
    growthStore: () => growthStore,
    growthReview: () => growthReview,
    growth: () => growthDesk,
    itemCards: () => itemCards,
    db: deps.services.db,
    disposed: _h.disposed,
    notify: deps.notify,
  );

  /// "Our Story" timeline read-model (Living Time §7) — pure aggregation
  /// over data already persisted; the journal dialog's timeline tab and the
  /// web facade both read through this one instance.
  MilestoneFeed buildMilestoneFeed() => MilestoneFeed(
    getDb: deps.services.db,
    getMessages: () => session.messages,
  );

  // ── Ambitions (Living Time §6) ──
  AmbitionService buildAmbitions() {
    return AmbitionService(
      journalStore: journalStore,
      growthStore: growthStore,
      fireEval: (prompt) async {
        final raw = await llmEvalEngine.fireLLMEval(prompt, label: 'ambition');
        return raw == null ? null : llmEvalEngine.stripThinkBlocks(raw);
      },
      getMaxCards: () => _storageService.memorySettings.journalMaxCards,
      onWaypoint: () => growthDesk.requestSalienceKick(),
      onCacheWarmed: () {
        if (!_h.disposed()) deps.notify();
      },
    );
  }

  /// Sidebar/web read surface (Living Time §6): [card]'s ambitions with
  /// live progress — triggers the lazy cache warm, so first render may show
  /// "just beginning" and correct itself one notify later. The ONE merge of
  /// card-authored definitions + per-chat progress; desktop and web both
  /// read through it so they can't drift.
  List<({String text, int progress})> ambitionsFor(CharacterCard card) {
    final sessionId = session.currentSessionId;
    final list = card.frontPorchExtensions?.ambitions ?? const [];
    if (sessionId == null || list.isEmpty) return const [];
    final cid = _h.characterIdFor(card);
    ambitions.ensureCacheWarm(sessionId, cid);
    final progress = ambitions.cachedProgress(sessionId, cid) ?? const {};
    return [for (final a in list) (text: a, progress: progress[a] ?? 0)];
  }

  // ── Promise & debt ledger (Train B) ──
  PromiseDebtService buildPromiseDebt() {
    return PromiseDebtService(
      journalStore: journalStore,
      fireEval: (prompt) async {
        final raw = await llmEvalEngine.fireLLMEval(prompt, label: 'promise');
        return raw == null ? null : llmEvalEngine.stripThinkBlocks(raw);
      },
      getMaxCards: () => _storageService.memorySettings.journalMaxCards,
      // Purity gate (maintainer, 2026-08-07). Promises work fine without the
      // engine — detection, the ledger, the Journal card, kept/broken status
      // and the milestone all run — but bond and trust are ENGINE scalars, and
      // with the engine off every other writer is gated. That left a kept
      // promise as the sole thing moving those numbers, in a chat whose own
      // sidebar says "The Realism Engine is off": invisible movement the user was
      // told was not being tracked. The promise still resolves; only the score
      // write is skipped.
      applyTrustDelta: (d) {
        if (controls.realismEnabled) relationship.applyTrustDelta(d);
      },
      applyBondDelta: (d) {
        if (controls.realismEnabled) relationship.applyScoreDelta(d);
      },
      onSalienceKick: () => growthDesk.requestSalienceKick(),
      onCacheWarmed: () {
        if (!_h.disposed()) deps.notify();
      },
    );
  }

  // ── Dreams (Living Time §1) ──
  DreamService buildDreams() {
    return DreamService(
      fireEval: (prompt) async {
        final raw = await llmEvalEngine.fireLLMEval(prompt, label: 'dream');
        return raw == null ? null : llmEvalEngine.stripThinkBlocks(raw);
      },
      // Dreams fire on day crossings, so what they need is a clock that
      // crosses days — not the engine. The clock gate is that condition for
      // either driver; with both off it is false, i.e. exactly the old gate.
      isEnabled: () =>
          controls.clockRunning &&
          _storageService.memorySettings.journalEnabled &&
          _storageService.realismSettings.dreamsEnabled,
    );
  }
}

extension on RealismGraph {
  StorageService get _storageService => deps.services.storage;
  RealismShellHooks get _h => deps.hooks;
  SessionStore get _sessions => deps.doors.sessions();
  List<CharacterCard> get _guestCards => deps.doors.cast().guests.state.cards;
  Future<void> _saveChat() => _sessions.save();
}
