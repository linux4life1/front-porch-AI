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

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import 'package:front_porch_ai/database/database.dart' hide AvatarImage, World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/services/chat/doors/cast/cast_door.dart';

import 'session_store.dart';

/// Session load and listing: the last session of a cast, the history list,
/// opening a chosen chat, and the switch guard both share with New chat.
class SessionLoader {
  SessionLoader(this._d, this._store);

  final SessionDeps _d;
  final SessionStore _store;

  ChatSessionState get _session => _d.session;
  SessionServices get _s => _d.services;
  SessionShellHooks get _h => _d.hooks;
  AppDatabase get _db => _s.db();
  GroupChat? get _activeGroup => _session.activeGroup;
  CastDoor get _cast => _s.cast();
  TimeService get _timeService => _s.realism().time();

  Future<void> loadLastSession() async {
    // NOTE: This method contains multiple await boundaries (DB queries).
    // If the user rapidly switches characters/groups, Dart's cooperative
    // scheduler may interleave a second setActiveCharacter call during one
    // of these awaits. The sanitizer below runs synchronously on already-
    // fetched local variables (swipes), so it does not introduce a new race
    // window — but it also cannot prevent pre-existing interleaving where
    // the later load overwrites the session's messages.
    if (_session.activeCharacter == null && _activeGroup == null) return;

    // Get sessions from DB
    List<Session> sessions;
    if (_activeGroup != null) {
      sessions = await _db.getSessionsForGroup(_activeGroup!.id);
    } else if (_session.activeCharacter?.dbId != null) {
      sessions = await _db.getSessionsForCharacter(
        _session.activeCharacter!.dbId!,
      );
    } else {
      return;
    }

    if (sessions.isEmpty) {
      debugPrint('[Chat] _loadLastSession: No previous sessions found');
      // Ensure no stale fork/parent state remains from a prior character/group.
      _store.parentSessionId = null;
      _store.forkIndex = null;
      // Expression runtime (manual/caches) reset on no-prior-session to
      // prevent bleed (matches fork/parent hygiene).
      _s.expression().resetForFreshChat();
      // Time (passage, weekday anchors, turns, day/time scalars), Nsfw
      // (cooldown/arousal) and lorebook triggers/depth reset for fresh
      // 0-session/new-group paths, so advanced state from a prior 1:1 never
      // bleeds into a fresh group. Keep reset blocks in sync with
      // setActiveGroup, both startNewChat branches and setActiveCharacter.
      _timeService.resetForFreshChat();
      _store.today.clearTodayPointer();
      // Fresh GROUP session: apply the group's authored scene-time seed on
      // top of the reset (story-calendar "As built" gap fix — the wizard's
      // time seed used to be editor-carried only and never reached the
      // clock). Keep in sync with the startNewChat group branch.
      if (_activeGroup != null) {
        _s.realism().groups.afterglowOn = groupAfterglowIn(
          _activeGroup!.defaultMemberRealismState,
        );
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
          );
          _s.graph().applySeededPassageOfTime();
        }
      }
      _s.realism().nsfw().resetForFreshChat();
      _s.lorebook().resetLorebookTriggerState();
      _s.objectives().resetForChatSwitch();
      // Secondary zeros for the 0-session early return (keep reset blocks
      // in sync).
      _store.summaryPaused = false;
      _store.isSummaryGenerating = false;
      _s.graph().growthPassRunning = false;
      _s.growthStore().invalidate(); // no session — nothing to inject
      _store.selectedLooks.clear(); // 0-session: no per-chat look selection
      // 0-session: no per-chat gen overrides — without this, character B's
      // first chat ran (and could SAVE) character A's temp/stops/sanitizer.
      _store.genSettings = ChatGenerationSettings();
      _h.armPromptPicker(); // prompt-picker SOW: a card with no saved session is a new chat
      _h.clearContextBudget();
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
    // Activate THIS row's persona before the session id is set and before
    // overlay-reapply / any hydrate save. setActiveCharacter then
    // loadSession used to stamp the still-live previous chat (Nightowl)
    // onto the first row; loadSession then skipped flush (same id) and
    // "restored" Nightowl. Default is unmoved — setActivePersona is
    // chat-scoped. Keep loadSession's restore too.
    await _store.scalars.activateSessionPersona(lastSession);
    // Stale unauthored RtR from a prior opening must not paint this hydrate.
    await _cast.greetings.invalidateGreetingEval();
    _store.preserveSessionPersona = true;
    try {
      _session.currentSessionId = lastSession.id;
      // Sanitizer + first paint need gen settings and the tail ONLY.
      // Growth/worlds/scalars used to run first and kept the spinner up
      // for the same beat as loading 11k messages.
      _store.genSettings = ChatGenerationSettings.fromJsonString(
        lastSession.generationSettings,
      );
      try {
        await _store.hydrator.openSessionMessages(lastSession.id);
      } catch (e) {
        print('Error loading chat session: $e');
      }
      await _s.graph().places.reload();
      await _store.scalars.hydrate(lastSession);

      // v30: Load live per-character group realism/needs (bond/trust/emotion/fixation/arousal/relationships/needs)
      // from the session column (or fall back to group defaults). Must happen for group entry paths
      // so that the group map is populated before any eval, prompt injection, or UI read.
      if (_activeGroup != null) {
        if (await _store.groupState.loadGroupRealismState(lastSession)) {
          await _store.save();
        }
      } else {
        // 1:1 session: the group realism column ('{}' for plain sessions) may
        // carry persisted Scene Guest (Lite NPC) dbIds. Tolerant of legacy/empty.
        _store.groupState.loadSceneGuests(lastSession);
      }
      await _cast.greetings.reapplyOpeningOverlayIfNeeded();
      await _s.clockWriter().reloadSessionClockThenSync(lastSession);
    } finally {
      _store.preserveSessionPersona = false;
    }

    // Zero the per-chat objective trio in the loaded path (before callers
    // load the objectives). loadSession zeroes and reloads this trio itself,
    // right after the scalar hydrate; the two paths differ in WHEN the
    // loader runs, not whether, so the trio stays out of the shared hydrate.
    _s.objectives().resetForChatSwitch();

    // LLMerta porch memories on last-session open (same as loadSession).
    unawaited(_store.scalars.maybeImportPorchMemories());
    unawaited(_s.birthdays().ensure());
    scoreStartIfSavedBlocked(lastSession);
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
    if (_session.activeCharacter == null && _activeGroup == null) return [];
    final charId = _h.ragCharacterId();
    return getSessionsForId(charId);
  }

  /// Open a fresh chat for the open cast. See [NewChatOpener.open].
  Future<void> startNewChat({String? personaId}) =>
      _whileSwitchingChat(() async {
        // A streaming reply is cut, as on entering a character; one still
        // settling finishes in the chat it started in.
        await _h.cancelAndWaitForGeneration();
        await _h.waitForTurnToSettle();
        await _store.newChat.open(personaId: personaId);
      });

  Future<void> loadSession(String sessionId) =>
      _whileSwitchingChat(() => _openSession(sessionId));

  /// Refuses sends across an in-chat switch, as entering a character or group
  /// does. A send (a `/join` included) that lands mid-switch gets "The chat is
  /// still opening." instead of starting in one chat and finishing in the
  /// next: a New chat mints its id twice, so a join that slipped in between
  /// lost its "joined the scene" line and could lose the guest too. Not the
  /// session-load flag: that would also hold the history backfill back.
  Future<void> _whileSwitchingChat(Future<void> Function() body) async {
    _store.chatSwitches++;
    try {
      await body();
    } finally {
      _store.chatSwitches--;
    }
  }

  Future<void> _openSession(String sessionId) async {
    if (_session.activeCharacter == null && _activeGroup == null) return;

    // A reload mid-settle reads rows the finishing turn hasn't persisted yet
    // (chip attach's save can land AFTER getMessagesForSession below),
    // and that turn's finalization would then write onto the replaced list.
    await _h.waitForTurnToSettle();
    // Persist the chat we are LEAVING before replacing the messages from
    // rows — only when this load actually switches sessions. A SAME-session
    // reload must NOT flush: flushPendingSaves is a full save, so it would
    // stamp the live scalars — the active persona above all — onto the very
    // row this load exists to read back, and the restore below would then
    // "restore" whatever was already live. That broke "reopening a chat
    // restores its persona" everywhere (Rawhide E2E red since 6192ddc:
    // persona_default_test + persona_folder_test; the picker flow after
    // setActiveCharacter then loadSession used to hit it because
    // loadLastSession set the session id before activating the persona).
    // The same-session transcript needs no flush here: turns persist when
    // taken, and waitForTurnToSettle has already drained the save chain.
    // loadLastSession now activates the row persona before any hydrate
    // save; the restore below still runs.
    if (_session.currentSessionId != sessionId) {
      _timeService.clearCapturedClock();
      await _store.save();
      _store.today.clearTodayPointer();
    }

    // Reset AFK idle state when loading a new session
    _cast.idle.cancelIdleTimer();
    _cast.idle.hasCompletedExchange = false;
    _cast.away.state.reset();

    final session = await _db.getSessionById(sessionId);
    if (session == null) return;

    // Any path that loads a new opening first_mes must bump the greeting
    // eval generation before hydrate / reapplyOpeningOverlayIfNeeded.
    // waitForTurnToSettle only drains the busy turn, so a delayed
    // unauthored RtR would still have a live Zone token and paint fury onto
    // the loaded opening.
    await _cast.greetings.invalidateGreetingEval();

    // Speak as the persona this chat was chatted under. A session with no
    // binding (pre-v25 rows) or one naming a persona that has since been
    // DELETED falls back to the default — not to whatever the previously-open
    // chat left behind, which is what the old silent no-op did.
    await _store.scalars.activateSessionPersona(session);

    // Load per-chat generation settings override for this session (must
    // happen before the message loop so retroactive sanitization can
    // consult per-chat override + rules).
    _store.genSettings = ChatGenerationSettings.fromJsonString(
      session.generationSettings,
    );

    // Same-session reload (model switch, settings, DB rebind) used to
    // replace the live recap with whatever the row still held. A journal
    // pass or a sidebar edit can be ahead of that row. Keep the live text
    // and write it through so the next open still has it.
    final sameSession = _session.currentSessionId == sessionId;
    final liveRecap = sameSession ? _store.summary : '';
    try {
      // Backfill checks the session id so this must be set first.
      _session.currentSessionId = sessionId;
      await _store.hydrator.openSessionMessages(sessionId);

      // Post-load sanitization: force valid swipe indices. This protects
      // against any legacy corrupted rows or previous buggy saves, even if
      // the individual message constructors already clamp.
      for (final msg in _session.messages) {
        if (msg.swipeIndex < 0 || msg.swipeIndex >= msg.swipes.length) {
          msg.swipeIndex = 0;
        }
      }

      await _s.graph().places.reload();
      // Touch updatedAt so this session becomes the "last active" for the
      // character/group — loadLastSession sorts by updatedAt DESC.
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
      // loadLastSession 1:1 branch: full reset, then load this session's blob.
      var rekeyedGroupStores = false;
      if (_activeGroup == null) {
        final guests = _cast.guests;
        guests.state.pendingDeparture = null;
        guests.state.pendingPickerFilter = null;
        guests.resetActivityState();
        guests.state.turnsSinceCastScan = 0;
        guests.state.pendingDetection = null;
        guests.state.offeredOrIgnoredNames.clear();
        _s.sceneMoves
            .reset(); // Slice 6: stale offers die with the session too.
        // (clears + restores the guest ids/cards + guest evolution)
        _store.groupState.loadSceneGuests(session);
      } else {
        // Group session: restore live per-character realism/needs from the
        // session column — mirrors the loadLastSession group branch so resuming
        // an OLDER group session via the in-chat history drawer no longer drops
        // each member's bond/trust/emotion/fixation/arousal/needs.
        rekeyedGroupStores = await _store.groupState.loadGroupRealismState(
          session,
        );
      }
      await _store.scalars.hydrate(session);
      if (rekeyedGroupStores) {
        await _store.save();
      }
      if (sameSession && liveRecap.isNotEmpty && _store.summary != liveRecap) {
        _store.summary = liveRecap;
        await _s.journal().persistRecap(sessionId, liveRecap);
      }
      await _cast.greetings.reapplyOpeningOverlayIfNeeded();
      await _s.clockWriter().reloadSessionClockThenSync(session);

      // Quests are keyed (character, CHAT) — so switching chats has to reload
      // them, exactly like the scalars above. Nothing did: the loaded objectives
      // kept the PREVIOUS chat's rows, which the prompt then injected here
      // while the pre-send completion check wrote (deactivate / task updates,
      // by primary key) back into that other chat's quests. This chat's own
      // quests never appeared at all. Every call site is bare (history drawer,
      // home page, delete-session switch, the web facade). Same both-paths
      // loader block as every other objective entry point; the trio of
      // per-chat counters is zeroed first, matching loadLastSession.
      final objectives = _s.objectives();
      objectives.resetForChatSwitch();
      if (_activeGroup != null) {
        await objectives.loadObjectivesForCurrentSpeaker();
      } else {
        await objectives.loadActiveObjectives();
      }

      // (Lorebook scanLatest already ran inside the row hydrate — the second
      // scan here was pure duplicate work.)
      _d.notify();
      // LLMerta porch memories: plant matching Mafia nights + arm force-ack.
      // Fire-and-forget so open path never blocks on disk/DB.
      unawaited(_store.scalars.maybeImportPorchMemories());
      unawaited(_s.birthdays().ensure());
      scoreStartIfSavedBlocked(session);
    } catch (e) {
      debugPrint('[Chat] Error loading session $sessionId: $e');
    }
  }

  /// Opening [s]: a 1:1 chat saved while Porch Life blocked Realism, or one
  /// the existing-chats question switched on while it was closed, never ran
  /// Realism there, so it scores its starting point now: one eval per such
  /// chat opened, none on an install that never blocked Realism.
  void scoreStartIfSavedBlocked(Session s) {
    final rs = _s.storage.realismSettings;
    final owed = rs.realismStartOwed.contains(s.id);
    if (!owed && !rs.savedWhileRealismBlocked(s.updatedAt)) return;
    if (owed) unawaited(rs.settleRealismStart(s.id));
    _h.onRealismStarted();
  }
}
