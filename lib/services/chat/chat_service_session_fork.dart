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

/// Rename, description, fork, and new-session world seed.
extension ChatServiceSessionFork on ChatService {
  /// Seed a NEW session's attached worlds (Living Worlds). Forks pass
  /// [carryRefs] to keep the parent chat's attachments; otherwise groups copy
  /// the group template and 1:1 chats copy the character's attached worlds —
  /// so a card paired with a world starts in that world's climate/setting
  /// instead of silently defaulting to temperate. Always reloads the ids +
  /// biome schedule so a fresh session can't inherit the previous chat's
  /// list. Called at every session-creation site: fresh 1:1/group entry,
  /// forkSession, both startNewChat branches, and SillyTavern import.
  Future<void> _seedChatWorldsForNewSession({List<String>? carryRefs}) async {
    final sid = _currentSessionId;
    if (sid == null) return;
    final refs =
        carryRefs ??
        (_activeGroup != null
            ? _activeGroup!.worldIds
            : (_activeCharacter?.worldNames ?? const <String>[]));
    try {
      if (refs.isNotEmpty) {
        await _worldRepository.applyTemplateWorldsToChat(sid, refs);
      }
      // Even when a fresh chat legitimately gets NO worlds, that is a decision
      // — record it so a later back-fill can't override it.
      await _worldRepository.markChatWorldsDecided(sid);
    } catch (e) {
      debugPrint('[ChatService] chat world seed failed: $e');
    }
    await _reloadChatWorldIds();
  }

  /// Re-read this chat's attached worlds from the database. Needed when
  /// something OUTSIDE the chat changes them — adding a world to a character
  /// back-fills that character's chats that had none, and an already-open
  /// conversation should pick up the new climate without being reopened.
  Future<void> refreshChatWorlds() async {
    await _reloadChatWorldIds();
    notifyListeners();
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

    await _db.patchSession(
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
    final tip = await _resolveHydratedIndex(messageIndex);
    if (tip == null) return;

    // Near-miss: fork copies the live greeting so eval would land on the
    // same alt, but this is a new session opening. Bump gen before the
    // forked transcript is live.
    await _invalidateGreetingEval();

    final oldSessionId = _currentSessionId!;
    _clearTodayPointer();
    final forkedMessages = _messages
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
      '[ChatService] 🟡 forkSession: clearing messages for fork at index $messageIndex',
    );
    _messages.clear();
    _messages.addAll(forkedMessages);
    _history.reset();
    _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _computeAbsenceGap(
      const [],
    ); // fresh session — no real-world gap (Living Time §2)
    // Forks stay in the parent chat's place: carry the world attachments so
    // the climate/setting follow (mid-chat climate spans reset to the world
    // default, like every other new session).
    await _seedChatWorldsForNewSession(carryRefs: _chatPlaceSlots.allIds);
    await _copyWikiForForkedSession(oldSessionId);
    _parentSessionId = oldSessionId;
    _forkIndex = tip;
    _sessionGenSettings = _sessionGenSettings
        .copy(); // inherit parent's overrides
    _summary = '';
    // Cards were copied for the kept prefix; start the cursor at the
    // fork tip so the next pass does not re-digest those same messages
    // (import uses the same rule).
    _summaryLastIndex = _messages.length;
    _selectedLooks
        .clear(); // fork starts with no per-chat look selection (keep reset blocks in sync)
    _summaryPaused =
        false; // explicit secondary zero for _summaryPaused (symmetric to generating; fork hygiene + incomplete zeroing now complete)
    _isSummaryGenerating =
        false; // zero secondary flag on fork (new branch hygiene, matches summary scalar reset)
    _isGrowthPassRunning =
        false; // growth-pass flag zero on fork (new branch hygiene; keep reset blocks in sync)

    // Time-travel: restore from nearest realism_state in the kept prefix.
    // Stamp-less (legacy/ST): rewind bond/time/emotion/arousal from the card
    // but keep per-chat feature toggles (Realism/Needs/Objectives/Chaos) and
    // fork lineage — never tip-of-chat scalar bleed, never toggle wipe.
    if (_messages.isNotEmpty) {
      await _restoreRealismStateWalkingBack(fromIndex: _messages.length - 1);
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
    await _journalStore.copySessionTo(
      oldSessionId,
      _currentSessionId!,
      cursor: _messages.length,
    );
    await _refreshGrowthCache();
    notifyListeners();
  }
}
