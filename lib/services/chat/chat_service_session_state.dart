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

/// Session-state load/save — scene-guest + group-realism hydration and _saveChat/_doSaveChat. Extracted verbatim (zero behaviour change) to shrink the god file.
extension ChatServiceSessionState on ChatService {
  // v30: Load per-character group realism/needs state.
  // Priority:
  // 1. Live state from the current session's group_realism_state column (if present and non-empty).
  // 2. Default state from the group's default_member_realism_state (important for Group Card imports and new sessions).
  //
  // Pass null for `session` to force-load from group defaults only (used for brand-new group chats).
  /// Restore Scene Guest (Lite NPC) dbIds for a 1:1 session from the reused
  /// group realism column, then resolve their cards. Tolerant of missing,
  /// empty, '{}', legacy group state, or malformed JSON (clears guests).
  void _loadSceneGuestsFromSession(Session? session) {
    _sceneGuestIds.clear();
    _sceneGuestCards.clear();
    final stateJson = session?.groupRealismState;
    // Timed lorebook effects ride the same blob — hydrate (resets first, so
    // a null/empty session clears any prior chat's timers).
    _loreTimedEffects.hydrate(stateJson);
    if (stateJson == null || stateJson.isEmpty || stateJson == '{}') return;
    try {
      final decoded = jsonDecode(stateJson);
      if (decoded is Map && decoded['sceneGuests'] is List) {
        for (final id in decoded['sceneGuests'] as List) {
          final s = id?.toString();
          if (s != null && s.isNotEmpty) _sceneGuestIds.add(s);
        }
      }
      // (The old 'guestEvolution' key is no longer read — guest growth lives
      // in the growth_rings table now, keyed by the guest's stable charId.)
    } catch (e) {
      debugPrint('[SceneGuest] Failed to parse sceneGuests from session: $e');
      return;
    }
    if (_sceneGuestIds.isNotEmpty) {
      // Fire-and-forget resolve; UI updates via notifyListeners inside.
      _resolveSceneGuestCards();
    }
  }

  void _loadGroupRealismStateFromSession(Session? session) {
    if (_activeGroup == null) return;

    String? stateJson = session?.groupRealismState;

    // Timed lorebook effects ride the SESSION blob only (never the group's
    // default-member-state fallback below — defaults carry no chat timers).
    _loreTimedEffects.hydrate(stateJson);

    // Fall back to group definition defaults (crucial for imported Group Cards and split-to-solo)
    if (stateJson == null || stateJson.isEmpty || stateJson == '{}') {
      stateJson = _activeGroup!.defaultMemberRealismState;
    }

    _groupRealism = {};
    _groupDecayRates = {};
    _groupAuthorNotes = {};
    _groupAuthorNoteStrengths = {};
    _groupCharacterSystemPrompts = {};
    _groupCharacterRAGPriorities = {};

    if (stateJson.isNotEmpty && stateJson != '{}') {
      try {
        final decoded = jsonDecode(stateJson);
        if (decoded is Map) {
          final map = Map<String, dynamic>.from(decoded);

          // Main per-character realism data (needs, emotion, bond, trust, fixation, relationships, arousal, etc.)
          final perChar =
              map['perChar'] ??
              map; // support both wrapped and direct formats during transition
          if (perChar is Map) {
            _groupRealism = perChar.map(
              (k, v) =>
                  MapEntry(k.toString(), Map<String, dynamic>.from(v as Map)),
            );
          }

          // Global group decay rates
          final globalDecay = map['globalDecayRates'];
          if (globalDecay is Map) {
            _groupDecayRates = globalDecay.map(
              (k, v) => MapEntry(k.toString(), (v as num).toInt()),
            );
          }

          // Per-char author notes (scoped to this group)
          final notes = map['authorNotes'];
          if (notes is Map) {
            _groupAuthorNotes = notes.map(
              (k, v) => MapEntry(k.toString(), (v ?? '').toString()),
            );
          }

          final strengths = map['authorNoteStrengths'];
          if (strengths is Map) {
            _groupAuthorNoteStrengths = strengths.map(
              (k, v) => MapEntry(
                k.toString(),
                (v as num?)?.toInt() ?? _authorNoteStrength,
              ),
            );
          }

          final sysPrompts = map['characterSystemPrompts'];
          if (sysPrompts is Map) {
            _groupCharacterSystemPrompts = sysPrompts.map(
              (k, v) => MapEntry(k.toString(), (v ?? '').toString()),
            );
          }

          // RAG settings (now also in the column)
          if (map.containsKey('ragEnabled')) {
            _groupRagEnabled = map['ragEnabled'] as bool? ?? true;
          }
          if (map.containsKey('retrievalCount')) {
            _groupRetrievalCount =
                (map['retrievalCount'] as num?)?.toInt() ?? 8;
          }
          if (map.containsKey('memoryBudgetPercent')) {
            _groupMemoryBudgetPercent =
                (map['memoryBudgetPercent'] as num?)?.toDouble() ?? 10.0;
          }

          final ragPrios = map['characterRAGPriorities'];
          if (ragPrios is Map) {
            _groupCharacterRAGPriorities = ragPrios.map(
              (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
            );
          }

          // Per-char objectives for group mode (each member has independent tasks)
          _groupObjectives.clear();
          final objMap = map['objectives'];
          if (objMap is Map) {
            objMap.forEach((charId, list) {
              if (list is List) {
                _groupObjectives[charId.toString()] = [];
              }
            });
          }

          // One-time seeding of objectives from an imported Group Card is handled
          // asynchronously after this state load completes (see callers of this method).

          debugPrint(
            '[GroupState v30] Loaded realism state for ${_groupRealism.length} characters '
            '(session + group defaults) for group ${_activeGroup!.name}',
          );
        }
      } catch (e) {
        debugPrint(
          '[GroupState v30] Failed to parse group realism state JSON: $e',
        );
        _groupRealism = {};
      }
    }
  }

  Future<void> _saveChat() async {
    // catchError keeps the chain alive: without it, one _doSaveChat throw
    // (SQLite busy from an external writer, session nulled mid-save, …) turns
    // _saveChain into an errored future, and every later save chained onto it
    // silently never runs again for the rest of the app session.
    _saveChain = _saveChain.then((_) => _doSaveChat()).catchError((Object e) {
      debugPrint('[ChatService] ⚠ _doSaveChat failed — save skipped: $e');
    });
    await _saveChain;
  }

  /// Shutdown flush: guarantee the current in-memory chat state — most
  /// importantly the just-applied Needs vector and Realism scalars from the
  /// last turn — is durably on disk before the process exits.
  ///
  /// Why this exists: the post-generation Needs deltas are applied to
  /// `_needsSimulation.vector` in memory and only reach the DB through
  /// `_saveChat()`. Several `_saveChat()` calls across the service are
  /// fire-and-forget (`unawaited`, `Future.microtask`, non-awaited setters), so
  /// the write carrying the last message's post-impact vector can still be
  /// queued or mid-commit when the user closes the window. Before this flush,
  /// `onWindowClose` tore down backends and called `exit(0)` without waiting,
  /// killing that pending write — the message text survived (saved earlier,
  /// pre-impact) but the sidebar levels reverted on reopen. That was the
  /// intermittent "the needs deltas from the last message didn't stick" bug.
  ///
  /// Awaiting `_saveChat()` here drains every already-queued save on
  /// `_saveChain` (so nothing in flight is dropped) and then writes the live
  /// state one final time — bounded and fast (a few SQLite writes). Safe to
  /// call with no active chat: `_doSaveChat` no-ops when there is no session or
  /// no messages.
  Future<void> flushPendingSaves() => _saveChat();

  Future<void> _doSaveChat() async {
    if ((_activeCharacter == null && _activeGroup == null) ||
        _currentSessionId == null) {
      return;
    }

    // ── Safety guard: never overwrite existing session data with empty messages.
    // This prevents data loss if _messages is momentarily empty due to a rebuild
    // race, nav glitch, or any other transient state issue.
    if (_messages.isEmpty) {
      debugPrint(
        '[ChatService] ⚠ _saveChat called with empty messages for '
        'session $_currentSessionId — skipping to protect existing data.',
      );
      return;
    }

    // Capture the session identity ONCE. Everything below — especially code
    // that runs after an await — must use this local, never _currentSessionId:
    // loadSession/setActiveCharacter flip the live field synchronously, so a
    // re-read after an await once deleted the NEW session's messages and
    // replaced them with this (old) snapshot — cross-chat data loss. The
    // per-session gen settings are captured for the same reason.
    final sessionId = _currentSessionId!;
    final genSettingsJson = _sessionGenSettings.toJsonString();

    // v30: For group chats, serialize current per-character realism state into the
    // new group_realism_state column (clean replacement for hidden checkpoint).
    // The lorebook timed-effect fragment rides the same blob additively at the
    // end (any mode); old app versions ignore the unknown key.
    String groupRealismJson = '{}';
    if (_activeGroup != null) {
      // Include per-char objectives so each group member carries independent tasks.
      final perCharObjectives = <String, List<Map<String, dynamic>>>{};
      _groupObjectives.forEach((charId, list) {
        perCharObjectives[charId] = list
            .map(
              (o) => {
                'id': o.id,
                'objective': o.objective,
                'isPrimary': o.isPrimary,
                'active': o.active,
                // tasks and other fields are stored in the objectives table; we keep lightweight here
              },
            )
            .toList();
      });

      groupRealismJson = jsonEncode({
        'globalDecayRates': _groupDecayRates,
        'perChar': _groupRealism,
        'authorNotes': _groupAuthorNotes,
        'authorNoteStrengths': _groupAuthorNoteStrengths,
        'characterSystemPrompts': _groupCharacterSystemPrompts,
        'ragEnabled': _groupRagEnabled,
        'retrievalCount': _groupRetrievalCount,
        'memoryBudgetPercent': _groupMemoryBudgetPercent,
        'characterRAGPriorities': _groupCharacterRAGPriorities,
        'objectives': perCharObjectives,
        'savedAt': DateTime.now().toIso8601String(),
      });
    } else if (_activeGroup == null && _sceneGuestIds.isNotEmpty) {
      // 1:1 with Scene Guests (Lite NPCs): reuse the (otherwise '{}') group
      // realism column to persist the guest dbIds. No schema change needed.
      // (Guest growth lives in the growth_rings table — nothing co-located.)
      groupRealismJson = jsonEncode({'sceneGuests': _sceneGuestIds});
    }

    // Merge the lorebook timed-effect + macro-variable fragments into
    // whatever state map the branches above produced. When all are empty
    // this stays the literal '{}' older app versions expect.
    final loreTimers = _loreTimedEffects.toJsonFragment();
    final macroVars = _loreTimedEffects.macroVarsFragment();
    final chatBook = _loreTimedEffects.chatLorebookFragment();
    if (loreTimers != null || macroVars != null || chatBook != null) {
      final stateMap = jsonDecode(groupRealismJson) as Map<String, dynamic>;
      if (loreTimers != null) stateMap['lorebookTimers'] = loreTimers;
      if (macroVars != null) stateMap['macroVars'] = macroVars;
      if (chatBook != null) stateMap['chatLorebook'] = chatBook;
      groupRealismJson = jsonEncode(stateMap);
    }

    // Snapshot messages at the start so async gaps can't see a mutated list.
    final snapshot = List<ChatMessage>.from(_messages);

    // Look up character DB id if in 1:1 mode
    String? characterDbId;
    String? groupDbId;
    if (_activeGroup != null) {
      groupDbId = _activeGroup!.id;
    } else if (_activeCharacter?.dbId != null) {
      characterDbId = _activeCharacter!.dbId;
    }

    // Upsert session (INSERT OR REPLACE to avoid UNIQUE constraint errors)
    final timestamp = int.tryParse(sessionId) ?? 0;
    final createdAt = timestamp > 0
        ? DateTime.fromMillisecondsSinceEpoch(timestamp)
        : DateTime.now();
    await _db.upsertSession(
      SessionsCompanion.insert(
        id: sessionId,
        characterId: drift.Value(characterDbId),
        groupId: drift.Value(groupDbId),
        name: drift.Value(_sessionName),
        description: drift.Value(_sessionDescription),
        userPersonaId: drift.Value(_userPersonaService.persona.id),
        authorNote: drift.Value(_authorNote),
        authorNoteDepth: drift.Value(_authorNoteStrength),
        summary: drift.Value(_summary.isEmpty ? null : _summary),
        summaryLastIndex: drift.Value(
          _summaryLastIndex > 0 ? _summaryLastIndex : null,
        ),
        parentSession: drift.Value(_parentSessionId),
        forkIndex: drift.Value(_forkIndex),
        affectionScore: drift.Value(_relationshipService.affectionScore),
        relationshipTier: drift.Value(_relationshipService.relationshipTier),
        longTermScore: drift.Value(_relationshipService.longTermScore),
        longTermTier: drift.Value(_relationshipService.longTermTier),
        turnsSinceLongTermCheck: drift.Value(
          _relationshipService.turnsSinceLongTermCheck,
        ),
        shortTermDeltasSummary: drift.Value(
          _relationshipService.shortTermDeltasSummary,
        ),
        realismEnabled: drift.Value(_realismEnabled),
        moodDecayCounter: drift.Value(_moodDecayCounter),
        characterEmotion: drift.Value(_characterEmotion),
        emotionIntensity: drift.Value(_emotionIntensity),
        timeOfDay: drift.Value(_timeService.timeOfDay),
        dayCount: drift.Value(_timeService.dayCount),
        startDayOfWeek: drift.Value(_timeService.startDayOfWeekAnchor),
        passageOfTimeEnabled: drift.Value(_timeService.passageOfTimeEnabled),
        nsfwCooldownEnabled: drift.Value(_nsfwService.nsfwCooldownEnabled),
        needsSimEnabled: drift.Value(_needsSimEnabled),
        needsVector: drift.Value(
          _needsSimEnabled ? jsonEncode(_needsSimulation.vector) : null,
        ),
        groupRealismState: drift.Value(groupRealismJson),
        arousalLevel: drift.Value(_nsfwService.arousalLevel),
        cooldownTurnsRemaining: drift.Value(
          _nsfwService.cooldownTurnsRemaining,
        ),
        cooldownTurnsTotal: drift.Value(_nsfwService.cooldownTurnsTotal),
        trustLevel: drift.Value(_relationshipService.trustLevel),
        activeFixation: drift.Value(_relationshipService.activeFixation),
        fixationLifespan: drift.Value(_relationshipService.fixationLifespan),
        spatialStance: drift.Value(_relationshipService.spatialStance),
        chaosModeEnabled: drift.Value(_chaosModeService.chaosModeEnabled),
        chaosPressure: drift.Value(_chaosModeService.chaosPressure),
        trustRepairPending: drift.Value(
          _relationshipService.pendingTrustRepair,
        ),
        createdAt: drift.Value(createdAt),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );

    // Per-session generation overrides (v22) — saved via raw SQL so this
    // works even before build_runner regenerates database.g.dart.
    await _db.customUpdate(
      'UPDATE sessions SET generation_settings = ? WHERE id = ?',
      variables: [
        drift.Variable(genSettingsJson),
        drift.Variable(sessionId),
      ],
      updates: {_db.sessions},
    );

    // Replace all messages for this session using the snapshot.
    // Use a transaction for the delete+insert to keep the replace atomic even
    // if other writers (cloud sync, external tools) touch the DB concurrently.
    await _db.transaction(() async {
      await _db.deleteMessagesForSession(sessionId);
      final messageBatch = <MessagesCompanion>[];
      for (int i = 0; i < snapshot.length; i++) {
        final m = snapshot[i];
        messageBatch.add(
          MessagesCompanion(
            sessionId: drift.Value(sessionId),
            position: drift.Value(i),
            sender: drift.Value(m.sender),
            isUser: drift.Value(m.isUser),
            characterId: drift.Value(m.characterId),
            swipes: drift.Value(jsonEncode(m.swipes)),
            swipeIndex: drift.Value(m.swipeIndex),
            swipeDurations: drift.Value(jsonEncode(m.swipeDurations)),
            metadata: drift.Value(
              m.metadata != null ? jsonEncode(m.metadata) : null,
            ),
            swipeMetadata: drift.Value(
              m.swipeMetadata.any((e) => e != null)
                  ? jsonEncode(m.swipeMetadata)
                  : null,
            ),
          ),
        );
      }
      if (messageBatch.isNotEmpty) {
        await _db.insertMessages(messageBatch);
      }
    });
  }


  /// Evaluates emotion + relationship baseline from the greeting message only.
}
