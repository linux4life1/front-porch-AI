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

import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/database/database.dart' hide AvatarImage, World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';

import 'session_store.dart';

/// Rename, description, fork, and the new-session world seed.
class SessionForker {
  SessionForker(this._d, this._store);

  final SessionDeps _d;
  final SessionStore _store;

  ChatSessionState get _session => _d.session;
  SessionServices get _s => _d.services;
  AppDatabase get _db => _s.db();
  GroupChat? get _activeGroup => _session.activeGroup;

  /// Seed a NEW session's attached worlds (Living Worlds). Forks pass
  /// [carryRefs] to keep the parent chat's attachments; otherwise groups copy
  /// the group template and 1:1 chats copy the character's attached worlds —
  /// so a card paired with a world starts in that world's climate/setting
  /// instead of silently defaulting to temperate. Always reloads the ids +
  /// biome schedule so a fresh session can't inherit the previous chat's
  /// list. Called at every session-creation site: fresh 1:1/group entry,
  /// forkSession, both startNewChat branches, and SillyTavern import.
  Future<void> seedChatWorldsForNewSession({List<String>? carryRefs}) async {
    final sid = _session.currentSessionId;
    if (sid == null) return;
    final refs =
        carryRefs ??
        (_activeGroup != null
            ? _activeGroup!.worldIds
            : (_session.activeCharacter?.worldNames ?? const <String>[]));
    // A split group or card names its Setting and Lore apart; null keeps the
    // flat legacy seed for templates nobody has re-saved.
    final loreRefs = carryRefs != null
        ? null
        : (_activeGroup != null
              ? _activeGroup!.loreWorldIds
              : _session.activeCharacter?.loreWorldNames);
    try {
      if (refs.isNotEmpty || (loreRefs?.isNotEmpty ?? false)) {
        // A fork carries the parent's slots as they stand: a scene the
        // user moved up to the world itself must not jump to its star.
        await _s.worlds.applyTemplateWorldsToChat(
          sid,
          refs,
          startAtStar: carryRefs == null,
          loreRefs: loreRefs,
        );
      }
      // Even when a fresh chat legitimately gets NO worlds, that is a decision
      // — record it so a later back-fill can't override it.
      await _s.worlds.markChatWorldsDecided(sid);
    } catch (e) {
      debugPrint('[Chat] chat world seed failed: $e');
    }
    await _s.graph().places.reload();
  }

  /// Re-read this chat's attached worlds from the database. Needed when
  /// something OUTSIDE the chat changes them — adding a world to a character
  /// back-fills that character's chats that had none, and an already-open
  /// conversation should pick up the new climate without being reopened.
  Future<void> refreshChatWorlds() async {
    await _s.graph().places.reload();
    _d.notify();
  }

  /// Rename a session.
  Future<void> renameSession(String sessionId, String name) async {
    final session = await _db.getSessionById(sessionId);
    if (session == null) return;

    await _db.patchSession(
      SessionsCompanion(
        id: drift.Value(sessionId),
        name: drift.Value(name.isEmpty ? null : name),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );

    // Update in-memory if this is the current session
    if (sessionId == _session.currentSessionId) {
      _store.sessionName = name.isEmpty ? null : name;
      _d.notify();
    }
  }

  /// Update the description of a session.
  Future<void> updateSessionDescription(
    String sessionId,
    String description,
  ) async {
    final session = await _db.getSessionById(sessionId);
    if (session == null) return;

    await _db.patchSession(
      SessionsCompanion(
        id: drift.Value(sessionId),
        description: drift.Value(description.isEmpty ? null : description),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );

    // Update in-memory if this is the current session
    if (sessionId == _session.currentSessionId) {
      _store.sessionDescription = description.isEmpty ? null : description;
      _d.notify();
    }
  }

  /// Create a new session by forking from message at [messageIndex].
  /// Copies messages 0..messageIndex into a new session and switches to it.
  Future<void> forkFromMessage(int messageIndex) async {
    if ((_session.activeCharacter == null && _activeGroup == null) ||
        _session.currentSessionId == null) {
      return;
    }
    final tip = await _store.window.resolveHydratedIndex(messageIndex);
    if (tip == null) return;
    final parentStart = _s.realism().time().startDate;

    // Near-miss: fork copies the live greeting so eval would land on the
    // same alt, but this is a new session opening. Bump gen before the
    // forked transcript is live.
    await _s.cast().greetings.invalidateGreetingEval();

    final oldSessionId = _session.currentSessionId!;
    _store.today.clearTodayPointer();
    final forkedMessages = _session.messages
        .sublist(0, tip + 1)
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
      '[Chat] 🟡 forkSession: clearing messages for fork at index $messageIndex',
    );
    _session.messages.clear();
    _session.messages.addAll(forkedMessages);
    _store.history.reset();
    _session.currentSessionId = DateTime.now().millisecondsSinceEpoch
        .toString();
    _store.computeAbsenceGap(
      const [],
    ); // fresh session — no real-world gap (Living Time §2)
    // Forks stay in the parent chat's place: carry the world attachments so
    // the climate/setting follow (mid-chat climate spans reset to the world
    // default, like every other new session).
    await seedChatWorldsForNewSession(
      carryRefs: _s.graph().places.slots.allIds,
    );
    await _s.media().copyWikiForForkedSession(oldSessionId);
    _store.parentSessionId = oldSessionId;
    _store.forkIndex = tip;
    _store.genSettings = _store.genSettings
        .copy(); // inherit parent's overrides
    _store.summary = '';
    // Cards were copied for the kept prefix; start the cursor at the
    // fork tip so the next pass does not re-digest those same messages
    // (import uses the same rule).
    _store.summaryLastIndex = _session.messages.length;
    // Fork hygiene (keep reset blocks in sync): no per-chat look selection,
    // and the secondary summary and growth flags zeroed on the new branch.
    _store.selectedLooks.clear();
    _store.summaryPaused = false;
    _store.isSummaryGenerating = false;
    _s.graph().growthPassRunning = false;

    // Time-travel: stamped after, else before+chip, else snap, else
    // before. Unstamped Carmen tip keeps the live clock. Stamp-less
    // (legacy/ST): rewind bond/emotion/arousal from the card but keep
    // per-chat feature toggles and fork lineage.
    if (_session.messages.isNotEmpty) {
      await _store.walk.restoreWalkingBack(
        fromIndex: _session.messages.length - 1,
        seedClockIfUnstamped: true,
      );
      _s.clockWriter().applyForkPointClock(parentStartDate: parentStart);
    }

    await _store.save();
    // Growth rings carry into the fork like the rest of the character's
    // history (the old evolved text carried the same way). Runs after
    // the save so the new session row exists for the legacy-blob copy.
    await _s.growthStore().copySessionTo(
      oldSessionId,
      _session.currentSessionId!,
      cursor: _session.messages.length,
    );
    await _s.journal().copySessionTo(
      oldSessionId,
      _session.currentSessionId!,
      cursor: _session.messages.length,
    );
    await _s.growthDesk().refreshCache();
    _d.notify();
  }
}
