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

/// Session persist: enqueue, write, and replace-all.
/// Guest / group-realism hydrate stays on [ChatServiceSessionState].
extension ChatServiceSessionStateSave on ChatService {
  Future<void> _saveChat({bool replaceAll = false}) async {
    // Turn taken = this write. Snapshot at enqueue so a later reload
    // cannot shrink the queued transcript. [replaceAll] is only for
    // delete/regen-pop — the default upsert cannot erase a landed turn.
    if ((_activeCharacter == null && _activeGroup == null) ||
        _currentSessionId == null) {
      return;
    }
    if (replaceAll) await _awaitHistoryHydrated();
    if (_messages.isEmpty) {
      debugPrint(
        '[ChatService] ⚠ _saveChat called with empty messages for '
        'session $_currentSessionId — skipping to protect existing data.',
      );
      return;
    }
    final sessionId = _currentSessionId!;
    final snapshot = List<ChatMessage>.from(_messages);
    final positionBase = _history.basePosition;
    _saveChain = _saveChain.then((_) async {
      for (var i = 0; i < 3; i++) {
        try {
          await _doSaveChat(
            sessionId,
            snapshot,
            replaceAll: replaceAll,
            positionBase: positionBase,
          );
          return;
        } catch (e) {
          debugPrint('[ChatService] ⚠ persist ${i + 1}/3 failed: $e');
          if (i == 2) return; // keep the chain healthy
          await Future<void>.delayed(Duration(milliseconds: 40 * (i + 1)));
        }
      }
    });
    await _saveChain;
  }

  /// Drain `_saveChain` and write live state (window-close + session swap).
  Future<void> flushPendingSaves() => _saveChat();

  Future<void> _doSaveChat(
    String sessionId,
    List<ChatMessage> snapshot, {
    bool replaceAll = false,
    int positionBase = 0,
  }) async {
    if (snapshot.isEmpty) return;

    // Switched chats since this write was queued: persist the captured
    // transcript onto ITS session, but do not stamp this chat's live
    // scalars onto that row (that is the inverse of the cross-chat wipe
    // this method's sessionId local was introduced to stop).
    if (_currentSessionId != sessionId) {
      await _replaceSessionMessages(
        sessionId,
        snapshot,
        positionBase: positionBase,
      );
      return;
    }

    // Per-session gen settings captured with the still-this-session check
    // so a switch after this line cannot bleed the new chat's overrides.
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
    } else if (_activeGroup == null && _sceneGuest.ids.isNotEmpty) {
      // 1:1 with Scene Guests (Lite NPCs): reuse the (otherwise '{}') group
      // realism column to persist the guest dbIds. No schema change needed.
      // (Guest growth lives in the growth_rings table — nothing co-located.)
      groupRealismJson = jsonEncode({'sceneGuests': _sceneGuest.ids});
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

    // Look up character DB id if in 1:1 mode
    String? characterDbId;
    String? groupDbId;
    if (_activeGroup != null) {
      groupDbId = _activeGroup!.id;
    } else if (_activeCharacter?.dbId != null) {
      characterDbId = _activeCharacter!.dbId;
    }

    // Hydrate must not overwrite the row's binding with the previous chat's
    // still-live persona. A partial omit is not possible on insertOnConflict
    // update (absent → default null), so keep the existing id when set.
    // Same for character/group: a save after `_activeCharacter =` but
    // before session detach used to rebind chat A onto the incoming card.
    var personaId = _userPersonaService.persona.id;
    final existing = await _db.getSessionById(sessionId);
    if (_preserveSessionPersonaOf[this] == true) {
      final kept = existing?.userPersonaId;
      if (kept != null && kept.isNotEmpty) {
        personaId = kept;
      }
    }
    final keptChar = existing?.characterId;
    if (keptChar != null && keptChar.isNotEmpty) {
      characterDbId = keptChar;
    }
    final keptGroup = existing?.groupId;
    if (keptGroup != null && keptGroup.isNotEmpty) {
      groupDbId = keptGroup;
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
        userPersonaId: drift.Value(personaId),
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
        characterEmotion: drift.Value(_characterEmotion),
        emotionIntensity: drift.Value(_emotionIntensity),
        timeOfDay: drift.Value(_timeService.timeOfDay),
        dayCount: drift.Value(_timeService.dayCount),
        startDayOfWeek: drift.Value(_timeService.startDayOfWeekAnchor),
        storyClock: drift.Value(_timeService.storyClockIso),
        storyStartDate: drift.Value(_timeService.storyStartDateIso),
        passageOfTimeEnabled: drift.Value(_timeService.passageOfTimeEnabled),
        nsfwCooldownEnabled: drift.Value(_nsfwService.nsfwCooldownEnabled),
        needsSimEnabled: drift.Value(_needsSimEnabled),
        objectivesEnabled: drift.Value(_objectivesEnabled),
        needsVector: drift.Value(
          _needsSimEnabled ? jsonEncode(_needsSimulation.vector) : null,
        ),
        // v47 — the 1:1 record. Group members keep theirs inside
        // groupRealismState above, which is why groups always survived a
        // reload and 1:1 chats did not: the scalar had nowhere to go. Written
        // unconditionally rather than behind the Pockets switch, because
        // toggling the feature off mid-chat must not erase what they were
        // already carrying — turning it back on should find the record intact.
        //
        // Empty ≠ absent (audit P1.8): an emptied inventory is still a
        // record (`{"worn":[],"carrying":[]}`). NULL means "never seeded",
        // and load + seedPocketsFromCards would re-apply the card kit.
        // Groups already store empty maps; 1:1 must match.
        pockets: drift.Value(
          _activeGroup == null && _pockets != null
              ? jsonEncode(_pockets!.toJson())
              : null,
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
        withUser: drift.Value(_relationshipService.withUser),
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
      variables: [drift.Variable(genSettingsJson), drift.Variable(sessionId)],
      updates: {_db.sessions},
    );

    // Per-chat theme overrides — saved via raw SQL (no build_runner needed).
    await _db.setThemeOverrides(
      sessionId,
      _sessionThemeOverrides.toJsonString(),
    );

    // Context Budget snapshot (last real send) — raw SQL, schema v44.
    await _persistContextBudgetForSession(sessionId);

    await _replaceSessionMessages(
      sessionId,
      snapshot,
      replaceAll: replaceAll,
      positionBase: positionBase,
    );
  }

  /// Persist [snapshot]. Default upsert cannot shrink a longer on-disk
  /// transcript. [replaceAll] is delete+insert for delete/regen-pop.
  Future<void> _replaceSessionMessages(
    String sessionId,
    List<ChatMessage> snapshot, {
    bool replaceAll = false,
    int positionBase = 0,
  }) async {
    final messageBatch = <MessagesCompanion>[];
    for (int i = 0; i < snapshot.length; i++) {
      final m = snapshot[i];
      messageBatch.add(
        MessagesCompanion(
          sessionId: drift.Value(sessionId),
          position: drift.Value(
            persistMessagePosition(base: positionBase, index: i),
          ),
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
    if (replaceAll) {
      await _db.transaction(() async {
        await _db.deleteMessagesForSession(sessionId);
        if (messageBatch.isNotEmpty) {
          await _db.insertMessages(messageBatch);
        }
      });
    } else if (messageBatch.isNotEmpty) {
      await _db.upsertMessagesPreservingTail(sessionId, messageBatch);
    }
  }
}
