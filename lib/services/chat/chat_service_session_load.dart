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

/// Session load + listing — last-session, history list, loadSession.
/// Hydrate (messages, scalars, persona, porch diary) lives in
/// [ChatServiceSessionHydrate].
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
    // Activate THIS row's persona before _currentSessionId is set and
    // before overlay-reapply / any hydrate save. setActiveCharacter then
    // loadSession used to stamp the still-live previous chat (Nightowl)
    // onto the first row; loadSession then skipped flush (same id) and
    // "restored" Nightowl. Default is unmoved — setActivePersona is
    // chat-scoped. Keep loadSession's restore too.
    await _activateSessionPersona(lastSession);
    // Stale unauthored RtR from a prior opening must not paint this hydrate.
    await _invalidateGreetingEval();
    _preserveSessionPersonaOf[this] = true;
    try {
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
      await _reapplyOpeningOverlayIfNeeded();
    } finally {
      _preserveSessionPersonaOf[this] = false;
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
    unawaited(_ensureBirthdayState());
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
    final stats = await _db.getSessionListStats([
      for (final s in dbSessions) s.id,
    ]);

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
    // setActiveCharacter then loadSession used to hit it because
    // _loadLastSession set _currentSessionId before activating the
    // persona). The same-session transcript needs no flush here: turns
    // persist when taken, and _waitForTurnToSettle has already drained
    // the save chain. _loadLastSession now activates the row persona
    // before any hydrate save; the restore below still runs.
    if (_currentSessionId != sessionId) {
      await flushPendingSaves();
      _clearTodayPointer();
    }

    // Reset AFK idle state when loading a new session
    _cancelIdleTimer();
    _hasCompletedExchange = false;

    final session = await _db.getSessionById(sessionId);
    if (session == null) return;

    // Any path that loads a new opening first_mes must bump _greetingEvalGen
    // before hydrate / _reapplyOpeningOverlayIfNeeded. _waitForTurnToSettle
    // only drains _isTurnBusy, so a delayed unauthored RtR would still have
    // a live Zone token and paint fury onto the loaded opening.
    await _invalidateGreetingEval();

    // Speak as the persona this chat was chatted under. A session with no
    // binding (pre-v25 rows) or one naming a persona that has since been
    // DELETED falls back to the default — not to whatever the previously-open
    // chat left behind, which is what the old silent no-op did.
    await _activateSessionPersona(session);

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
      _db.patchSession(
        SessionsCompanion(
          id: drift.Value(sessionId),
          updatedAt: drift.Value(DateTime.now()),
        ),
      );
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
      await _reapplyOpeningOverlayIfNeeded();

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
      unawaited(_ensureBirthdayState());
    } catch (e) {
      debugPrint('[ChatService] Error loading session $sessionId: $e');
    }
  }
}
