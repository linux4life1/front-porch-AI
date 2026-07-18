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
  Future<void> setActiveCharacter(CharacterCard? character) async {
    // Cancel any in-flight generation before switching context
    await _cancelAndWaitForGeneration();
    _generationEpoch++;

    // If same character is already active and has messages, just refresh
    // the character reference (in case fields were edited) but skip the
    // expensive full re-initialization (message clearing, session reload).
    if (_activeCharacter?.name == character?.name &&
        _activeCharacter?.dbId == character?.dbId &&
        _messages.isNotEmpty) {
      _activeCharacter = character;
      notifyListeners();
      return;
    }

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
    _groupRetrievalCount = 8;
    _groupMemoryBudgetPercent = 10.0;
    _groupCharacterRAGPriorities = {};

    // Reset Scene Guests for the new 1:1 context (repopulated by _loadLastSession
    // if the loaded session persisted any). _pendingGuestDeparture is one-shot.
    _sceneGuestIds.clear();
    _sceneGuestCards.clear();
    _pendingGuestDeparture = null;
    _pendingGuestPickerFilter = null;
    _resetGuestActivityState();
    // Phase 2 cast detection: reset the scan cadence + pending/debounce state
    // for the new 1:1 context (kept in sync with the Scene Guest clears).
    _userMessagesSinceLastCastScan = 0;
    _pendingGuestDetection = null;
    _offeredOrIgnoredGuestNames.clear();

    _activeCharacter = character;

    // Auto-start the local Kobold backend (native or a .kcpps preset) when
    // entering a chat so the user never has to manually start it just to talk.
    _llmProvider?.ensureManagedBackendIsRunning();

    // If extensions are missing (e.g., app was restarted after DB load that
    // didn't carry over PNG extensions), reload the PNG to get V2.5 card data.
    if (_activeCharacter != null &&
        _activeCharacter!.frontPorchExtensions == null &&
        _activeCharacter!.imagePath != null) {
      try {
        final v2Service = V2CardService();
        final reloaded = await v2Service.readCard(_activeCharacter!.imagePath!);
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
    _messages.clear();
    _currentSessionId = null;
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
    _isLoadingSession = true;
    notifyListeners();

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
      _moodDecayCounter = 0;
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
          // Card-seed bypass (rec 1 from PR #47): use seedFromCardV2OrExt (plain .clamp only,
          // no _migrate*) because V2.5 cards + creator UI author shortTermBond/longTermBond on the
          // *current* ±300 scale (see models/character_card.dart:31-32 + FrontPorchExtensions).
          // Legacy *2 migration must stay *only* on _loadLastSession loadScalars + migrate* wrappers
          // + applyLegacyShortTermMigrationIfNeeded paths (and the public migrate surface).
          // This was the root cause of bond-doubling (e.g. authored 55 -> 110) on every fresh 1:1
          // card import / 0-session setActive / startNew. 1:1 only; group per-speaker paths were
          // never affected (used loadRelationshipScalarsForSpeaker etc). See relationship_service.dart
          // seedFromCardV2OrExt + god keep-sync comments (full list) + cross-ref setActiveCharacter:1572.
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
          _chaosModeService.seedFromGroupOrExt(ext.chaosModeEnabled, false);
          _needsSimEnabled = ext.needsSimEnabled;
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

          // Seed initial quest/task as a primary objective
          if (ext.currentTask.isNotEmpty) {
            // Defer so the session ID is ready before the DB write
            Future.microtask(() async {
              await setObjective(ext.currentTask, isPrimary: true);
              debugPrint(
                '[ChatService] V2.5 seeded initial task: ${ext.currentTask}',
              );
            });
          }
        }

        if (_activeCharacter!.firstMessage.isNotEmpty) {
          _messages.add(
            ChatMessage(
              text: _buildFirstMessage(_activeCharacter!),
              sender: _activeCharacter!.name,
              isUser: false,
            ),
          );
          // Scan first message for lore (thin delegation to extracted scanner).
          _lorebookScanner.scanLatest();
        }
        // Note: for the direct 0-session setActiveCharacter path (fresh import via home grid <=1 session),
        // _greetingEvalPending is left false here. The post-greeting baseline eval is scheduled only
        // in startNewChat (for explicit New Chat flows). Fresh-import cards rely on the retro path
        // in setRealismEnabled (or manual enable after first messages) when _hasRealismBaseline==false.
        // This matches pre-existing behavior for the import entry point; the critical bleed fix
        // ensures the baseline check is now correctly false for no-ext cards.
        // Save the initial message session
        _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
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
    _isLoadingSession = false;
    notifyListeners();
  }
}
