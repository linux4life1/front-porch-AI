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
  /// Real-absence gap (Living Time §2) from the freshly loaded DB rows —
  /// computed BEFORE any save this session can refresh their updatedAt, so
  /// the anchor is genuinely "when this chat last had activity". Shared by
  /// both load paths (keep them in sync). Fresh/empty chats stay at zero.
  void _computeAbsenceGap(List<Message> dbMessages) {
    _absenceGap = Duration.zero;
    _absenceAckPending = false;
    _absenceAckConsumed = false;
    DateTime? last;
    for (final m in dbMessages) {
      if (last == null || m.updatedAt.isAfter(last)) last = m.updatedAt;
    }
    if (last == null) return;
    final gap = DateTime.now().difference(last);
    if (gap.isNegative) return;
    _absenceGap = gap;
    _absenceAckPending = absencePhrase != null;
  }

  Future<void> _loadLastSession() async {
    // NOTE: This method contains multiple await boundaries (DB queries).
    // If the user rapidly switches characters/groups, Dart's cooperative
    // scheduler may interleave a second setActiveCharacter call during one
    // of these awaits. The sanitizer below runs synchronously on already-
    // fetched local variables (swipes), so it does not introduce a new race
    // window — but it also cannot prevent pre-existing interleaving where
    // the later load overwrites _messages.
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
      _clearTodayPointer();
      // Fresh GROUP session: apply the group's authored scene-time seed on
      // top of the reset (story-calendar "As built" gap fix — the wizard's
      // time seed used to be editor-carried only and never reached the
      // clock). Keep in sync with the startNewChat group branch.
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
      _lorebookScanner.resetLorebookTriggerState();
      _activeObjectives = [];
      _messagesSinceLastCheck = 0;
      _isCheckingCompletion =
          false; // zero in _loadLast empty early return (0-session path hygiene)
      _summaryPaused =
          false; // explicit secondary zero for _summaryPaused (symmetric; _loadLast empty early return 0-session)
      _isSummaryGenerating =
          false; // secondary zero in _loadLast empty (0-session for summary flag)
      _isGrowthPassRunning =
          false; // growth-pass flag zero in _loadLast empty early return (0-session path hygiene; keep reset blocks in sync)
      _growthStore.invalidate(); // no session — nothing to inject
      _selectedLooks
          .clear(); // 0-session: no per-chat look selection (keep reset blocks in sync)
      _sessionGenSettings =
          ChatGenerationSettings(); // 0-session: no per-chat gen overrides — without this, character B's first chat ran (and could SAVE) character A's temp/stops/sanitizer (keep reset blocks in sync)
      _clearContextBudget();
      return;
    }

    // Auto-load the most recently ACTIVE session (loadSession bumps updatedAt
    // when a chat is opened). The shared session queries deliberately order by
    // createdAt (story-export, group/cast and the history list rely on that), so
    // "last active" is derived here from updatedAt instead of the list order —
    // keeping this feature isolated from those other callers.
    final lastSession = sessions.reduce(
      (a, b) => a.updatedAt.isAfter(b.updatedAt) ? a : b,
    );
    _currentSessionId = lastSession.id;
    // Sanitizer + first paint need gen settings and the tail ONLY.
    // Growth/worlds/scalars used to run first and kept the spinner up
    // for the same beat as loading 11k messages.
    _sessionGenSettings = ChatGenerationSettings.fromJsonString(
      lastSession.generationSettings,
    );
    try {
      await _openSessionMessages(lastSession.id);
    } catch (e) {
      print('Error loading chat session: $e');
    }
    await _reloadChatWorldIds();
    await _hydrateSessionScalars(lastSession);

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

    // Load messages
    // Zero secondary objective flags in loaded path of _loadLast (before callers do _loadActiveObjectives / _loadObjectivesForCurrentSpeaker); incomplete zeroing hygiene.
    // (loadSession zeroes + reloads this trio itself, right after
    // _hydrateSessionScalars — it used to leave them alone on the belief that
    // "its own callers" would, and none did. Keep the trio out of the shared
    // hydrate: the two paths differ in WHEN the loader runs, not whether.)
    _activeObjectives = [];
    _messagesSinceLastCheck = 0;
    _isCheckingCompletion = false;

    // Load per-chat generation settings override for this session.
    // LLMerta porch memories on last-session open (same as loadSession).
    unawaited(_maybeImportPorchMemories());
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

    // Aggregate stats in two queries instead of hydrating every message row
    // of every session — this runs on the tap-to-open-chat path, where the
    // old loop was the dead time before the route push even started.
    final stats = await _db.getSessionListStats(
      [for (final s in dbSessions) s.id],
    );

    List<Map<String, dynamic>> sessions = [];
    for (final s in dbSessions) {
      final timestamp = int.tryParse(s.id) ?? 0;
      final date = DateTime.fromMillisecondsSinceEpoch(timestamp);

      final stat = stats[s.id];
      String preview = 'New Conversation';
      if (s.name != null && s.name!.isNotEmpty) {
        preview = s.name!;
      } else if (stat?.previewSwipes != null) {
        // Use second message text as preview
        try {
          final swipes = List<String>.from(jsonDecode(stat!.previewSwipes!));
          preview =
              (stat.previewIndex >= 0 && stat.previewIndex < swipes.length)
              ? swipes[stat.previewIndex]
              : (swipes.isNotEmpty ? swipes.first : '');
          if (preview.length > 50) preview = '${preview.substring(0, 50)}...';
        } catch (_) {}
      }

      sessions.add({
        'id': s.id,
        'date': date,
        'preview': preview,
        'message_count': stat?.count ?? 0,
        'user_message_count': stat?.userCount ?? 0,
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

  /// Decode DB [Message] rows into [_messages], applying retroactive output
  /// sanitisation when the per-chat or global setting requests it.
  /// Caller must clear `_messages` and set `_sessionGenSettings` beforehand.
  void _hydrateMessagesFromRows(List<Message> dbMessages) {
    // Output sanitizer: apply configured replacements to loaded swipes
    // so legacy messages (saved before this feature) are also normalised.
    // Gated by sanitiseExistingHistory — when off, even chats with
    // per-chat sanitizer enabled keep their raw saved text on load.
    // Resolved (per-chat override + rules, falling back to global) and
    // compiled ONCE out here: this loop runs per message and sanitize runs
    // per swipe, so compiling per swipe was thousands of RegExp
    // constructions on the UI isolate per chat open (hot-path rule).
    final compiledRules =
        _sessionGenSettings.resolveOutputSanitizerEnabled(_storageService) &&
            _storageService.generationSettings.sanitiseExistingHistory
        ? compileSanitizerRules(
            _sessionGenSettings.resolveOutputSanitizerRules(_storageService),
          )
        : const <CompiledSanitizerRule>[];
    for (final m in dbMessages) {
      List<String> swipes;
      try {
        swipes = List<String>.from(jsonDecode(m.swipes));
      } catch (_) {
        swipes = [''];
      }

      // Model output ONLY — the feature's contract. Without the isUser
      // gate, a broad rule + retroactive-on rewrote the USER's own words in
      // memory, and the next _saveChat persisted the corruption. (Impersonate
      // drafts are sanitized at creation time, before they become user rows.)
      // System rows (backend notices, app status) are skipped too — rules
      // rewriting those could break the backend-notice dedupe comparison.
      if (!m.isUser &&
          m.sender != 'System' &&
          compiledRules.isNotEmpty &&
          swipes.isNotEmpty) {
        swipes = swipes
            .map((s) => sanitizeOutputCompiled(s, compiledRules))
            .toList();
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
      _lorebookScanner.scanLatest();
    }
  }

  /// Hydrates every session-scoped scalar the two load paths share, from one
  /// [Session] row: metadata (author note, summary, name/description, look
  /// selection, fork lineage), relationship scalars (RAW persisted values —
  /// the legacy ±150→×2 era wrappers were deleted 2026-07-27; see the
  /// era-heuristic warning atop relationship_service.dart), realism/mood/
  /// emotion, time, NSFW, needs (seed-then-overlay so a blank saved vector
  /// can't clobber defaults), the "enjoys low hygiene" re-sync, per-chat
  /// theme overrides, chaos mode, transient-flag zeroing, and the
  /// session-scoped growth-ring cache.
  ///
  /// Extracted per docs/design/session-load-refactor.md Step 2. Two fixes by
  /// construction: chaos-mode scalars now load on the history-picker path too
  /// (they only loaded on library open, so picked sessions lost Chaos Mode
  /// state), and fixation truncation now runs AFTER the relationship load on
  /// both paths (loadSession used to sanitize the PREVIOUS session's fixation
  /// before loading this one's).
  ///
  /// Callers keep what genuinely differs: group-realism/scene-guest branch,
  /// objectives zeroing (library path only), per-chat gen settings placement
  /// (must precede message hydration for the retroactive sanitizer), and the
  /// persona activation (picker path only, by design — restoring a specific
  /// chat restores its persona; a library tap must not silently switch the
  /// user's persona).
  Future<void> _hydrateSessionScalars(Session s) async {
    _authorNote = s.authorNote;
    _authorNoteStrength = s.authorNoteDepth;
    _summary = s.summary ?? '';
    _summaryLastIndex = s.summaryLastIndex ?? 0;
    _sessionName = s.name;
    _sessionDescription = s.description;
    _selectedLooks = decodeSelectedLooks(s.selectedLookAvatarId);
    _parentSessionId = s.parentSession;
    _forkIndex = s.forkIndex;
    _relationshipService.loadScalars(
      affectionScore: s.affectionScore,
      longTermScore: s.longTermScore,
      trustLevel: s.trustLevel,
      activeFixation: s.activeFixation,
      fixationLifespan: s.fixationLifespan,
      spatialStance: s.spatialStance,
      trustRepairPending: s.trustRepairPending,
      turnsSinceLongTermCheck: s.turnsSinceLongTermCheck,
      shortTermDeltasSummary: s.shortTermDeltasSummary,
    );
    // The fixation coming out of the LLM can sometimes be a full paragraph
    // instead of a short topic — truncate to keep the UI and prompts sane.
    _relationshipService.sanitizeFixationIfTooLong();
    _realismEnabled = s.realismEnabled;
    _characterEmotion = s.characterEmotion;
    _emotionIntensity = s.emotionIntensity;
    _timeService.loadTimeScalars(
      timeOfDay: s.timeOfDay,
      dayCount: s.dayCount,
      startDayOfWeek: s.startDayOfWeek,
      storyClock: s.storyClock,
      storyStartDate: s.storyStartDate,
      // The saved per-chat value, NOT AND-ed with the global default. That
      // global is a seed-time ceiling: the four seedFromV2OrExt callers apply
      // it when a chat is first created ("Global ceiling applied before
      // passing"). Applying it again on every load would let switching the
      // global off retroactively disable time in chats the user had already
      // turned it on for. Until now the AND was computed and then thrown away
      // by loadTimeScalars, so it was inert; assigning the parameter without
      // removing it here would have quietly switched that behaviour on.
      passageOfTimeEnabled: s.passageOfTimeEnabled,
    );
    // Freeze a synthesised story date into the row the FIRST time we invent it.
    // The v38 ladder note promised legacy rows would "synthesize on first
    // load", but nothing wrote the result back, and the synthesis is anchored
    // on the real-world calendar — so the in-story date silently followed
    // whatever day the chat was opened on (96 of 109 sessions in the
    // maintainer's library were still in that state). A full save would have
    // fixed it, but a save only happens when you send a message: opening a
    // chat, reading it and closing it left the date free to move again.
    //
    // A partial patch, not _saveChat(): we are mid-hydration, so writing the
    // whole row here would persist the half-loaded needs/pockets/chaos state
    // that the lines below have not restored yet. Unawaited for the same reason
    // the other load-path writes are — the open path must not block on disk.
    if (_timeService.canonicalClockWasSynthesised) {
      unawaited(
        _db.patchSession(
          SessionsCompanion(
            id: drift.Value(s.id),
            storyClock: drift.Value(_timeService.storyClockIso),
            storyStartDate: drift.Value(_timeService.storyStartDateIso),
            startDayOfWeek: drift.Value(_timeService.startDayOfWeekAnchor),
            timeOfDay: drift.Value(_timeService.timeOfDay),
            dayCount: drift.Value(_timeService.dayCount),
          ),
        ),
      );
    }
    _nsfwService.loadNsfwScalars(
      nsfwCooldownEnabled: s.nsfwCooldownEnabled,
      arousalLevel: s.arousalLevel,
      cooldownTurnsRemaining: s.cooldownTurnsRemaining,
      cooldownTurnsTotal: s.cooldownTurnsTotal,
    );
    _needsSimEnabled = s.needsSimEnabled;
    _objectivesEnabled = s.objectivesEnabled;
    if (_needsSimEnabled) {
      // Seed defaults first, then overlay the saved vector ONLY when it has
      // values. A blank saved vector (e.g. needs was toggled on mid-chat before
      // it seeded) must NOT clobber the defaults, or the sidebar shows no scores.
      _needsSimulation.initializeFresh();
      final nv = s.needsVector;
      final saved = (nv is String && nv.isNotEmpty)
          ? (jsonDecode(nv) as Map).cast<String, int>()
          : <String, int>{};
      if (saved.isNotEmpty) {
        _needsSimulation.restoreFromSnapshot({'vector': saved});
      }
    } else {
      _needsSimulation.clearVector();
    }

    // v47 — restore the 1:1 pockets record. Group members' records ride
    // groupRealismState and are restored with it; this is the half that had no
    // home and so was silently dropped on every reload.
    //
    // Restored regardless of whether Pockets is currently switched on: a
    // record only exists because it was on at the time, and rolling a chat
    // open must not be the thing that empties her hands.
    final pj = s.pockets;
    _pockets = (pj is String && pj.isNotEmpty)
        ? Pockets.fromJson(jsonDecode(pj))
        : null;
    // No saved record means this chat has never run the pass, so fall back to
    // what the card starts her with — otherwise the sidebar reads empty until
    // after the first reply and an author who just set a wardrobe concludes it
    // did not save. Skipped when a record exists: the chat has moved on.
    seedPocketsFromCards();

    _todayObjectiveId = s.todayObjectiveId;
    _todayObjectiveText = null;

    // Re-sync from the character's current setting so that toggling
    // "Enjoys low hygiene" on the character affects existing chats on next load.
    _enjoysLowHygiene =
        _activeCharacter?.frontPorchExtensions?.enjoysLowHygiene ?? false;

    // Load per-chat theme overrides.
    try {
      final themeJson = await _db.getThemeOverrides(s.id);
      _sessionThemeOverrides = ChatThemeOverrides.fromJsonString(themeJson);
    } catch (_) {
      _sessionThemeOverrides = ChatThemeOverrides();
    }

    // Context Budget bars from the last real send (empty on older chats).
    try {
      await _loadContextBudgetForSession(s.id);
    } catch (_) {
      _clearContextBudget();
    }

    _needsSimulation.resetBuffers();
    // Chaos scalars — the shared load is what fixed session-load-refactor.md
    // bug #1 (loadSession never loaded these, so history-picked chats lost
    // Chaos Mode state and pressure reset to defaults).
    _chaosModeService.loadScalars(
      modeEnabled: s.chaosModeEnabled,
      pressure: s.chaosPressure,
    );
    debugPrint(
      '[ChatService] session scalars hydrated: arousal=${_nsfwService.arousalLevel}, fixation=${_relationshipService.activeFixation}/${_relationshipService.fixationLifespan}',
    );

    // Transient-flag zeroing shared by both loaded paths (keep reset blocks in sync).
    _summaryPaused = false;
    _isSummaryGenerating = false;
    _isGrowthPassRunning = false;

    // Cache growth rings (and any not-yet-distilled legacy evolved blobs) for
    // this session so the injection layer can read them synchronously —
    // scoped to the session, not the character (1:1 + group both).
    await _refreshGrowthCache();
  }

  Future<void> loadSession(String sessionId) async {
    if (_activeCharacter == null && _activeGroup == null) return;

    // A reload mid-settle reads rows the finishing turn hasn't persisted yet
    // (chip attach's _saveChat can land AFTER getMessagesForSession below),
    // and that turn's finalization would then write onto the replaced list.
    await _waitForTurnToSettle();
    // Persist the chat we are LEAVING before replacing `_messages` from rows
    // — only when this load actually switches sessions. A SAME-session
    // reload must NOT flush: flushPendingSaves is a full save, so it would
    // stamp the live scalars — the active persona above all — onto the very
    // row this load exists to read back, and the restore below would then
    // "restore" whatever was already live. That broke "reopening a chat
    // restores its persona" everywhere (Rawhide E2E red since 6192ddc:
    // persona_default_test + persona_folder_test; the picker flow after
    // setActiveCharacter hits it because _loadLastSession sets
    // _currentSessionId without activating the persona — by design). The
    // same-session transcript needs no flush here: turns persist when
    // taken, and _waitForTurnToSettle has already drained the save chain.
    if (_currentSessionId != sessionId) {
      await flushPendingSaves();
      _clearTodayPointer();
    }

    // Reset AFK idle state when loading a new session
    _cancelIdleTimer();
    _hasCompletedExchange = false;

    final session = await _db.getSessionById(sessionId);
    if (session == null) return;

    // Speak as the persona this chat was chatted under. A session with no
    // binding (pre-v25 rows) or one naming a persona that has since been
    // DELETED falls back to the default — not to whatever the previously-open
    // chat left behind, which is what the old silent no-op did.
    final sessionPersonaId = session.userPersonaId;
    final knownPersona =
        sessionPersonaId != null &&
        _userPersonaService.personas.any((p) => p.id == sessionPersonaId);
    await _userPersonaService.setActivePersona(
      knownPersona ? sessionPersonaId : _userPersonaService.defaultPersonaId,
    );

    // Load per-chat generation settings override for this session (must
    // happen before the message loop so retroactive sanitization can
    // consult per-chat override + rules).
    _sessionGenSettings = ChatGenerationSettings.fromJsonString(
      session.generationSettings,
    );

    try {
      // Backfill checks `_currentSessionId` so this must be set first.
      _currentSessionId = sessionId;
      await _openSessionMessages(sessionId);

      // Post-load sanitization: force valid swipe indices. This protects
      // against any legacy corrupted rows or previous buggy saves, even if
      // the individual message constructors already clamp.
      for (final msg in _messages) {
        if (msg.swipeIndex < 0 || msg.swipeIndex >= msg.swipes.length) {
          msg.swipeIndex = 0;
        }
      }

      // ── Hydrate hidden group state checkpoint (DB-free: realism + per-char notes) ──
      // The sentinel is stored as the last message for durability but must be
      // stripped from the in-memory list so the UI and prompt builders never see it.
      // (v30: _hydrateGroupRealismCheckpointIfPresent removed — state now loads from DB column)

      await _reloadChatWorldIds();
      // Touch updatedAt so this session becomes the "last active" for the
      // character/group — _loadLastSession sorts by updatedAt DESC.
      _db.patchSession(SessionsCompanion(
        id: drift.Value(sessionId),
        updatedAt: drift.Value(DateTime.now()),
      ));
      // Scene Guests are per-session. Without this, switching to a different
      // session via the history picker leaves the PREVIOUS session's guests
      // (and their evolution/detection state) in place — they keep chiming in
      // and get re-persisted into the loaded session's blob, contaminating it,
      // while this session's own guests are never restored. Mirror the
      // _loadLastSession 1:1 branch: full reset, then load this session's blob.
      if (_activeGroup == null) {
        _sceneGuest.pendingDeparture = null;
        _sceneGuest.pendingPickerFilter = null;
        _resetGuestActivityState();
        _sceneGuest.turnsSinceCastScan = 0;
        _sceneGuest.pendingDetection = null;
        _sceneGuest.offeredOrIgnoredNames.clear();
        // (clears + restores _sceneGuest.ids/_sceneGuest.cards + guest evolution)
        _loadSceneGuestsFromSession(session);
      } else {
        // Group session: restore live per-character realism/needs from the
        // session column — mirrors the _loadLastSession group branch so resuming
        // an OLDER group session via the in-chat history drawer no longer drops
        // each member's bond/trust/emotion/fixation/arousal/needs.
        _loadGroupRealismStateFromSession(session);
      }
      await _hydrateSessionScalars(session);

      // Quests are keyed (character, CHAT) — so switching chats has to reload
      // them, exactly like the scalars above. Nothing did: `_activeObjectives`
      // kept the PREVIOUS chat's rows, which the prompt then injected here
      // while the pre-send completion check wrote (deactivate / task updates,
      // by primary key) back into that other chat's quests. This chat's own
      // quests never appeared at all. The stale comment in `_loadLastSession`
      // — "objectives there are handled by its own callers" — described a
      // caller that never existed; every call site is bare (history drawer,
      // home page, delete-session switch, the web facade). Same both-paths
      // loader block as every other objective entry point; the trio of
      // per-chat counters is zeroed first, matching `_loadLastSession`.
      _activeObjectives = [];
      _messagesSinceLastCheck = 0;
      _isCheckingCompletion = false;
      if (_activeGroup != null) {
        await _loadObjectivesForCurrentSpeaker();
      } else {
        await _loadActiveObjectives();
      }

      // (Lorebook scanLatest already ran inside _hydrateMessagesFromRows —
      // the second scan here was pure duplicate work.)
      notifyListeners();
      // LLMerta porch memories: plant matching Mafia nights + arm force-ack.
      // Fire-and-forget so open path never blocks on disk/DB.
      unawaited(_maybeImportPorchMemories());
    } catch (e) {
      debugPrint('[ChatService] Error loading session $sessionId: $e');
    }
  }

  /// Diary targets for LLMerta porch import: library stableGroupId (match) +
  /// journal characterId (plant key). 1:1 uses the same id for both; group
  /// members match on originStableId and plant under the live card id.
  Future<List<PorchDiaryTarget>> _buildPorchDiaryTargets() async {
    if (_activeGroup == null && _activeCharacter != null) {
      final id = _getCharacterIdFromCard(_activeCharacter!);
      return [
        PorchDiaryTarget(libraryStableGroupId: id, diaryCharacterId: id),
      ];
    }
    if (_activeGroup == null) return const [];

    final repo = _groupChatRepository;
    if (repo == null) {
      // Fall back to live roster stable ids (origin may equal library for
      // many members whose avatar stem matches the library basename).
      return [
        for (final c in _groupCharacters)
          PorchDiaryTarget(
            libraryStableGroupId: _getCharacterIdFromCard(c),
            diaryCharacterId: _getCharacterIdFromCard(c),
          ),
      ];
    }

    final rows = await repo.getMembersForGroup(_activeGroup!.id);
    final library = _characterRepository?.characters ?? const <CharacterCard>[];
    final targets = <PorchDiaryTarget>[];
    for (final m in rows) {
      if (m.avatarFilename == null) continue;
      final resolvedPath = path.join(
        _storageService.groupsDir.path,
        _activeGroup!.id,
        'avatars',
        m.avatarFilename!,
      );
      final diaryId = path.basenameWithoutExtension(resolvedPath);
      final origin = m.originStableId;
      final matchId = (origin != null && origin.isNotEmpty)
          ? origin
          : (MemberOriginResolver.resolve(
                  stampedOriginStableId: null,
                  memberName: m.name,
                  libraryCharacters: library,
                )?.stableGroupId ??
                diaryId);
      targets.add(
        PorchDiaryTarget(
          libraryStableGroupId: matchId,
          diaryCharacterId: diaryId,
        ),
      );
    }
    return targets;
  }

  /// Scan mailbox and plant into this session; never throws into open path.
  Future<void> _maybeImportPorchMemories() async {
    final sessionId = _currentSessionId;
    if (sessionId == null) return;
    final personaId = _userPersonaService.persona.id;
    if (personaId.isEmpty) return;
    try {
      final targets = await _buildPorchDiaryTargets();
      if (targets.isEmpty) return;
      await _porchMemoryImport.tryImportForSession(
        sessionId: sessionId,
        userPersonaId: personaId,
        targets: targets,
      );
    } catch (e) {
      debugPrint('[PorchMemories] session hook failed: $e');
    }
  }
}
