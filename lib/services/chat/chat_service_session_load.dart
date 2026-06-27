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

/// Session load + listing — _loadLastSession, getSessionsForId, getSessions, loadSession. Extracted verbatim (zero behaviour change) to shrink the god file.
extension ChatServiceSessionLoad on ChatService {
  Future<void> _loadLastSession() async {
    if (_activeCharacter == null && _activeGroup == null) return;

    // Get sessions from DB
    List<Session> sessions;
    if (_activeGroup != null) {
      sessions = await _db.getSessionsForGroup(_activeGroup!.id);
    } else if (_activeCharacter?.dbId != null) {
      sessions = await _db.getSessionsForCharacter(_activeCharacter!.dbId!);
    } else {
      return;
    }

    if (sessions.isEmpty) {
      debugPrint('[ChatService] _loadLastSession: No previous sessions found');
      // Ensure no stale fork/parent state remains from a prior character/group.
      _parentSessionId = null;
      _forkIndex = null;
      // Expression runtime (manual/caches) reset on no-prior-session to prevent bleed (new for step4, matches fork/parent hygiene).
      _expressionService.resetForFreshChat();
      // Time (secondary config: passage, weekday anchors, turns, day/time scalars) reset for fresh 0-session/new-group paths.
      // Prevents bleed of advanced time from prior 1:1 into fresh groups (cross-check vs needs bugfix reset hygiene).
      // Nsfw (cooldown/arousal) reset for same (incomplete zeroing of nsfw on 0-session/new-group was a prior hygiene issue).
      // Lorebook triggers/depth reset for same (incomplete zeroing of lore on 0-session/new-group was a prior hygiene pattern to avoid).
      // See "keep reset blocks in sync" (setActiveGroup, startNewChat 1:1+group (now explicit in both), load* , setActive* all must hit this; now includes needs/chaos/... + leaves (see CLAUDE.md for full; incomplete zeroing now complete) + " ; now complete in all group/0-session/new-chat hygiene)" ; incomplete zeroing now complete).
      // (cross-ref setActiveCharacter:1572)
      _timeService.resetForFreshChat();
      _nsfwService.resetForFreshChat();
      _lorebookScanner.resetLorebookTriggerState();
      _activeObjectives = [];
      _messagesSinceLastCheck = 0;
      _isCheckingCompletion =
          false; // zero in _loadLast empty early return (0-session path hygiene)
      _summaryPaused =
          false; // explicit secondary zero for _summaryPaused (symmetric; _loadLast empty early return 0-session)
      _isSummaryGenerating =
          false; // secondary zero in _loadLast empty (0-session for summary flag)
      _userMessagesSinceLastPeriodicEval = 0;
      _isExtractingFacts =
          false; // secondary fact flag + counter zero in _loadLast empty early return (0-session path hygiene; fact_extraction)
      _isEvolvingCharacter = false;
      _evolutionStatus = '';
      _evolutionError =
          ''; // explicit evo flag/status/error zero in _loadLast empty early return (0-session path hygiene; evolution_service (stateless or prompt-only; no reset calls needed))
      return;
    }

    // Sessions are already sorted descending by createdAt
    final lastSession = sessions.first;
    _currentSessionId = lastSession.id;
    _authorNote = lastSession.authorNote;
    _authorNoteStrength = lastSession.authorNoteDepth;
    _summary = lastSession.summary ?? '';
    _summaryLastIndex = lastSession.summaryLastIndex ?? 0;
    _sessionName = lastSession.name;
    _sessionDescription = lastSession.description;
    _parentSessionId = lastSession.parentSession;
    _forkIndex = lastSession.forkIndex;
    // Relationship scalars + migration/tier calc now via service (keeps load parity).
    // Migration: scale old scores (±150) to new range (±300). (Card-seed bypass: fresh V2.5
    // ext seeds use seedFromCardV2OrExt plain clamp in setActiveCharacter/startNew 1:1 paths;
    // this migrate path is *only* for legacy persisted sessions. See card-seed notes at the two
    // ext-seed sites + relationship_service + full keep-sync lists + setActiveCharacter:1572.)
    _relationshipService.loadScalars(
      affectionScore: _relationshipService.migrateShortTermScore(
        lastSession.affectionScore,
      ),
      longTermScore: _relationshipService.migrateLongTermScore(
        lastSession.longTermScore,
      ),
      trustLevel: lastSession.trustLevel,
      activeFixation: lastSession.activeFixation,
      fixationLifespan: lastSession.fixationLifespan,
      spatialStance: lastSession.spatialStance,
      trustRepairPending: lastSession.trustRepairPending,
      turnsSinceLongTermCheck: lastSession.turnsSinceLongTermCheck,
      shortTermDeltasSummary: lastSession.shortTermDeltasSummary,
    );
    // Apply legacy migration (if needed) after load. (Card-seed bypass note: this *10 + migrate
    // path is exclusively for legacy persisted sessions from pre-±300 era; fresh card seeds use
    // the plain seedFromCardV2OrExt at the two 1:1 ext sites above. Expanded per "related load/reset
    // sites" requirement + keep-sync full list + setActiveCharacter:1572 + both startNew.)
    _relationshipService.applyLegacyShortTermMigrationIfNeeded();
    _realismEnabled = lastSession.realismEnabled;
    _moodDecayCounter = lastSession.moodDecayCounter;
    _characterEmotion = lastSession.characterEmotion;
    _emotionIntensity = lastSession.emotionIntensity;
    // Time load via extracted service (resolve + scalars; keeps load blocks in sync).
    _timeService.loadTimeScalars(
      timeOfDay: lastSession.timeOfDay,
      dayCount: lastSession.dayCount,
      startDayOfWeek: lastSession.startDayOfWeek,
      passageOfTimeEnabled:
          lastSession.passageOfTimeEnabled &&
          _storageService.realismSettings.passageOfTimeDefault,
    );
    _nsfwService.loadNsfwScalars(
      nsfwCooldownEnabled: lastSession.nsfwCooldownEnabled,
      arousalLevel: lastSession.arousalLevel,
      cooldownTurnsRemaining: lastSession.cooldownTurnsRemaining,
      cooldownTurnsTotal: lastSession.cooldownTurnsTotal,
    );
    _needsSimEnabled = lastSession.needsSimEnabled;
    if (_needsSimEnabled) {
      // Seed defaults first, then overlay the saved vector ONLY when it has
      // values. A blank saved vector (e.g. needs was toggled on mid-chat before
      // it seeded) must NOT clobber the defaults, or the sidebar shows no scores.
      _needsSimulation.initializeFresh();
      final nv = lastSession.needsVector;
      final saved = (nv is String && nv.isNotEmpty)
          ? (jsonDecode(nv) as Map).cast<String, int>()
          : <String, int>{};
      if (saved.isNotEmpty) {
        _needsSimulation.restoreFromSnapshot({'vector': saved});
      }
    } else {
      _needsSimulation.clearVector();
    }

    // Re-sync from the character's current setting so that toggling
    // "Enjoys low hygiene" on the character affects existing chats on next load.
    _enjoysLowHygiene =
        _activeCharacter?.frontPorchExtensions?.enjoysLowHygiene ?? false;

    _needsSimulation.resetBuffers();
    // trust/fixation/spatial/pending/affection/tiers already loaded via _relationshipService.loadScalars above.
    debugPrint(
      '[ChatService] _loadLastSession: Loaded session with arousal=${_nsfwService.arousalLevel}, fixation=${_relationshipService.activeFixation}/${_relationshipService.fixationLifespan}',
    );
    _chaosModeService.loadScalars(
      modeEnabled: lastSession.chaosModeEnabled,
      pressure: lastSession.chaosPressure,
    );

    // Realism Engine 2.0 Compatibility Migration (delegated to service). (Card-seed bypass:
    // this legacy path for old persisted data; fresh 1:1 card ext seeds use seedFromCardV2OrExt
    // (plain) at setActive/startNew 1:1 sites. See expanded keep-sync + setActiveCharacter:1572.)
    _relationshipService.applyLegacyShortTermMigrationIfNeeded();
    if (_relationshipService.affectionScore != lastSession.affectionScore ||
        _relationshipService.relationshipTier != lastSession.relationshipTier) {
      debugPrint(
        '[Realism] Legacy session migrated to REv2 scales (loadLast).',
      );
    }

    // v30: Load live per-character group realism/needs (bond/trust/emotion/fixation/arousal/relationships/needs)
    // from the session column (or fall back to group defaults). Must happen for group entry paths
    // so that _groupRealism is populated before any eval, prompt injection, or UI read.
    if (_activeGroup != null) {
      _loadGroupRealismStateFromSession(lastSession);
    } else {
      // 1:1 session: the group realism column ('{}' for plain sessions) may
      // carry persisted Scene Guest (Lite NPC) dbIds. Tolerant of legacy/empty.
      _loadSceneGuestsFromSession(lastSession);
    }

    // Load per-session evolution (1:1 mode only — group is handled by _loadGroupEvolvedFields)
    if (_activeCharacter != null) {
      final charId = _getCharacterIdFromCard(_activeCharacter!);
      _evolvedPersonalities[charId] = lastSession.evolvedPersonality;
      _evolvedScenarios[charId] = lastSession.evolvedScenario;
      _characterEvolutionCount = lastSession.evolutionCount;
      _groupEvolutionCounts[charId] = lastSession.evolutionCount;
    }

    // Load messages
    // Zero secondary objective flags in loaded path of _loadLast (before callers do _loadActiveObjectives / _loadObjectivesForCurrentSpeaker); incomplete zeroing hygiene.
    _activeObjectives = [];
    _messagesSinceLastCheck = 0;
    _isCheckingCompletion = false;
    _summaryPaused =
        false; // explicit secondary zero for _summaryPaused (symmetric; _loadLast empty/loaded hygiene)
    _isSummaryGenerating =
        false; // secondary flag zero for summary_service (stateless/prompt-only; incomplete zeroing ... now complete)
    _userMessagesSinceLastPeriodicEval = 0;
    _isExtractingFacts =
        false; // secondary fact flag + counter zero in _loadLast loaded path (incomplete zeroing ... now complete; fact_extraction)
    _isEvolvingCharacter = false;
    _evolutionStatus = '';
    _evolutionError =
        ''; // explicit evo flag/status/error zero in _loadLast loaded path (incomplete zeroing ... now complete; evolution_service (stateless or prompt-only; no reset calls needed))
    try {
      final dbMessages = await _db.getMessagesForSession(_currentSessionId!);
      debugPrint(
        '[ChatService] 🟢 _loadLastSession: loading ${dbMessages.length} '
        'messages for session $_currentSessionId',
      );
      _messages.clear();
      for (final m in dbMessages) {
        List<String> swipes;
        try {
          swipes = List<String>.from(jsonDecode(m.swipes));
        } catch (_) {
          swipes = [''];
        }
        List<int> swipeDurations;
        try {
          swipeDurations = List<int>.from(
            (jsonDecode(m.swipeDurations) as List).map(
              (e) => (e as num).toInt(),
            ),
          );
        } catch (_) {
          swipeDurations = [0];
        }

        final safeSwipeIndex =
            (m.swipeIndex >= 0 && m.swipeIndex < swipes.length)
            ? m.swipeIndex
            : 0;

        _messages.add(
          ChatMessage(
            text: swipes.isNotEmpty ? swipes[safeSwipeIndex] : '',
            sender: m.sender,
            isUser: m.isUser,
            characterId: m.characterId,
            swipes: swipes,
            swipeIndex: safeSwipeIndex,
            swipeDurations: swipeDurations,
            metadata: m.metadata != null
                ? Map<String, dynamic>.from(jsonDecode(m.metadata!))
                : null,
            swipeMetadata: m.swipeMetadata != null
                ? (jsonDecode(m.swipeMetadata!) as List<dynamic>)
                      .map(
                        (e) => e != null
                            ? Map<String, dynamic>.from(e as Map)
                            : null,
                      )
                      .toList()
                : null,
          ),
        );
      }

      if (_messages.isNotEmpty) {
        _lorebookScanner.scanLorebook(_messages.last.text);
      }
    } catch (e) {
      print('Error loading chat session: $e');
    }
  }

  /// Get sessions for a given character/group ID without setting it as active.
  Future<List<Map<String, dynamic>>> getSessionsForId(String charId) async {
    // Determine if this is a group or character
    List<Session> dbSessions;
    if (charId.startsWith('group_')) {
      final groupId = charId.replaceFirst('group_', '');
      dbSessions = await _db.getSessionsForGroup(groupId);
    } else {
      // Find character by imagePath basename
      final allChars = await _db.getAllCharacters();
      final match = allChars.where((c) {
        if (c.imagePath == null) return false;
        return path.basenameWithoutExtension(c.imagePath!) == charId;
      }).firstOrNull;
      if (match != null) {
        dbSessions = await _db.getSessionsForCharacter(match.id);
      } else {
        dbSessions = [];
      }
    }

    List<Map<String, dynamic>> sessions = [];
    for (final s in dbSessions) {
      final timestamp = int.tryParse(s.id) ?? 0;
      final date = DateTime.fromMillisecondsSinceEpoch(timestamp);

      // Get message count and preview
      final msgs = await _db.getMessagesForSession(s.id);
      String preview = 'New Conversation';
      if (s.name != null && s.name!.isNotEmpty) {
        preview = s.name!;
      } else if (msgs.length > 1) {
        // Use second message text as preview
        try {
          final swipes = List<String>.from(jsonDecode(msgs[1].swipes));
          preview = swipes.isNotEmpty ? swipes[msgs[1].swipeIndex] : '';
          if (preview.length > 50) preview = '${preview.substring(0, 50)}...';
        } catch (_) {}
      }

      sessions.add({
        'id': s.id,
        'date': date,
        'preview': preview,
        'message_count': msgs.length,
        'user_message_count': msgs.where((m) => m.isUser).length,
        if (s.name != null) 'session_name': s.name,
        if (s.description != null) 'session_description': s.description,
        if (s.parentSession != null) 'parent_session': s.parentSession,
        if (s.forkIndex != null) 'fork_index': s.forkIndex,
      });
    }

    sessions.sort(
      (a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime),
    );
    return sessions;
  }

  Future<List<Map<String, dynamic>>> getSessions() async {
    if (_activeCharacter == null && _activeGroup == null) return [];
    final charId = _getCharacterId();
    return getSessionsForId(charId);
  }

  Future<void> loadSession(String sessionId) async {
    if (_activeCharacter == null && _activeGroup == null) return;

    final session = await _db.getSessionById(sessionId);
    if (session == null) return;

    if (session.userPersonaId != null) {
      await _userPersonaService.setActivePersona(session.userPersonaId!);
    }

    try {
      final dbMessages = await _db.getMessagesForSession(sessionId);
      debugPrint(
        '[ChatService] 🟢 loadSession: loading ${dbMessages.length} '
        'messages for session $sessionId',
      );
      _messages.clear();
      for (final m in dbMessages) {
        List<String> swipes;
        try {
          swipes = List<String>.from(jsonDecode(m.swipes));
        } catch (_) {
          swipes = [''];
        }
        List<int> swipeDurations;
        try {
          swipeDurations = List<int>.from(
            (jsonDecode(m.swipeDurations) as List).map(
              (e) => (e as num).toInt(),
            ),
          );
        } catch (_) {
          swipeDurations = [0];
        }

        final safeSwipeIndex =
            (m.swipeIndex >= 0 && m.swipeIndex < swipes.length)
            ? m.swipeIndex
            : 0;

        _messages.add(
          ChatMessage(
            text: swipes.isNotEmpty ? swipes[safeSwipeIndex] : '',
            sender: m.sender,
            isUser: m.isUser,
            characterId: m.characterId,
            swipes: swipes,
            swipeIndex: safeSwipeIndex,
            swipeDurations: swipeDurations,
            metadata: m.metadata != null
                ? Map<String, dynamic>.from(jsonDecode(m.metadata!))
                : null,
            swipeMetadata: m.swipeMetadata != null
                ? (jsonDecode(m.swipeMetadata!) as List<dynamic>)
                      .map(
                        (e) => e != null
                            ? Map<String, dynamic>.from(e as Map)
                            : null,
                      )
                      .toList()
                : null,
          ),
        );
      }

      // Post-load sanitization: force valid swipe indices and clamp absurdly long fixation text.
      // This protects against any legacy corrupted rows or previous buggy saves, even if the
      // individual message constructors already clamp.
      for (final msg in _messages) {
        if (msg.swipeIndex < 0 || msg.swipeIndex >= msg.swipes.length) {
          msg.swipeIndex = 0;
        }
      }

      // The fixation coming out of the LLM can sometimes be a full paragraph instead of a short topic.
      // Truncate it to keep the UI and prompts sane.
      _relationshipService.sanitizeFixationIfTooLong();

      // ── Hydrate hidden group state checkpoint (DB-free: realism + per-char notes) ──
      // The sentinel is stored as the last message for durability but must be
      // stripped from the in-memory list so the UI and prompt builders never see it.
      // (v30: _hydrateGroupRealismCheckpointIfPresent removed — state now loads from DB column)

      _currentSessionId = sessionId;
      // Scene Guests are per-session. Without this, switching to a different
      // session via the history picker leaves the PREVIOUS session's guests
      // (and their evolution/detection state) in place — they keep chiming in
      // and get re-persisted into the loaded session's blob, contaminating it,
      // while this session's own guests are never restored. Mirror the
      // _loadLastSession 1:1 branch: full reset, then load this session's blob.
      if (_activeGroup == null) {
        _pendingGuestDeparture = null;
        _pendingGuestPickerFilter = null;
        _resetGuestActivityState();
        _userMessagesSinceLastCastScan = 0;
        _pendingGuestDetection = null;
        _offeredOrIgnoredGuestNames.clear();
        // (clears + restores _sceneGuestIds/_sceneGuestCards + guest evolution)
        _loadSceneGuestsFromSession(session);
      } else {
        // Group session: restore live per-character realism/needs from the
        // session column — mirrors the _loadLastSession group branch so resuming
        // an OLDER group session via the in-chat history drawer no longer drops
        // each member's bond/trust/emotion/fixation/arousal/needs.
        _loadGroupRealismStateFromSession(session);
      }
      _authorNote = session.authorNote;
      _authorNoteStrength = session.authorNoteDepth;
      _summary = session.summary ?? '';
      _summaryLastIndex = session.summaryLastIndex ?? 0;
      _summaryPaused =
          false; // explicit secondary zero for _summaryPaused on loadSession loaded path (incomplete zeroing ... now complete; see keep-sync + summary_service)
      _isSummaryGenerating =
          false; // secondary zero for flag on loadSession loaded (symmetric)
      _userMessagesSinceLastPeriodicEval = 0;
      _isExtractingFacts =
          false; // secondary fact flag + counter zero on loadSession loaded (symmetric; incomplete zeroing ... now complete; fact_extraction)
      _isEvolvingCharacter = false;
      _evolutionStatus = '';
      _evolutionError =
          ''; // explicit evo flag/status/error zero on loadSession loaded (symmetric; incomplete zeroing ... now complete; evolution_service (stateless or prompt-only; no reset calls needed))
      _sessionName = session.name;
      _sessionDescription = session.description;
      _parentSessionId = session.parentSession;
      _forkIndex = session.forkIndex;
      // Relationship load + tier calc + legacy migration via service.
      _relationshipService.loadScalars(
        affectionScore: session.affectionScore,
        longTermScore: session.longTermScore,
        trustLevel: session.trustLevel,
        activeFixation: session.activeFixation,
        fixationLifespan: session.fixationLifespan,
        spatialStance: session.spatialStance,
        trustRepairPending: session.trustRepairPending,
        turnsSinceLongTermCheck: session.turnsSinceLongTermCheck,
        shortTermDeltasSummary: session.shortTermDeltasSummary,
      );
      _relationshipService.applyLegacyShortTermMigrationIfNeeded();
      // (Card-seed bypass: legacy *10 migration only; see the two ext-seed sites + prior load sites
      // for full "card seeds authored on current ±300" + keep-sync lists + relationship leaf.)

      // counters already via loadScalars on service.
      _realismEnabled = session.realismEnabled;
      _moodDecayCounter = session.moodDecayCounter;
      _characterEmotion = session.characterEmotion;
      _emotionIntensity = session.emotionIntensity;
      // Time load via extracted service (resolve + scalars; keeps group load blocks in sync).
      _timeService.loadTimeScalars(
        timeOfDay: session.timeOfDay,
        dayCount: session.dayCount,
        startDayOfWeek: session.startDayOfWeek,
        passageOfTimeEnabled:
            session.passageOfTimeEnabled &&
            _storageService.realismSettings.passageOfTimeDefault,
      );
      _nsfwService.loadNsfwScalars(
        nsfwCooldownEnabled: session.nsfwCooldownEnabled,
        arousalLevel: session.arousalLevel,
        cooldownTurnsRemaining: session.cooldownTurnsRemaining,
        cooldownTurnsTotal: session.cooldownTurnsTotal,
      );
      _needsSimEnabled = session.needsSimEnabled;
      if (_needsSimEnabled) {
        // Seed defaults first, then overlay the saved vector ONLY when it has
        // values — a blank saved vector must not clobber the defaults (else the
        // sidebar shows no scores). Keeps load in sync with _loadLastSession.
        _needsSimulation.initializeFresh();
        final nv = session.needsVector;
        final saved = (nv is String && nv.isNotEmpty)
            ? (jsonDecode(nv) as Map).cast<String, int>()
            : <String, int>{};
        if (saved.isNotEmpty) {
          _needsSimulation.restoreFromSnapshot({'vector': saved});
        }
      } else {
        _needsSimulation.clearVector();
      }

      // Re-sync from the character's current setting so toggling
      // "Enjoys low hygiene" affects existing chats on load.
      _enjoysLowHygiene =
          _activeCharacter?.frontPorchExtensions?.enjoysLowHygiene ?? false;

      _needsSimulation.resetBuffers();
      // trust/fixation etc already via _relationshipService.loadScalars above.

      // Load per-session evolution (1:1 mode only — group handled by _loadGroupEvolvedFields)
      if (_activeCharacter != null) {
        final charId = _getCharacterIdFromCard(_activeCharacter!);
        _evolvedPersonalities[charId] = session.evolvedPersonality;
        _evolvedScenarios[charId] = session.evolvedScenario;
        _characterEvolutionCount = session.evolutionCount;
        _groupEvolutionCounts[charId] = session.evolutionCount;
      }

      // Per-session generation parameter overrides (v22) — loaded via raw SQL
      // so this works even before build_runner regenerates database.g.dart.
      try {
        final genRows = await _db
            .customSelect(
              'SELECT generation_settings FROM sessions WHERE id = ?',
              variables: [drift.Variable(sessionId)],
            )
            .get();
        final genJson = genRows.isNotEmpty
            ? genRows.first.read<String?>('generation_settings')
            : null;
        _sessionGenSettings = ChatGenerationSettings.fromJsonString(genJson);
      } catch (_) {
        _sessionGenSettings = ChatGenerationSettings();
      }

      if (_messages.isNotEmpty) {
        _lorebookScanner.scanLorebook(_messages.last.text);
      }
      notifyListeners();
    } catch (e) {
      print('Error loading session $sessionId: $e');
    }
  }
}
