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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/cast/cast_door.dart';
import 'package:front_porch_ai/services/chat/doors/session/session_store.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';

import 'entry_door.dart';

/// Open a 1:1: the departing chat flushed and detached, every per-chat
/// register reset, the character's last session loaded, or, with none, a
/// new chat seeded from the card (Realism, bond, clock, Afterglow, Chaos,
/// Needs, objectives), its worlds attached and its greeting placed.
class ChatEntry {
  ChatEntry(this._door, this._d);

  final EntryDoor _door;
  final EntryDeps _d;

  ChatSessionState get _session => _d.session;
  EntryServices get _s => _d.services;
  EntryShellHooks get _h => _d.hooks;
  SessionShellHooks get _sh => _d.shared;
  SessionStore get _store => _d.sessions();
  GroupSessionConfig get _group => _store.groupConfig;
  RealismScope get _scope => _s.realism();
  CastDoor get _cast => _s.cast();
  SceneGuestState get _sceneGuest => _cast.guests.state;
  GroupRealismStore get _groupStore => _scope.groups;
  RelationshipService get _relationshipService => _scope.relationship();
  NsfwService get _nsfwService => _scope.nsfw();
  TimeService get _timeService => _scope.time();
  NeedsSimulation get _needsSimulation => _scope.needs();
  ChaosModeService get _chaosModeService => _s.chaos();
  LorebookScanner get _lorebookScanner => _s.lorebook();
  ExpressionService get _expressionService => _s.expression();
  MoodRegisters get _mood => _s.mood();
  StoryClockWriter get _clockWriter => _s.clockWriter();
  GrowthDesk get _growthDesk => _s.growthDesk();

  /// The chat's own Realism switch: reset, then seeded from the card.
  bool get _realismChatSwitch => _s.controls().chatRealism;
  set _realismChatSwitch(bool on) => _s.controls().setChatRealism(on);

  /// The chat's stored Needs switch: seeded here, never a gate.
  bool get _needsSimEnabled => _scope.needsSimEnabled();
  set _needsSimEnabled(bool on) => _s.controls().needsSimEnabled = on;
  set _enjoysLowHygiene(bool on) => _s.controls().chatEnjoysLowHygiene = on;
  set _objectivesEnabled(bool on) => _s.controls().objectivesEnabled = on;
  set _isGrowthPassRunning(bool on) => _s.graph().growthPassRunning = on;
  set _pockets(Pockets? record) => _s.graph().hostPockets = record;

  Future<void> setActiveCharacter(CharacterCard? character) async {
    // Overlay on BEFORE cancel/settle/flush so ChatPage can cover the switch
    // the instant home pushes the route. A caller that already called
    // beginSessionLoad keeps the flag across a follow-up loadSession.
    final ownedLoad = !_store.isLoadingSession;
    _door.cover.beginSessionLoad();
    try {
      // Cancel any in-flight generation before switching context, then wait
      // out the settling tail so the reload below reads fully-persisted rows.
      await _sh.cancelAndWaitForGeneration();
      await _door.cover.waitForTurnToSettle();
      _h.bumpGenerationEpoch();

      // Same library card: match by dbId when both sides have one (renames
      // stay light). A grid card with a missing dbId used to fail
      // `dbId == dbId` (uuid != null), take the slow path, assign the
      // dbId-less card, skip `_loadLastSession`, and seed a NEW greeting
      // session — the last exchange (and sometimes the whole chat) vanished.
      final sameCharacter =
          character != null &&
          _session.activeCharacter != null &&
          ((character.dbId != null &&
                  _session.activeCharacter!.dbId != null &&
                  character.dbId == _session.activeCharacter!.dbId) ||
              (character.name == _session.activeCharacter!.name &&
                  (character.dbId == null ||
                      _session.activeCharacter!.dbId == null)));
      if (sameCharacter && _session.messages.isNotEmpty) {
        // Keep the dbId-bearing instance when the grid card is missing one
        // so a later save still stamps sessions.character_id.
        if (character.dbId != null) {
          _session.activeCharacter = character;
        }
        _d.notify();
        return;
      }

      // About to throw the live list away. Write it first so a slow-path
      // reload cannot hydrate a row that is still missing this turn.
      await _store.save();
      // Detach before swapping the owner. Anything that saves between
      // `_session.activeCharacter =` and `_loadLastSession` used to rebind this
      // row to the incoming card (history/E2E then loadSession-ed Nightowl).
      _session.currentSessionId = null;

      // Reset AFK idle state when switching to a different chat
      _cast.idle.cancelIdleTimer();
      _cast.idle.hasCompletedExchange = false;
      _cast.away.state.reset();

      // Clear group mode when switching to 1:1 AND reset author note for new session context
      _store.authorNote = '';
      _store.authorNoteStrength = 4;
      _session.groupManager?.leaveGroup();
      _session.groupManager = null;
      _groupStore.members = {};
      _group.authorNotes = {};
      _group.authorNoteStrengths = {};
      _group.characterSystemPrompts = {};
      _group.ragEnabled = true;
      _group.retrievalCount = 4;
      _group.memoryBudgetPercent = 10.0;
      _group.characterRAGPriorities = {};

      // Reset Scene Guests for the new 1:1 context (repopulated by _loadLastSession
      // if the loaded session persisted any). _sceneGuest.pendingDeparture is one-shot.
      _sceneGuest.ids.clear();
      _sceneGuest.cards.clear();
      _sceneGuest.pendingDeparture = null;
      _sceneGuest.pendingPickerFilter = null;
      _cast.guests.resetActivityState();
      // Phase 2 cast detection: reset the scan cadence + pending/debounce state
      // for the new 1:1 context (kept in sync with the Scene Guest clears).
      _sceneGuest.turnsSinceCastScan = 0;
      _sceneGuest.pendingDetection = null;
      _sceneGuest.offeredOrIgnoredNames.clear();
      _s.sceneMoves.reset(); // Slice 6: stale offers die with the session too.

      _session.activeCharacter = character;

      // Auto-start the local Kobold backend (native or a .kcpps preset) when
      // entering a chat so the user never has to manually start it just to talk.
      // Gated by autostartOnChatOpen — when off, the user must start manually.
      // A start that is refused is kept by the provider, and the composer's
      // connection hint says why.
      if (_s.storage.backendSettings.autostartOnChatOpen) {
        _s.llmProvider()?.ensureManagedBackendIsRunning();
      }

      // If extensions are missing (e.g., app was restarted after DB load that
      // didn't carry over PNG extensions), reload the PNG to get V2.5 card data.
      if (_session.activeCharacter != null &&
          _session.activeCharacter!.frontPorchExtensions == null &&
          _session.activeCharacter!.imagePath != null) {
        try {
          final v2Service = V2CardService();
          final reloaded = await v2Service.readCard(
            _session.activeCharacter!.imagePath!,
          );
          if (reloaded != null && reloaded.frontPorchExtensions != null) {
            _session.activeCharacter!.frontPorchExtensions =
                reloaded.frontPorchExtensions;
            _session.activeCharacter!.rawExtensions = reloaded.rawExtensions;
            debugPrint(
              '[Chat] Reloaded frontPorchExtensions from PNG for ${_session.activeCharacter!.name}',
            );
          }
        } catch (e) {
          debugPrint('[Chat] Failed to reload PNG extensions: $e');
        }
      }

      // Note: growth rings are cached inside _loadLastSession() (which runs
      // below) so they are scoped to the session, not the character.
      debugPrint(
        '[Chat] 🟡 setActiveCharacter: clearing messages '
        '(had ${_session.messages.length}) for ${character?.name}, loading session...',
      );
      await _cast.greetings.invalidateGreetingEval();
      _session.messages.clear();
      _cast.greetings.greetingIndex = 0;
      _store.history.reset();
      _session.currentSessionId = null;
      _store.today.clearTodayPointer();
      _store.summary = '';
      _store.summaryLastIndex = 0;
      _store.selectedLooks
          .clear(); // fresh 1:1: drop prior chat's per-chat look selection (keep reset blocks in sync)
      _store.summaryPaused =
          false; // explicit secondary zero for _summaryPaused (symmetric to _isSummaryGenerating; incomplete zeroing... now complete (see CLAUDE.md); see keep-sync + journal_maintenance)
      _store.isSummaryGenerating =
          false; // explicit secondary zero on setActiveCharacter (incomplete zeroing of secondary config on ... now complete; see keep-sync + journal_maintenance)
      // Clear fork/branch state so it doesn't leak from previous character
      // into a fresh character's first session (see startNewChat for details).
      _store.parentSessionId = null;
      _store.forkIndex = null;

      if (_session.activeCharacter != null) {
        // Lorebook trigger reset via extracted service (keeps the keep-sync reset sites correct
        // without god privates; constants skipped, non-const zeroed for char + attached worlds).
        // See lorebook_scanner.dart and "keep reset blocks" comments (now lists needs/chaos/relationship/expression/time/nsfw/lorebook_scanner + prompt_injection (stateless builders; no reset calls needed) + llm_eval_engine (stateless or prompt-only; no reset calls needed; incomplete zeroing... now complete (see CLAUDE.md)) + needs_impact_evaluator (stateless or prompt-only; no reset calls needed) + realism_evals (stateless or prompt-only; no reset calls needed) + objective_proposal (stateless or prompt-only; no reset calls needed) + journal_maintenance (stateless or prompt-only; no reset calls needed)). (cross-ref setActiveCharacter:1572 etc)
        _lorebookScanner.resetLorebookTriggerState();

        // Reset realism state to prevent bleeding from previous character.
        // Keep the reset sites (startNewChat 1:1+group now with explicit lorebook reset in both branches, load*Session paths incl. empty for groups, setActiveGroup, setActiveCharacter, delete flows, ext-seed, fork/insert)
        // in sync when moving more state in later Stage 3 steps. See needs_simulation.dart for the
        // current owner of vector + buffers (and _needsSimEnabled/_enjoysLowHygiene control fields).
        // Relationship + Expression + Time + Nsfw + LorebookScanner via service reset helpers (expression: manual/caches/onnx/lastAvatar/random;
        // time: clock/day/passage/turns/anchor + narrative weekday; nsfw: cooldown/arousal/tier; lorebook: triggers/depth on entries).
        // All secondary time/nsfw/lorebook config zeroed on fresh group/0-session paths.
        final prevArousal = _nsfwService.arousalLevel;
        final prevFixation = _relationshipService.activeFixation;
        final prevFixationLife = _relationshipService.fixationLifespan;
        _needsSimEnabled = false;
        _enjoysLowHygiene = false;
        _needsSimulation.clearVector();
        _needsSimulation.resetBuffers();
        // v47: clear the 1:1 Pockets record too. A fresh chat re-seeds from the
        // card, and leaving the previous chat's record in the scalar meant they
        // walked into the new conversation still holding the last one's props.
        // Harmless while the record was memory-only; now that it is saved, the
        // bleed would be written to the new chat's row and become permanent.
        _pockets = null;
        _realismChatSwitch = false;
        _mood.reset();
        // Time reset via extracted service (keeps multiple reset blocks in sync).
        // See time_service.dart and "keep reset blocks" comments (now lists needs/chaos/relationship/expression/time/nsfw/lorebook_scanner + prompt_injection (stateless builders; no reset calls needed) + llm_eval_engine (stateless or prompt-only; no reset calls needed; incomplete zeroing... now complete (see CLAUDE.md)) + needs_impact_evaluator (stateless or prompt-only; no reset calls needed) + realism_evals (stateless or prompt-only; no reset calls needed) + objective_proposal (stateless or prompt-only; no reset calls needed) + journal_maintenance (stateless or prompt-only; no reset calls needed)). (cross-ref setActiveCharacter:1572 etc)
        _timeService.resetForFreshChat();
        // Chaos reset via extracted service (keeps multiple reset blocks in sync).
        // See chaos_mode_service.dart and "keep reset blocks" comments (now lists needs/chaos/relationship/expression/time/nsfw/lorebook_scanner + prompt_injection (stateless builders; no reset calls needed) + llm_eval_engine (stateless or prompt-only; no reset calls needed; incomplete zeroing... now complete (see CLAUDE.md)) + needs_impact_evaluator (stateless or prompt-only; no reset calls needed) + realism_evals (stateless or prompt-only; no reset calls needed) + objective_proposal (stateless or prompt-only; no reset calls needed) + journal_maintenance (stateless or prompt-only; no reset calls needed)). (cross-ref setActiveCharacter:1572 etc)
        _chaosModeService.resetForFreshChat();
        _s.media().resetForFreshChat();
        // Nsfw reset via extracted service (keeps multiple reset blocks in sync).
        // See nsfw_service.dart and "keep reset blocks" comments (now lists needs/chaos/relationship/expression/time/nsfw/lorebook_scanner + prompt_injection (stateless builders; no reset calls needed) + llm_eval_engine (stateless or prompt-only; no reset calls needed; incomplete zeroing... now complete (see CLAUDE.md)) + needs_impact_evaluator (stateless or prompt-only; no reset calls needed) + realism_evals (stateless or prompt-only; no reset calls needed) + objective_proposal (stateless or prompt-only; no reset calls needed) + journal_maintenance (stateless or prompt-only; no reset calls needed)). (cross-ref setActiveCharacter:1572 etc)
        _nsfwService.resetForFreshChat();
        // Lorebook already reset above via _lorebookScanner (keeps blocks in sync; see cross-ref comment at top of this reset).
        _relationshipService.resetForFreshChat();
        _expressionService.resetForFreshChat();
        _cast.baseline.greetingEvalPending = false;
        _cast.baseline.isProcessingGreeting = false;
        _scope.setPending(null);
        _s.objectives().resetForChatSwitch();
        _isGrowthPassRunning =
            false; // explicit growth-pass flag zero on setActiveCharacter main path (transient guard; keep reset blocks in sync — growth cache itself is session-scoped and re-cached by _growthDesk.refreshCache in _loadLastSession)
        debugPrint(
          '[Chat] setActiveCharacter: Reset realism state (baseline + runtime transients cleared; was: arousal=$prevArousal, fixation=$prevFixation/$prevFixationLife)',
        );

        await _store.loader.loadLastSession();

        // Message 0 needs their wardrobe too. AFTER the load, so a restored
        // session's own record always wins — this only fills a gap. With no
        // prior session there is nothing to load and this is the only thing
        // standing between an authored wardrobe and a sidebar that draws
        // nothing until the user's first message. See seedPocketsFromCards.
        _s.graph().seedPocketsFromCards();

        // If no session loaded, start fresh
        if (_session.messages.isEmpty) {
          // #328: a never-opened character has no row to restore a persona
          // from, so _loadLastSession's _activateSessionPersona never ran and
          // the PREVIOUS chat's in-chat persona was still live — the greeting
          // resolved {{user}} as them and the _saveChat below bound the new
          // session to them. A fresh chat starts as the default, same as
          // startNewChat. Done before the greeting is built so the macro sees
          // it too. `_session.currentSessionId == null` is load-bearing: a stored
          // zero-message chat also lands here, and it keeps its own persona.
          if (_session.currentSessionId == null) {
            await _s.personas.setActivePersona(_s.personas.defaultPersonaId);
          }
          // Seed Realism Engine state from V2.5 card extensions (new conversations only)
          if (_session.activeCharacter!.frontPorchExtensions != null) {
            final ext = _session.activeCharacter!.frontPorchExtensions!;
            // Global "Enable Realism Mode" default is an OR override (not a gate
            // like passage-of-time): its whole purpose is to force realism ON for
            // imported cards (Chub/V2 PNG/BYAF) that carry no realism setup, so
            // the engine reads the room + generates baselines without the user
            // editing every card. Defaults false, so card behavior is unchanged
            // until the user opts in globally.
            _realismChatSwitch =
                ext.realismEnabled || _s.storage.realismSettings.realismDefault;
            // Card-seed path (rec 1 from PR #47): seedFromCardV2OrExt is plain .clamp only,
            // because V2.5 cards + creator UI author shortTermBond/longTermBond on the *current*
            // ±300 scale (see models/character_card.dart:31-32 + FrontPorchExtensions). The old
            // legacy ±150→×2 era migration doubled authored values here (55 → 110) and — worse —
            // re-doubled live session bonds ≤ 150 on every _loadLastSession→save cycle; the whole
            // migration surface was deleted 2026-07-27 (see era-heuristic warning atop
            // relationship_service.dart). Session loads now pass raw values everywhere.
            _relationshipService.seedFromCardV2OrExt(
              shortTermBond: ext.shortTermBond,
              longTermBond: ext.longTermBond,
              trustLevel: ext.trustLevel,
            );
            // Time seed via extracted service (keeps reset/seed blocks in sync with startNewChat etc).
            // Global ceiling applied before passing (see time_service.seed doc).
            _timeService.seedFromV2OrExt(
              dayCount: ext.dayCount.clamp(1, 9999),
              timeOfDay: ext.timeOfDay,
              storyStartDate: ext.storyStartDate,
              storyStartTime: ext.storyStartTime,
            );
            _s.graph().applySeededPassageOfTime();
            _mood.seed(ext.characterEmotion, ext.emotionIntensity);
            // The card says how a new chat starts its Afterglow; the chat
            // keeps its own switch from here on.
            _nsfwService.seedFromV2OrExt(
              nsfwCooldownEnabled: ext.afterglowEnabled,
            );
            _chaosModeService.seedFromGroupOrExt(
              // OR-override: the card asks, or the global default does.
              ext.chaosModeEnabled ||
                  _s.storage.realismSettings.chaosModeDefault,
              false,
            );
            // The Porch Life Needs switch decides for a card that says
            // nothing (imported Chub/SillyTavern cards) and can veto a card
            // that asks. A card's explicit false still wins.
            _needsSimEnabled = _s.needsPass().seedNeedsSim(ext.needsSimChoice);
            // Objectives seed from the GLOBAL switch only — deliberately no card
            // extension. A per-character default would change the card JSON
            // shape, which ripples to The Stoop and every external reader, and
            // nobody asked for objectives to be a per-character trait. The
            // per-chat store is sessions.objectives_enabled.
            _objectivesEnabled = _s.storage.realismSettings.objectivesEnabled;
            _enjoysLowHygiene = ext.enjoysLowHygiene;
            if (_needsSimEnabled) {
              // Brand new conversation for this character (no prior session loaded):
              // seed from card baselines (falls back to needDefaults when the card has no baselines).
              _needsSimulation.initializeFreshWithDefaults(
                NeedsSimulation.baselinesFromExtensions(ext),
              );
            } else {
              _needsSimulation.clearVector();
            }
            // Tiers maintained by service after seedFromCardV2OrExt (or V2OrExt for other leaves).
            debugPrint(
              '[Chat] V2.5 extensions seeded: realism=$_realismChatSwitch, '
              'bond=${_relationshipService.affectionScore}, trust=${_relationshipService.trustLevel}, day=${_timeService.dayCount}, time=${_timeService.timeOfDay}',
            );

            _s.objectives().writer.importAuthoredTask(ext);
          } else if (_session.currentSessionId == null) {
            // A PLAIN IMPORTED CARD — no `frontPorchExtensions` at all, which is
            // every PNG downloaded from Chub or exported from another app — and
            // no prior session. Until 2026-08-08 it got NOTHING from this block,
            // because the guard above is `!= null` while the comment inside it
            // says the OR-override exists "to force realism ON for imported cards
            // (Chub/V2 PNG/BYAF) that carry no realism setup". The guard excluded
            // exactly the population the code was written to serve: turn a global
            // on, open a card you just downloaded, nothing happens.
            //
            // Only the GLOBAL feature switches are applied — the pure
            // OR-overrides plus Needs, which a silent card leaves to the
            // Porch Life switch. Deliberately NOT the numeric seeds (bond,
            // trust, day, needs baselines): a plain card has no opinion about
            // those, and the defaults are already in place.
            //
            // `_session.currentSessionId == null` is the load-bearing part, and the first
            // draft of this fix got it wrong by reusing a default-constructed
            // extensions object for the whole block above. `_session.messages.isEmpty` is
            // NOT "no session was loaded" — a session row with zero messages
            // still hydrates every stored scalar, so that version let card
            // defaults overwrite a saved chat's bond of 77 with 0. Seven existing
            // tests caught it, and they were right; this branch runs only when
            // `_loadLastSession` genuinely found nothing.
            _realismChatSwitch =
                _realismChatSwitch || _s.storage.realismSettings.realismDefault;
            // A card that says nothing starts Afterglow on.
            _nsfwService.seedFromV2OrExt(nsfwCooldownEnabled: true);
            _chaosModeService.seedFromGroupOrExt(
              _s.storage.realismSettings.chaosModeDefault,
              false,
            );
            _needsSimEnabled = _s.needsPass().seedNeedsSim(null);
            if (_needsSimEnabled) _needsSimulation.initializeFresh();
            _objectivesEnabled = _s.storage.realismSettings.objectivesEnabled;
          }

          final opening = _session.activeCharacter!.allGreetings;
          if (opening.isNotEmpty) {
            _session.messages.add(
              ChatMessage(
                text: _cast.greetings.buildFirstMessage(
                  _session.activeCharacter!,
                  greetingText: opening.first,
                ),
                sender: _session.activeCharacter!.name,
                isUser: false,
              ),
            );
            // Scan first message for lore (thin delegation to extracted scanner).
            _lorebookScanner.scanLatest();
            _clockWriter.writeSlotClock(
              _session.messages.isEmpty ? null : _session.messages.first,
              kind: SlotClockWrite.seed,
            );
            if (_session.activeCharacter!.firstMessage.trim().isEmpty) {
              await _cast.greetings.applyGreetingOpeningSeed(
                card: _session.activeCharacter!,
                index: 0,
              );
            }
          }
          // Note: for the direct 0-session setActiveCharacter path (fresh import via home grid <=1 session),
          // _greetingEvalPending is left false here. The post-greeting baseline eval is scheduled only
          // in startNewChat (for explicit New Chat flows). Fresh-import cards rely on the retro path
          // in setRealismEnabled (or manual enable after first messages) when _realismDance.hasBaseline==false.
          // This matches pre-existing behavior for the import entry point; the critical bleed fix
          // ensures the baseline check is now correctly false for no-ext cards.
          // Save the initial message session
          _session.currentSessionId = DateTime.now().millisecondsSinceEpoch
              .toString();
          // Seed chat worlds from the character's attached worlds (Living
          // Worlds) — a paired world's climate/setting applies from turn one.
          await _store.forker.seedChatWorldsForNewSession();
          await _s.media().seedWikiForNewSession();
          await _store.save();
          _s.objectives().resetForChatSwitch();
          _store.isSummaryGenerating =
              false; // secondary zero in empty subpath of setActiveCharacter (incomplete zeroing... now complete (see CLAUDE.md))
          _isGrowthPassRunning =
              false; // growth-pass flag zero in empty subpath of setActiveCharacter (transient guard; keep reset blocks in sync)
          await _growthDesk
              .refreshCache(); // fresh session id → scope the injection cache to it
        }
        // Load active objectives for this session (must be after _loadLastSession
        // so _session.currentSessionId is set)
        // Awaited (was fire-and-forget); root fix for post-dispose notify races in tests + rapid switches. Central _disposed + notifyListeners override (rec 2) now protects residual unawaited/microtask paths + any other notify-after-async in god/services (see _disposed decl and the overrides at end of class).
        await _s.objectives().loadActiveObjectives();
      }
    } finally {
      if (ownedLoad) _door.cover.endSessionLoad();
    }
  }
}
