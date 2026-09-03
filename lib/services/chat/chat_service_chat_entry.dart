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

/// Chat-entry point — setActiveCharacter (open/seed a 1:1 chat). Extracted verbatim (zero behaviour change) to shrink the god file.
extension ChatServiceChatEntry on ChatService {
  /// Light in-place refresh after the active/focused character's card was
  /// edited: swap the reference (matched by dbId, so RENAMES stay light) and
  /// repaint — WITHOUT the full chat-entry dance. Never cancels an in-flight
  /// generation, never reloads the session, and is group-safe: editing a
  /// focused group member updates that member's reference instead of tearing
  /// the group down. (The deleted EditCharacterDialog called
  /// setActiveCharacter for this, which cancels generation, full-reloads on
  /// rename, and leaves the group — the exact failure modes this exists to
  /// avoid.)
  void refreshActiveCharacterCard(CharacterCard card) {
    if (_activeGroup != null) {
      // identical() first: group member cards are library-decoupled copies
      // whose dbId is often null — the editor mutates the same instance, so
      // identity is the reliable key; dbId covers reloaded-copy callers.
      final i = _groupCharacters.indexWhere(
        (c) => identical(c, card) || (c.dbId != null && c.dbId == card.dbId),
      );
      if (i != -1) {
        _groupCharacters[i] = card;
        if (_activeCharacter?.dbId == card.dbId) {
          _activeCharacter = card;
        }
      }
    } else if (_activeCharacter != null &&
        (_activeCharacter!.dbId == null ||
            _activeCharacter!.dbId == card.dbId)) {
      _activeCharacter = card;
    }
    refreshEnjoysLowHygieneFromActiveCharacter();
    unawaited(_ensureBirthdayState());
    notifyListeners();
  }

  /// Raise the ChatPage overlay before any await so a navigate-first open
  /// never paints the previous transcript. No-op when a caller (home tap,
  /// startFreshChatWith) already owns the flag for a multi-step load.
  void beginSessionLoad() {
    if (_isLoadingSession) return;
    _isLoadingSession = true;
    notifyListeners();
  }

  /// Drop the overlay. Safe to call when the flag is already false.
  void endSessionLoad() {
    if (!_isLoadingSession) return;
    _isLoadingSession = false;
    notifyListeners();
  }

  /// Wait (bounded) for a finishing turn's settling section to complete.
  ///
  /// [_cancelAndWaitForGeneration] stops the STREAM, but the post-gen work —
  /// evals, chip attach, `_saveChat` — runs after `_isGenerating` drops.
  /// Entering a session/character/group mid-settle rehydrates from rows the
  /// persist hasn't written yet (the reloaded reply came back chip-less, so
  /// deleting it refunded nothing — the app_smoke Windows CI catch) while
  /// the finalization keeps writing onto the REPLACED list. Bounded so a
  /// wedged backend degrades to the old racy behaviour instead of hanging
  /// the UI (`_cancelAndWaitForGeneration`'s doc forbids broadening its own
  /// unbounded spin for exactly that reason).
  Future<void> _waitForTurnToSettle() async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (_isTurnBusy && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    // Persist is not `_isTurnBusy`: `_isPostGenerating` drops in
    // `_generateResponse`'s finally, and fire-and-forget `_saveChat()`
    // calls can still be on `_saveChain`. A reload that does not wait
    // here hydrates the pre-turn row and a later write can then persist
    // that shorter list.
    await _saveChain;
  }

  Future<void> setActiveCharacter(CharacterCard? character) async {
    // Overlay on BEFORE cancel/settle/flush so ChatPage can cover the switch
    // the instant home pushes the route. A caller that already called
    // beginSessionLoad keeps the flag across a follow-up loadSession.
    final ownedLoad = !_isLoadingSession;
    beginSessionLoad();
    try {
      // Cancel any in-flight generation before switching context, then wait
      // out the settling tail so the reload below reads fully-persisted rows.
      await _cancelAndWaitForGeneration();
      await _waitForTurnToSettle();
      _generationEpoch++;

      // Same library card: match by dbId when both sides have one (renames
      // stay light). A grid card with a missing dbId used to fail
      // `dbId == dbId` (uuid != null), take the slow path, assign the
      // dbId-less card, skip `_loadLastSession`, and seed a NEW greeting
      // session — the last exchange (and sometimes the whole chat) vanished.
      final sameCharacter =
          character != null &&
          _activeCharacter != null &&
          ((character.dbId != null &&
                  _activeCharacter!.dbId != null &&
                  character.dbId == _activeCharacter!.dbId) ||
              (character.name == _activeCharacter!.name &&
                  (character.dbId == null || _activeCharacter!.dbId == null)));
      if (sameCharacter && _messages.isNotEmpty) {
        // Keep the dbId-bearing instance when the grid card is missing one
        // so a later save still stamps sessions.character_id.
        if (character.dbId != null) {
          _activeCharacter = character;
        }
        notifyListeners();
        return;
      }

      // About to throw the live list away. Write it first so a slow-path
      // reload cannot hydrate a row that is still missing this turn.
      await flushPendingSaves();
      // Detach before swapping the owner. Anything that saves between
      // `_activeCharacter =` and `_loadLastSession` used to rebind this
      // row to the incoming card (history/E2E then loadSession-ed Nightowl).
      _currentSessionId = null;

      // Reset AFK idle state when switching to a different chat
      _cancelIdleTimer();
      _hasCompletedExchange = false;

      // Clear group mode when switching to 1:1 AND reset author note for new session context
      _authorNote = '';
      _authorNoteStrength = 4;
      _groupManager?.leaveGroup();
      _groupManager = null;
      _groupRealism = {};
      _groupAuthorNotes = {};
      _groupAuthorNoteStrengths = {};
      _groupCharacterSystemPrompts = {};
      _groupRagEnabled = true;
      _groupRetrievalCount = 4;
      _groupMemoryBudgetPercent = 10.0;
      _groupCharacterRAGPriorities = {};

      // Reset Scene Guests for the new 1:1 context (repopulated by _loadLastSession
      // if the loaded session persisted any). _sceneGuest.pendingDeparture is one-shot.
      _sceneGuest.ids.clear();
      _sceneGuest.cards.clear();
      _sceneGuest.pendingDeparture = null;
      _sceneGuest.pendingPickerFilter = null;
      _resetGuestActivityState();
      // Phase 2 cast detection: reset the scan cadence + pending/debounce state
      // for the new 1:1 context (kept in sync with the Scene Guest clears).
      _sceneGuest.turnsSinceCastScan = 0;
      _sceneGuest.pendingDetection = null;
      _sceneGuest.offeredOrIgnoredNames.clear();

      _activeCharacter = character;

      // Auto-start the local Kobold backend (native or a .kcpps preset) when
      // entering a chat so the user never has to manually start it just to talk.
      // Gated by autostartOnChatOpen — when off, the user must start manually.
      if (_storageService.autostartOnChatOpen) {
        _llmProvider?.ensureManagedBackendIsRunning();
      }

      // If extensions are missing (e.g., app was restarted after DB load that
      // didn't carry over PNG extensions), reload the PNG to get V2.5 card data.
      if (_activeCharacter != null &&
          _activeCharacter!.frontPorchExtensions == null &&
          _activeCharacter!.imagePath != null) {
        try {
          final v2Service = V2CardService();
          final reloaded = await v2Service.readCard(
            _activeCharacter!.imagePath!,
          );
          if (reloaded != null && reloaded.frontPorchExtensions != null) {
            _activeCharacter!.frontPorchExtensions =
                reloaded.frontPorchExtensions;
            _activeCharacter!.rawExtensions = reloaded.rawExtensions;
            debugPrint(
              '[ChatService] Reloaded frontPorchExtensions from PNG for ${_activeCharacter!.name}',
            );
          }
        } catch (e) {
          debugPrint('[ChatService] Failed to reload PNG extensions: $e');
        }
      }

      // Note: growth rings are cached inside _loadLastSession() (which runs
      // below) so they are scoped to the session, not the character.
      debugPrint(
        '[ChatService] 🟡 setActiveCharacter: clearing messages '
        '(had ${_messages.length}) for ${character?.name}, loading session...',
      );
      await _invalidateGreetingEval();
      _messages.clear();
      _greetingIndex = 0;
      _history.reset();
      _currentSessionId = null;
      _clearTodayPointer();
      _summary = '';
      _summaryLastIndex = 0;
      _selectedLooks
          .clear(); // fresh 1:1: drop prior chat's per-chat look selection (keep reset blocks in sync)
      _summaryPaused =
          false; // explicit secondary zero for _summaryPaused (symmetric to _isSummaryGenerating; incomplete zeroing... now complete (see CLAUDE.md); see keep-sync + journal_maintenance)
      _isSummaryGenerating =
          false; // explicit secondary zero on setActiveCharacter (incomplete zeroing of secondary config on ... now complete; see keep-sync + journal_maintenance)
      // Clear fork/branch state so it doesn't leak from previous character
      // into a fresh character's first session (see startNewChat for details).
      _parentSessionId = null;
      _forkIndex = null;

      if (_activeCharacter != null) {
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
        // card, and leaving the previous chat's record in the scalar meant she
        // walked into the new conversation still holding the last one's props.
        // Harmless while the record was memory-only; now that it is saved, the
        // bleed would be written to the new chat's row and become permanent.
        _pockets = null;
        _realismEnabled = false;
        _characterEmotion = '';
        _emotionIntensity = '';
        // Time reset via extracted service (keeps multiple reset blocks in sync).
        // See time_service.dart and "keep reset blocks" comments (now lists needs/chaos/relationship/expression/time/nsfw/lorebook_scanner + prompt_injection (stateless builders; no reset calls needed) + llm_eval_engine (stateless or prompt-only; no reset calls needed; incomplete zeroing... now complete (see CLAUDE.md)) + needs_impact_evaluator (stateless or prompt-only; no reset calls needed) + realism_evals (stateless or prompt-only; no reset calls needed) + objective_proposal (stateless or prompt-only; no reset calls needed) + journal_maintenance (stateless or prompt-only; no reset calls needed)). (cross-ref setActiveCharacter:1572 etc)
        _timeService.resetForFreshChat();
        // Chaos reset via extracted service (keeps multiple reset blocks in sync).
        // See chaos_mode_service.dart and "keep reset blocks" comments (now lists needs/chaos/relationship/expression/time/nsfw/lorebook_scanner + prompt_injection (stateless builders; no reset calls needed) + llm_eval_engine (stateless or prompt-only; no reset calls needed; incomplete zeroing... now complete (see CLAUDE.md)) + needs_impact_evaluator (stateless or prompt-only; no reset calls needed) + realism_evals (stateless or prompt-only; no reset calls needed) + objective_proposal (stateless or prompt-only; no reset calls needed) + journal_maintenance (stateless or prompt-only; no reset calls needed)). (cross-ref setActiveCharacter:1572 etc)
        _chaosModeService.resetForFreshChat();
        // Nsfw reset via extracted service (keeps multiple reset blocks in sync).
        // See nsfw_service.dart and "keep reset blocks" comments (now lists needs/chaos/relationship/expression/time/nsfw/lorebook_scanner + prompt_injection (stateless builders; no reset calls needed) + llm_eval_engine (stateless or prompt-only; no reset calls needed; incomplete zeroing... now complete (see CLAUDE.md)) + needs_impact_evaluator (stateless or prompt-only; no reset calls needed) + realism_evals (stateless or prompt-only; no reset calls needed) + objective_proposal (stateless or prompt-only; no reset calls needed) + journal_maintenance (stateless or prompt-only; no reset calls needed)). (cross-ref setActiveCharacter:1572 etc)
        _nsfwService.resetForFreshChat();
        // Lorebook already reset above via _lorebookScanner (keeps blocks in sync; see cross-ref comment at top of this reset).
        _relationshipService.resetForFreshChat();
        _expressionService.resetForFreshChat();
        _greetingEvalPending = false;
        _isProcessingGreeting = false;
        _pendingRealismMetadata = null;
        _activeObjectives = [];
        _messagesSinceLastCheck = 0;
        _isCheckingCompletion =
            false; // secondary objective flag zero on setActiveCharacter main path (incomplete zeroing hygiene; keep reset blocks)
        _isGrowthPassRunning =
            false; // explicit growth-pass flag zero on setActiveCharacter main path (transient guard; keep reset blocks in sync — growth cache itself is session-scoped and re-cached by _refreshGrowthCache in _loadLastSession)
        debugPrint(
          '[ChatService] setActiveCharacter: Reset realism state (baseline + runtime transients cleared; was: arousal=$prevArousal, fixation=$prevFixation/$prevFixationLife)',
        );

        // Try to load last session
        await _loadLastSession();

        // Message 0 needs her wardrobe too. AFTER the load, so a restored
        // session's own record always wins — this only fills a gap. With no
        // prior session there is nothing to load and this is the only thing
        // standing between an authored wardrobe and a sidebar that draws
        // nothing until the user's first message. See seedPocketsFromCards.
        seedPocketsFromCards();

        // If no session loaded, start fresh
        if (_messages.isEmpty) {
          // Seed Realism Engine state from V2.5 card extensions (new conversations only)
          if (_activeCharacter!.frontPorchExtensions != null) {
            final ext = _activeCharacter!.frontPorchExtensions!;
            // Global "Enable Realism Mode" default is an OR override (not a gate
            // like passage-of-time): its whole purpose is to force realism ON for
            // imported cards (Chub/V2 PNG/BYAF) that carry no realism setup, so
            // the engine reads the room + generates baselines without the user
            // editing every card. Defaults false, so card behavior is unchanged
            // until the user opts in globally.
            _realismEnabled =
                ext.realismEnabled ||
                _storageService.realismSettings.realismDefault;
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
              passageOfTimeEnabled:
                  ext.passageOfTimeEnabled &&
                  _storageService.realismSettings.passageOfTimeDefault,
            );
            _characterEmotion = ext.characterEmotion;
            _emotionIntensity = ext.emotionIntensity;
            _nsfwService.seedFromV2OrExt(
              // Same OR-override rationale as realism above: a globally-enabled
              // NSFW cooldown applies to imported cards too.
              nsfwCooldownEnabled:
                  ext.nsfwCooldownEnabled ||
                  _storageService.realismSettings.nsfwCooldownDefault,
            );
            _chaosModeService.seedFromGroupOrExt(
              // OR-override: the card asks, or the global default does.
              ext.chaosModeEnabled ||
                  _storageService.realismSettings.chaosModeDefault,
              false,
            );
            // AND-gated by the global Needs switch (Porch Life tab): the card
            // asks, the global setting can veto. Default true = no change.
            _needsSimEnabled =
                ext.needsSimEnabled &&
                _storageService.realismSettings.needsSimDefault;
            // Objectives seed from the GLOBAL switch only — deliberately no card
            // extension. A per-character default would change the card JSON
            // shape, which ripples to The Stoop and every external reader, and
            // nobody asked for objectives to be a per-character trait. The
            // per-chat store is sessions.objectives_enabled.
            _objectivesEnabled =
                _storageService.realismSettings.objectivesEnabled;
            _enjoysLowHygiene = ext.enjoysLowHygiene;
            if (_needsSimEnabled) {
              // Brand new conversation for this character (no prior session loaded):
              // seed from card baselines (falls back to needDefaults when the card has no baselines).
              _needsSimulation.initializeFreshWithDefaults({
                'hunger': ext.needsBaselineHunger,
                'bladder': ext.needsBaselineBladder,
                'energy': ext.needsBaselineEnergy,
                'social': ext.needsBaselineSocial,
                'fun': ext.needsBaselineFun,
                'hygiene': ext.needsBaselineHygiene,
                'comfort': ext.needsBaselineComfort,
              });
            } else {
              _needsSimulation.clearVector();
            }
            // Tiers maintained by service after seedFromCardV2OrExt (or V2OrExt for other leaves).
            debugPrint(
              '[ChatService] V2.5 extensions seeded: realism=$_realismEnabled, '
              'bond=${_relationshipService.affectionScore}, trust=${_relationshipService.trustLevel}, day=${_timeService.dayCount}, time=${_timeService.timeOfDay}',
            );

            _importAuthoredTask(ext);
          } else if (_currentSessionId == null) {
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
            // OR-overrides plus the Needs AND-gate. Deliberately NOT the numeric
            // seeds (bond, trust, day, needs baselines): a plain card has no
            // opinion about those, and the defaults are already in place.
            //
            // `_currentSessionId == null` is the load-bearing part, and the first
            // draft of this fix got it wrong by reusing a default-constructed
            // extensions object for the whole block above. `_messages.isEmpty` is
            // NOT "no session was loaded" — a session row with zero messages
            // still hydrates every stored scalar, so that version let card
            // defaults overwrite a saved chat's bond of 77 with 0. Seven existing
            // tests caught it, and they were right; this branch runs only when
            // `_loadLastSession` genuinely found nothing.
            _realismEnabled =
                _realismEnabled ||
                _storageService.realismSettings.realismDefault;
            _nsfwService.seedFromV2OrExt(
              nsfwCooldownEnabled:
                  _nsfwService.nsfwCooldownEnabled ||
                  _storageService.realismSettings.nsfwCooldownDefault,
            );
            _chaosModeService.seedFromGroupOrExt(
              _storageService.realismSettings.chaosModeDefault,
              false,
            );
            _needsSimEnabled =
                _needsSimEnabled &&
                _storageService.realismSettings.needsSimDefault;
            _objectivesEnabled =
                _storageService.realismSettings.objectivesEnabled;
          }

          final opening = _activeCharacter!.allGreetings;
          if (opening.isNotEmpty) {
            _messages.add(
              ChatMessage(
                text: _buildFirstMessage(
                  _activeCharacter!,
                  greetingText: opening.first,
                ),
                sender: _activeCharacter!.name,
                isUser: false,
              ),
            );
            // Scan first message for lore (thin delegation to extracted scanner).
            _lorebookScanner.scanLatest();
            if (_activeCharacter!.firstMessage.trim().isEmpty) {
              await _applyGreetingOpeningSeed(
                card: _activeCharacter!,
                index: 0,
              );
            }
          }
          // Note: for the direct 0-session setActiveCharacter path (fresh import via home grid <=1 session),
          // _greetingEvalPending is left false here. The post-greeting baseline eval is scheduled only
          // in startNewChat (for explicit New Chat flows). Fresh-import cards rely on the retro path
          // in setRealismEnabled (or manual enable after first messages) when _hasRealismBaseline==false.
          // This matches pre-existing behavior for the import entry point; the critical bleed fix
          // ensures the baseline check is now correctly false for no-ext cards.
          // Save the initial message session
          _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
          // Seed chat worlds from the character's attached worlds (Living
          // Worlds) — a paired world's climate/setting applies from turn one.
          await _seedChatWorldsForNewSession();
          await _saveChat();
          _activeObjectives = [];
          _messagesSinceLastCheck = 0;
          _isCheckingCompletion =
              false; // zero secondary in empty session subpath of setActiveCharacter (per incomplete zeroing fix)
          _isSummaryGenerating =
              false; // secondary zero in empty subpath of setActiveCharacter (incomplete zeroing... now complete (see CLAUDE.md))
          _isGrowthPassRunning =
              false; // growth-pass flag zero in empty subpath of setActiveCharacter (transient guard; keep reset blocks in sync)
          await _refreshGrowthCache(); // fresh session id → scope the injection cache to it
        }
        // Load active objectives for this session (must be after _loadLastSession
        // so _currentSessionId is set)
        await _loadActiveObjectives(); // Awaited (was fire-and-forget); root fix for post-dispose notify races in tests + rapid switches. Central _disposed + notifyListeners override (rec 2) now protects residual unawaited/microtask paths + any other notify-after-async in god/services (see _disposed decl, overrides at end of class, and cleaned per-site guard in _loadActiveObjectives).
      }
    } finally {
      if (ownedLoad) endSessionLoad();
    }
  }
}
