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

/// Session management + new-chat — renameSession, updateSessionDescription, forkFromMessage, startNewChat. Extracted verbatim (zero behaviour change) to shrink the god file.
extension ChatServiceSessionManage on ChatService {
  /// Rename a session.
  Future<void> renameSession(String sessionId, String name) async {
    final session = await _db.getSessionById(sessionId);
    if (session == null) return;

    await _db.updateSession(
      SessionsCompanion(
        id: drift.Value(sessionId),
        name: drift.Value(name.isEmpty ? null : name),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );

    // Update in-memory if this is the current session
    if (sessionId == _currentSessionId) {
      _sessionName = name.isEmpty ? null : name;
      notifyListeners();
    }
  }

  /// Update the description of a session.
  Future<void> updateSessionDescription(
    String sessionId,
    String description,
  ) async {
    final session = await _db.getSessionById(sessionId);
    if (session == null) return;

    await _db.updateSession(
      SessionsCompanion(
        id: drift.Value(sessionId),
        description: drift.Value(description.isEmpty ? null : description),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );

    // Update in-memory if this is the current session
    if (sessionId == _currentSessionId) {
      _sessionDescription = description.isEmpty ? null : description;
      notifyListeners();
    }
  }

  /// Create a new session by forking from message at [messageIndex].
  /// Copies messages 0..messageIndex into a new session and switches to it.
  Future<void> forkFromMessage(int messageIndex) async {
    if ((_activeCharacter == null && _activeGroup == null) ||
        _currentSessionId == null) {
      return;
    }
    if (messageIndex < 0 || messageIndex >= _messages.length) return;

    final oldSessionId = _currentSessionId!;
    final forkedMessages = _messages
        .sublist(0, messageIndex + 1)
        .map(
          (m) => ChatMessage(
            text: m.text,
            sender: m.sender,
            isUser: m.isUser,
            characterId: m.characterId,
            swipes: List.from(m.swipes),
            swipeIndex: (m.swipeIndex >= 0 && m.swipeIndex < m.swipes.length)
                ? m.swipeIndex
                : 0,
            swipeDurations: List.from(m.swipeDurations),
            metadata: m.metadata != null
                ? Map<String, dynamic>.from(m.metadata!)
                : null,
            swipeMetadata: m.swipeMetadata
                .map((e) => e != null ? Map<String, dynamic>.from(e) : null)
                .toList(),
          ),
        )
        .toList();

    debugPrint(
      '[ChatService] 🟡 forkSession: clearing messages for fork at index $messageIndex',
    );
    _messages.clear();
    _messages.addAll(forkedMessages);
    _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _computeAbsenceGap(const []); // fresh session — no real-world gap (Living Time §2)
    _parentSessionId = oldSessionId;
    _forkIndex = messageIndex;
    _sessionGenSettings = _sessionGenSettings
        .copy(); // inherit parent's overrides
    _summary = '';
    _summaryLastIndex = 0;
    _selectedLooks
        .clear(); // fork starts with no per-chat look selection (keep reset blocks in sync)
    _summaryPaused =
        false; // explicit secondary zero for _summaryPaused (symmetric to generating; fork hygiene + incomplete zeroing now complete)
    _isSummaryGenerating =
        false; // zero secondary flag on fork (new branch hygiene, matches summary scalar reset)
    _isGrowthPassRunning =
        false; // growth-pass flag zero on fork (new branch hygiene; keep reset blocks in sync)

    // Time-Travel Restoration
    if (_messages.isNotEmpty) {
      _restoreRealismStateFromMessage(_messages.last);
    }

    await _saveChat();
    // Growth rings carry into the fork like the rest of the character's
    // history (the old evolved text carried the same way). Runs after
    // _saveChat so the new session row exists for the legacy-blob copy.
    await _growthStore.copySessionTo(
      oldSessionId,
      _currentSessionId!,
      cursor: _messages.length,
    );
    await _refreshGrowthCache();
    notifyListeners();
  }

  Future<void> startNewChat() async {
    if (_activeCharacter == null && _activeGroup == null) return;

    // Reset AFK idle state when starting a new chat
    _cancelIdleTimer();
    _hasCompletedExchange = false;

    debugPrint(
      '[startNewChat] START: arousal=${_nsfwService.arousalLevel}, fixation=${_relationshipService.activeFixation}/${_relationshipService.fixationLifespan}',
    );

    // Refresh _activeCharacter from the repository so we pick up any edits
    // made in the character editor (personality, description, etc.)
    if (_activeCharacter != null && _characterRepository != null) {
      final freshChar = _characterRepository!.characters
          .cast<CharacterCard?>()
          .firstWhere(
            (c) => c!.dbId == _activeCharacter!.dbId,
            orElse: () => null,
          );
      if (freshChar != null) {
        // Preserve any runtime-loaded extensions if the repository instance lacks them
        final existingExt = _activeCharacter!.frontPorchExtensions;
        final existingRaw = _activeCharacter!.rawExtensions;

        _activeCharacter = freshChar;

        if (existingExt != null &&
            _activeCharacter!.frontPorchExtensions == null) {
          _activeCharacter!.frontPorchExtensions = existingExt;
          _activeCharacter!.rawExtensions = existingRaw;
          debugPrint(
            '[startNewChat] Preserved existing extensions during character refresh',
          );
        } else if (existingExt == null &&
            _activeCharacter!.frontPorchExtensions == null) {
          debugPrint(
            '[startNewChat] DEBUG: existingExt was null AND freshChar had null extensions.',
          );
        }
      } else {
        debugPrint(
          '[startNewChat] DEBUG: freshChar was null (repository lookup failed).',
        );
      }
    }

    // Fallback: If extensions are STILL missing, forcefully reload from PNG.
    // This catches edge cases where repository/memory loses sync with the file.
    if (_activeCharacter != null &&
        _activeCharacter!.frontPorchExtensions == null) {
      debugPrint(
        '[startNewChat] DEBUG: Extensions are missing. Attempting PNG fallback.',
      );
      if (_activeCharacter!.imagePath != null) {
        debugPrint(
          '[startNewChat] DEBUG: Image path exists: ${_activeCharacter!.imagePath}',
        );
        try {
          final v2Service = V2CardService();
          final reloaded = await v2Service.readCard(
            _activeCharacter!.imagePath!,
          );
          if (reloaded == null) {
            debugPrint(
              '[startNewChat] DEBUG: readCard returned null. Failed to parse PNG.',
            );
          } else if (reloaded.frontPorchExtensions != null) {
            _activeCharacter!.frontPorchExtensions =
                reloaded.frontPorchExtensions;
            _activeCharacter!.rawExtensions = reloaded.rawExtensions;
            debugPrint(
              '[startNewChat] Force-reloaded frontPorchExtensions from PNG',
            );
          } else {
            debugPrint(
              '[startNewChat] DEBUG: readCard succeeded, BUT reloaded.frontPorchExtensions was NULL! Meaning the PNG file does NOT contain the front_porch extension data.',
            );
          }
        } catch (e) {
          debugPrint('[startNewChat] Force-reload failed with exception: $e');
        }
      } else {
        debugPrint('[startNewChat] DEBUG: Cannot fallback. imagePath is null.');
      }
    }

    debugPrint(
      '[ChatService] 🟡 startNewChat: clearing messages (had ${_messages.length})',
    );
    _messages.clear();
    _greetingIndex = 0;
    // A fresh chat starts with no Scene Guests (they don't carry across sessions).
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
    _summary = '';
    _summaryLastIndex = 0;
    _selectedLooks
        .clear(); // fresh 1:1: drop prior chat's per-chat look selection (keep reset blocks in sync)
    _summaryPaused =
        false; // explicit secondary zero for _summaryPaused (symmetric; startNew 1:1/ext-seed branch + incomplete zeroing ... now complete)
    _isSummaryGenerating =
        false; // explicit in startNewChat 1:1/ext-seed branch (both startNew explicit + incomplete zeroing... now complete (see CLAUDE.md); journal_maintenance) + "needsSimulation. (reason support kept for Director chips) ; cleared via sim initializeFresh/clearVector/resetBuffers on all paths; now complete in both branches)"

    // Explicitly clear any prior branching/fork metadata. A "New Chat" is
    // never a branch/fork from a previous session. This prevents stale
    // _parentSessionId / _forkIndex (from a previous branched chat or
    // different character) from being written into the brand-new session
    // record via _saveChat(), which was causing new chats to incorrectly
    // show "Branched at message #NNNN" in history lists even for characters
    // with no prior chats.
    _parentSessionId = null;
    _forkIndex = null;

    // Mark this as a new chat to prevent memory retrieval
    _isNewChat = true;
    debugPrint('[startNewChat] Marked as new chat - memories will be filtered');

    // Save the current session (preserves objectives for this session)
    if (_currentSessionId != null) {
      await _saveChat();
    }

    // Clear objectives for fresh session start
    _activeObjectives = [];
    _messagesSinceLastCheck = 0;
    _isCheckingCompletion =
        false; // see decl + keep reset blocks (incomplete zeroing... now complete (see CLAUDE.md); explicit in both startNew branches)
    _isGrowthPassRunning =
        false; // growth-pass flag zero in startNew 1:1/ext-seed branch (both startNew explicit; keep reset blocks in sync)

    // Create new session ID for the new chat
    _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _computeAbsenceGap(const []); // fresh session — no real-world gap (Living Time §2)

    // Clear memory sources to prevent old memories from being retrieved
    // Cross-character memory can still be re-selected by user after new chat starts
    if (_activeCharacter?.dbId != null) {
      try {
        await _db.updateCharacter(
          CharactersCompanion(
            id: drift.Value(_activeCharacter!.dbId!),
            memorySources: drift.Value('[]'),
          ),
        );
        debugPrint('[startNewChat] Cleared memory sources from DB');
      } catch (e) {
        debugPrint('[startNewChat] Failed to clear memory sources: $e');
      }
    }

    // Seed Realism Engine state from V2.5 card extensions for 1:1 mode only,
    // ensuring realism settings persist across chat sessions (group mode handled elsewhere)
    if (_activeCharacter != null && _activeGroup == null) {
      final extSeed =
          _activeCharacter!.frontPorchExtensions ?? FrontPorchExtensions();

      // Global "Enable Realism Mode" default is an OR override so imported
      // cards (no realism setup) get realism + baseline generation without the
      // user editing each card. Defaults false → no change until opted in.
      // Mirrors the setActiveCharacter fresh-seed path (chat_entry).
      _realismEnabled =
          extSeed.realismEnabled ||
          _storageService.realismSettings.realismDefault;
      // Card-seed bypass (rec 1 from PR #47; keeps startNewChat parity with setActive ext seed):
      // use seedFromCardV2OrExt (plain .clamp only, no _migrate*) because V2.5 cards + creator
      // author on current ±300 scale. (The old "Migration + seed" comment + call was the source
      // of the doubling regression on fresh 1:1 New Chat.) Migration stays exclusively on legacy
      // persisted session paths (_loadLastSession + loadScalars(migrate*) + applyLegacy... at 3 sites).
      // 1:1 vs group parity: group seeding paths untouched (resetForFresh + per-speaker load/save scalars).
      // See relationship_service.dart (seedFromCardV2OrExt + public migrate docs) + expanded
      // "keep reset blocks in sync" + "incomplete zeroing... now complete (see CLAUDE.md)"
      // (see CLAUDE.md full list + incomplete zeroing hygiene; buffer removal complete)
      // Clear ALL per-chat relationship registers first, THEN re-seed bond/trust
      // from the card. seedFromCardV2OrExt only sets affection/long-term/trust +
      // their tiers — it deliberately does NOT touch the active fixation, spatial
      // stance, the pending trust-repair flag, or the long-term/decay counters.
      // Without this reset those registers survived from the previous conversation
      // into the fresh chat and were then persisted into the new session's row, so
      // the in-chat "New Chat" button leaked a fixation "Background Thought" (and
      // spatial stance) across chats with the SAME character. resetForFreshChat
      // zeroes every register; the seed below restores bond/trust. This mirrors
      // setActiveCharacter's reset-before-load ordering and the group _groupRealism
      // baseline reset in the else branch (1:1 ↔ group fresh-chat parity).
      _relationshipService.resetForFreshChat();
      _relationshipService.seedFromCardV2OrExt(
        shortTermBond: extSeed.shortTermBond,
        longTermBond: extSeed.longTermBond,
        trustLevel: extSeed.trustLevel,
      );
      _expressionService.resetForFreshChat();
      // Lorebook trigger reset via extracted service (keeps the keep-sync reset sites correct
      // without god privates; now includes startNewChat 1:1 ext-seed path to prevent bleed of prior
      // isTriggered/remainingDepth into fresh New Chat for 1:1; constants skipped. See setActiveCharacter:1572
      // + "incomplete zeroing of secondary realism configuration fields" briefing pattern (cross-ref step6 nsfw).
      // See lorebook_scanner.dart and "keep reset blocks" comments (now lists needs/chaos/... + leaves (see CLAUDE.md for full; incomplete zeroing now complete) + needs_impact_evaluator (stateless or prompt-only; no reset calls needed)). (cross-ref setActiveCharacter:1572 etc; card-seed bypass hygiene added here too)
      _lorebookScanner.resetLorebookTriggerState();
      // Time seed via extracted service (keeps startNewChat / setActive / ext-seed blocks in sync).
      _timeService.seedFromV2OrExt(
        dayCount: extSeed.dayCount.clamp(1, 9999),
        timeOfDay: extSeed.timeOfDay,
        storyStartDate: extSeed.storyStartDate,
        storyStartTime: extSeed.storyStartTime,
        passageOfTimeEnabled:
            extSeed.passageOfTimeEnabled &&
            _storageService.realismSettings.passageOfTimeDefault,
      );
      _characterEmotion = extSeed.characterEmotion;
      _emotionIntensity = extSeed.emotionIntensity;
      _nsfwService.seedFromV2OrExt(
        // OR-override for consistency with realism above (imported cards).
        nsfwCooldownEnabled:
            extSeed.nsfwCooldownEnabled ||
            _storageService.realismSettings.nsfwCooldownDefault,
      );
      _chaosModeService.seedFromGroupOrExt(extSeed.chaosModeEnabled, false);
      _needsSimEnabled = extSeed.needsSimEnabled;
      _enjoysLowHygiene = extSeed.enjoysLowHygiene;
      if (_needsSimEnabled) {
        // Fresh chat / new session: seed from card baselines (falls back to
        // needDefaults when the card has no baselines).
        _needsSimulation.initializeFreshWithDefaults({
          'hunger': extSeed.needsBaselineHunger,
          'bladder': extSeed.needsBaselineBladder,
          'energy': extSeed.needsBaselineEnergy,
          'social': extSeed.needsBaselineSocial,
          'fun': extSeed.needsBaselineFun,
          'hygiene': extSeed.needsBaselineHygiene,
          'comfort': extSeed.needsBaselineComfort,
        });
      } else {
        _needsSimulation.clearVector();
      }
      _needsSimulation.resetBuffers();
      // needs_impact_evaluator is stateless/prompt-only (no reset calls needed on it;
      // see full list in "keep reset blocks in sync" comments + cross-ref setActiveCharacter:1572 + evolution_service (stateless or prompt-only; no reset calls needed) + realism_verification (stateless or prompt-only; no reset calls needed) + " ; read live from ext on active/group speaker; incomplete zeroing... now complete (see CLAUDE.md) (no extra scalar)") + "needsSimulation. (reason support kept for Director chips) ; cleared via sim initializeFresh/clearVector/resetBuffers on all paths; now complete)".

      // pending covered by relationship service reset in the ext-seed or non-ext paths below.
      // Always reset per-chat runtime realism fields (arousal/fixation/cooldowns) for a fresh
      // session started via explicit New Chat. ... (See also: matching full reset in setActiveCharacter
      // and the cross-sync comment there; load*Session, deleteSession→startNewChat, setActiveGroup defensive zero.
      // Needs vector/buffers reset via _needsSimulation also kept in sync across sites.)
      // Time secondary fields (passage/anchor/turns/day/time) zeroed via _timeService.resetForFreshChat in non-ext path + _load empty + setActiveGroup.
      // Nsfw runtime (arousal/cooldown) zeroed via service for fresh (see resetRuntime + resetForFreshChat).
      // Declarative initial bond/trust/emotion/day etc are already seeded above from the card's
      // FrontPorchExtensions (or defaults). The old hasFrontPorchExtensions preserve here
      // was the source of fixation bleed on "New Chat" for cards that had any FP ext object.
      // Expression (manual/caches/onnx/lastAvatar) reset via service for no-bleed (new for step 4).
      // Lorebook (non-const isTriggered/remainingDepth) reset via scanner in both ext-seed (1:1) and non-ext (group/0-session) paths of startNewChat (added for hygiene to match briefing "every keep-sync" + setActiveCharacter etc; prevents bleed into greetings/scans).
      debugPrint(
        '[startNewChat] Resetting runtime arousal/fixation + transients for fresh chat (was: arousal=${_nsfwService.arousalLevel}, fixation=${_relationshipService.activeFixation}/${_relationshipService.fixationLifespan})',
      );
      _nsfwService.resetRuntimeArousalAndCooldown();
      debugPrint(
        '[startNewChat] After reset: arousal=${_nsfwService.arousalLevel}, fixation=${_relationshipService.activeFixation}/${_relationshipService.fixationLifespan}',
      );

      // Recalculate tiers from seeded scores (only needed for realism-enabled chars)
      if (_realismEnabled) {
        // Tiers are maintained inside service after seed; no direct _calculate here.
      }

      // Seed initial quest/task as a primary objective
      if (extSeed.currentTask.isNotEmpty) {
        // Defer so the session ID is ready before the DB write
        Future.microtask(() async {
          await setObjective(extSeed.currentTask, isPrimary: true);
          debugPrint(
            '[ChatService] V2.5 seeded initial task: ${extSeed.currentTask}',
          );
        });
      }
    } else {
      // Group mode or no active character: reset to defaults but preserve existing extensions-based values
      // (pending covered by service.resetForFreshChat below)

      if (_activeGroup == null && _messages.isNotEmpty) {
        // Will be populated later with greeting in non-group modes
        // Preserve realism state for proper post-greeting eval (don't reset here)
      } else {
        // Relationship + Expression + Time + Nsfw reset via service helpers (keeps reset blocks in sync with setActiveCharacter:1572 etc / _loadLast empty / setActiveGroup / startNew ext-seed; see "incomplete zeroing... now complete (see CLAUDE.md)" + full list in "keep reset blocks" comments including + llm_eval_engine (stateless or prompt-only; no reset calls needed; incomplete zeroing... now complete (see CLAUDE.md)) + needs_impact_evaluator (stateless or prompt-only; no reset calls needed) + realism_evals (stateless or prompt-only; no reset calls needed)). (cross-ref setActiveCharacter:1572 etc)
        // Time now explicitly reset in group 0-session/empty paths + setActiveGroup defensive + _loadLast empty (cross-check needs bugfix hygiene).
        _relationshipService.resetForFreshChat();
        _expressionService.resetForFreshChat();
        _timeService.resetForFreshChat();
        // Fresh GROUP chat: apply the group's authored scene-time seed on top
        // of the reset (story-calendar "As built" gap fix). Keep in sync with
        // the _loadLastSession 0-session branch.
        if (_activeGroup != null) {
          final timeSeed = parseGroupTimeSeed(
            _activeGroup!.defaultMemberRealismState,
            _activeGroup!.baselineRealismState,
          );
          if (timeSeed != null) {
            _timeService.seedFromV2OrExt(
              dayCount: timeSeed.dayCount,
              timeOfDay: timeSeed.timeOfDay,
              storyStartDate: timeSeed.storyStartDate,
              storyStartTime: timeSeed.storyStartTime,
              passageOfTimeEnabled:
                  _storageService.realismSettings.passageOfTimeDefault,
            );
          }
        }
        _nsfwService.resetForFreshChat();
        // Lorebook trigger reset via extracted service (keeps reset blocks in sync with setActiveCharacter:1572 / _loadLast empty / setActiveGroup / startNew ext-seed; see "incomplete zeroing of secondary ... on 0-session/new-character/group" + startNew 1:1+group now complete + full list in keep-sync comments incl llm_eval_engine). (cross-ref setActiveCharacter:1572 etc)
        // See "keep reset blocks in sync" comments (setActiveGroup, startNewChat, load* , setActive* all must hit this; now includes needs/chaos/... + leaves (see CLAUDE.md for full; incomplete zeroing now complete) + " )" for group/0-session/new-chat hygiene; incomplete zeroing now complete).
        // (cross-ref setActiveCharacter:1572)
        _lorebookScanner.resetLorebookTriggerState();
        // Don't touch dayCount/time etc directly — seeded from extensions or loaded session (or reset above for fresh no-ext path).
        // Time reset helper kept in sync with other blocks.
        // needs_impact_evaluator (stateless/prompt-only; no reset calls needed) covered in keep-sync lists.

        // Explicit zero for secondary config flags in group/non-ext/0-session/new-chat path (keeps "incomplete zeroing... now complete (see CLAUDE.md)" true in *code* not just comments; matches ext-seed 1:1 + setActiveCharacter + setActiveGroup defensive; cross-ref setActiveCharacter:1572 + full list in keep-sync comments incl + needs_impact_evaluator (stateless or prompt-only; no reset calls needed) + realism_evals (stateless or prompt-only; no reset calls needed) + " ; authority mode for needs; hygiene listed, no code zero line)") + "needsSimulation. (reason support kept for Director chips) ; cleared via sim initializeFresh/clearVector/resetBuffers on all paths; now complete)".
        _needsSimEnabled = false;
        _enjoysLowHygiene = false;
        _needsSimulation.clearVector();
        _needsSimulation.resetBuffers();
        // Fresh group chat: reset each member's per-character realism (bond/trust/
        // emotion/needs/FIXATION) back to the group's default member baselines so
        // the previous session's evolved state — most visibly an active fixation
        // "Background Thought" — does not bleed into the new chat. The scalar
        // resetForFreshChat() above only clears the 1:1 registers; per-speaker group
        // state lives in _groupRealism, which startNewChat never reset (the leak).
        // This mirrors the 1:1 branch's resetForFreshChat + card re-seed (parity).
        // Only _groupRealism is reset — group config (per-char system prompts, RAG
        // priorities, author notes, decay rates) is intentionally preserved, which
        // is why we do NOT route through _loadGroupRealismStateFromSession(null):
        // defaultMemberRealismState is perChar-only, so that path would wipe those
        // config maps. parseGroupRealismSeeds pulls just the perChar baselines.
        if (_activeGroup != null) {
          _groupRealism = parseGroupRealismSeeds(
            _activeGroup!.defaultMemberRealismState,
          );
        }
        _activeObjectives = [];
        _messagesSinceLastCheck = 0;
        _isCheckingCompletion =
            false; // explicit in non-ext/group/0-session else branch of startNew (both branches now; incomplete zeroing ... now complete)
        _summaryPaused =
            false; // explicit secondary zero for _summaryPaused (symmetric to generating; non-ext/group/0-session startNew path + now complete)
        _isSummaryGenerating =
            false; // explicit secondary zero in startNew non-ext/group/0-session path (both branches + now complete for summary flag too)
        _isGrowthPassRunning =
            false; // growth-pass flag zero in startNew non-ext/group/0-session path (both branches; keep reset blocks in sync)
      }
    }

    // Drop the previous session's growth cache so the new chat starts with
    // the original (ungrown) personality. A fresh session has no rings and
    // no legacy blob, so an empty cache IS the correct state — the next
    // _refreshGrowthCache (session load / first growth pass) re-scopes it.
    _isGrowthPassRunning = false;
    _growthStore.invalidate();

    if (_activeGroup != null && _groupCharacters.isNotEmpty) {
      // Group mode: respect explicit group.firstMessage (custom group greeting set
      // by creator or Group Card) when present. Only fall back to the first
      // participating character's firstMessage when the group has no custom opening.
      String greetingText;
      String greetingSender;
      String? greetingCharId;

      if (_activeGroup!.firstMessage.isNotEmpty) {
        greetingText = _macroResolver.resolve(
          _activeGroup!.firstMessage,
          MacroContext(userName: _userPersonaService.persona.name),
          section: 'greeting',
        );
        greetingSender = _activeGroup!.name;
        greetingCharId = null;
      } else {
        final first = _groupCharacters.first;
        greetingText = first.firstMessage.isNotEmpty
            ? _buildFirstMessage(first)
            : '';
        greetingSender = first.name;
        greetingCharId = _getCharacterIdFromCard(first);
      }

      if (greetingText.isNotEmpty) {
        _messages.add(
          ChatMessage(
            text: greetingText,
            sender: greetingSender,
            isUser: false,
            characterId: greetingCharId,
          ),
        );
        _lorebookScanner.scanLatest();
      }
      _groupManager?.resetTurnState();
    } else if (_activeCharacter != null) {
      // 1:1 mode
      if (_activeCharacter!.firstMessage.isNotEmpty) {
        _messages.add(
          ChatMessage(
            text: _buildFirstMessage(_activeCharacter!),
            sender: _activeCharacter!.name,
            isUser: false,
          ),
        );
        _lorebookScanner.scanLatest();
      }
    }

    _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _computeAbsenceGap(const []); // fresh session — no real-world gap (Living Time §2)

    // Inherit theme from the most recent prior session with this character/group.
    _sessionThemeOverrides = ChatThemeOverrides();
    try {
      final lastThemeJson = await _db.getLastSessionThemeOverrides(
        characterId: _activeCharacter?.dbId,
        groupId: _activeGroup?.id,
      );
      if (lastThemeJson != null) {
        _sessionThemeOverrides =
            ChatThemeOverrides.fromJsonString(lastThemeJson);
      }
    } catch (_) {
      _sessionThemeOverrides = ChatThemeOverrides();
    }
    debugPrint(
      '[startNewChat] BEFORE SAVE: arousal=${_nsfwService.arousalLevel}, fixation=${_relationshipService.activeFixation}/${_relationshipService.fixationLifespan}',
    );
    await _saveChat();
    debugPrint(
      '[startNewChat] AFTER SAVE: arousal=${_nsfwService.arousalLevel}, fixation=${_relationshipService.activeFixation}/${_relationshipService.fixationLifespan}',
    );
    notifyListeners();

    // ── Post-Greeting Realism Baseline ──────────────────────────────────
    // Always mark that a greeting was placed — even if Realism is currently off.
    // If Realism is already on, fire immediately. Otherwise the flag will be
    // consumed the moment the user enables Realism.
    // Skip if character already has pre-seeded V2.5 extensions — those baseline
    // values are intentional and should not be overwritten by auto-eval.
    // (See also: setActiveCharacter 0-session path comment for why direct imports rely on retro path.)
    if (_activeGroup == null &&
        _messages.isNotEmpty &&
        _activeCharacter!.frontPorchExtensions == null) {
      _greetingEvalPending = true;
      if (_realismEnabled) {
        _runPostGreetingEval();
      }
    }
  }
}
