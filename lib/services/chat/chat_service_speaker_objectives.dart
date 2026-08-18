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

/// Per-speaker objective focus/seed + realism-state injection/restore +
/// post-gen needs checks + mood decay. Extracted verbatim (zero behaviour change).
extension ChatServiceSpeakerObjectives on ChatService {
  /// Public API: Focus the personal objectives of a specific group member so the
  /// existing objective management UI and generation can operate on them.
  /// Does nothing in 1:1 mode.
  Future<void> focusObjectivesForGroupCharacter(CharacterCard character) async {
    if (_activeGroup == null) return;
    final charId = _getCharacterIdFromCard(character);
    final objs = await _db.getObjectivesForCharacter(
      charId,
      chatId: _currentSessionId,
    );
    _activeObjectives = objs.where((o) => o.active).toList();
    _rebindTodayObjectiveFromDb();
    notifyListeners();
  }

  // ── Group Creation Baseline Seeding (bond/trust/emotion/time/day only) ──

  /// Returns the immutable creation-time baseline realism values for a group member.
  /// Only the allowed seeding fields are exposed: affection (bond), trust, emotion, timeOfDay, dayCount.
  Map<String, dynamic> getBaselineSeedForGroupCharacter(
    CharacterCard character,
  ) {
    if (_activeGroup == null) return {};
    final charId = _getCharacterIdFromCard(character);
    try {
      final json = jsonDecode(_activeGroup!.baselineRealismState);
      if (json is Map && json.containsKey(charId)) {
        final data = json[charId] as Map<String, dynamic>? ?? {};
        return {
          'affection': (data['affection'] as num?)?.toInt() ?? 50,
          'trust': (data['trust'] as num?)?.toInt() ?? 50,
          'emotion': (data['emotion'] as String?) ?? 'neutral',
          'emotionIntensity':
              (data['emotionIntensity'] as String?) ?? 'moderate',
          'timeOfDay': (data['timeOfDay'] as String?) ?? 'morning',
          'dayCount': (data['dayCount'] as num?)?.toInt() ?? 1,
        };
      }
    } catch (_) {}
    return {
      'affection': 50,
      'trust': 50,
      'emotion': 'neutral',
      'emotionIntensity': 'moderate',
      'timeOfDay': 'morning',
      'dayCount': 1,
    };
  }

  /// Updates the immutable creation baseline for a group member.
  /// Only allowed fields are accepted. This should only be called during group creation seeding.
  void setBaselineSeedForGroupCharacter(
    CharacterCard character,
    Map<String, dynamic> values,
  ) {
    if (_activeGroup == null) return;
    final charId = _getCharacterIdFromCard(character);

    Map<String, dynamic> baseline;
    try {
      baseline = Map<String, dynamic>.from(
        jsonDecode(_activeGroup!.baselineRealismState),
      );
    } catch (_) {
      baseline = {};
    }

    // NOTE: this REPLACES the per-character entry with exactly this shape, so a
    // key missing here is silently dropped no matter what the caller passes.
    // 'longTermScore' was missing, which is half of why the Group Settings
    // "Long-Term Bond" slider never persisted — the editor wrote it into
    // 'trust' instead, and even the correct key would have been discarded here.
    // Defaults to affection, matching how RelationshipService seeds a member
    // that predates the key.
    baseline[charId] = {
      'affection': (values['affection'] as num?)?.toInt() ?? 50,
      'longTermScore':
          (values['longTermScore'] as num?)?.toInt() ??
          (values['affection'] as num?)?.toInt() ??
          50,
      'trust': (values['trust'] as num?)?.toInt() ?? 50,
      'emotion': (values['emotion'] as String?) ?? 'neutral',
      'emotionIntensity': (values['emotionIntensity'] as String?) ?? 'moderate',
      'timeOfDay': (values['timeOfDay'] as String?) ?? 'morning',
      'dayCount': (values['dayCount'] as num?)?.toInt() ?? 1,
    };

    _activeGroup!.baselineRealismState = jsonEncode(baseline);
    notifyListeners();
  }

  /// Loads the personal objectives for the current/next speaker into _activeObjectives
  /// when in group mode. This makes the existing objective UI, generation, and injection
  /// work per-character in groups without duplicating the entire objective system.
  Future<void> _loadObjectivesForCurrentSpeaker() async {
    if (_activeGroup == null || _currentSessionId == null) return;

    final speaker = nextCharacter ?? _groupCharacters.firstOrNull;
    if (speaker == null) {
      _activeObjectives = [];
      _messagesSinceLastCheck = 0;
      _isCheckingCompletion = false;
      _summaryPaused =
          false; // explicit secondary zero for _summaryPaused (symmetric; _loadObjectivesForCurrentSpeaker no-speaker hygiene)
      _isSummaryGenerating =
          false; // secondary zero in _loadObjectivesForCurrentSpeaker no-speaker (group hygiene for summary flag)
      _isGrowthPassRunning =
          false; // growth-pass flag zero in _loadObjectivesForCurrentSpeaker no-speaker (group hygiene; keep reset blocks in sync)
      notifyListeners();
      return;
    }

    final charId = _getCharacterIdFromCard(speaker);
    final objs = await _db.getObjectivesForCharacter(
      charId,
      chatId: _currentSessionId,
    );

    _activeObjectives = objs.where((o) => o.active).toList();
    _rebindTodayObjectiveFromDb();
    notifyListeners();
  }

  /// Import a card's authored "Current Task / Quest" as that character's
  /// primary objective.
  ///
  /// The authoring box was retired from every editor (approved sketch §4:
  /// Ambitions replaced it, and a per-chat quest belongs in the sidebar's
  /// Objectives panel, not baked into the card). The FIELD is still read, so a
  /// quest an author typed before the swap still arrives — quietly, in the one
  /// place quests now live. No prompt, no banner: it is exactly what they asked
  /// for when they typed it.
  ///
  /// Shared by all three fresh-chat entry points. Two of them (1:1 first entry
  /// and startNewChat) had carried their own copy of this since V2.5; group
  /// entry never seeded at all, so a member card's task was dropped on the
  /// floor — invisible while the editor existed, permanent data loss once it
  /// was gone.
  ///
  /// Deferred to a microtask for the reason the 1:1 copies always were: the
  /// session row must exist before the objective write. [target] pins a group
  /// member's task to THEM rather than to whoever happens to speak first; 1:1
  /// leaves it null and [setObjective] resolves the active character. Not gated
  /// on [objectivesActive] — this is a data-preservation write, and an
  /// objective costs nothing while the feature is off.
  void _importAuthoredTask(FrontPorchExtensions? ext, {CharacterCard? target}) {
    final task = ext?.currentTask.trim() ?? '';
    if (task.isEmpty) return;
    Future.microtask(() async {
      await setObjective(task, isPrimary: true, targetCharacter: target);
      debugPrint(
        '[ChatService] Imported authored task'
        '${target != null ? ' for ${target.name}' : ''}: $task',
      );
    });
  }

  /// One-time seeding of objectives that were carried in an imported Group Card.
  /// Called after group state is loaded for a freshly imported group.
  Future<void> _seedImportedMemberObjectivesIfPresent() async {
    if (_activeGroup == null || _currentSessionId == null) return;

    try {
      final stateJson = _activeGroup!.defaultMemberRealismState;
      if (stateJson.isEmpty || stateJson == '{}') return;

      final map = jsonDecode(stateJson);
      if (map is! Map) return;

      final importedObj = map['imported_member_objectives'];
      if (importedObj is! Map) return;

      for (final entry in importedObj.entries) {
        final charId = entry.key.toString();
        final list = entry.value as List? ?? [];
        for (final objData in list) {
          final objMap = objData as Map<String, dynamic>? ?? {};
          // Uuid, like every other objective write (chat_service_objectives).
          // The old id was `obj_<millis>_<charId.hashCode>`, built INSIDE this
          // loop from the OUTER key — so two objectives for the same member
          // written in the same millisecond (routinely: the inserts are
          // adjacent) collided on the primary key. The insert threw, the bare
          // catch below ate it, and every remaining member's quests were
          // dropped with no log.
          final newId = const Uuid().v4();
          await _db.insertObjective(
            ObjectivesCompanion.insert(
              id: newId,
              characterId: charId,
              chatId: drift.Value(_currentSessionId!),
              objective:
                  objMap['objective']?.toString() ?? 'Imported objective',
              tasks: drift.Value(objMap['tasks']?.toString() ?? '[]'),
              active: const drift.Value(true),
              isPrimary: drift.Value(objMap['isPrimary'] == true),
              checkFrequency: drift.Value(
                (objMap['checkFrequency'] as num?)?.toInt() ?? 3,
              ),
              injectionDepth: drift.Value(
                (objMap['injectionDepth'] as num?)?.toInt() ?? 4,
              ),
            ),
          );
        }
      }

      // Remove the marker so it doesn't seed again. The marker lives on the
      // GROUP row, and _saveChat only upserts the session — so the in-memory
      // clear used to evaporate on the next launch and every re-entry seeded
      // the same quests all over again. Save the group too.
      map.remove('imported_member_objectives');
      _activeGroup!.defaultMemberRealismState = jsonEncode(map);
      await _groupChatRepository?.save(_activeGroup!);
      await _saveChat();
    } catch (e) {
      debugPrint('[ChatService] Imported member objectives seed failed: $e');
    }
  }

  String _getRealismStateInjection() {
    // Thin delegation to the words-only state composer — the single source of
    // the "[How <Name> is right now: …]" block the model receives (salience-
    // gated natural language, no simulation scalars; see
    // docs/design/prompt-state-injection.md §3).
    return _realismStateInjection.buildRealismStateInjection();
  }

  /// Group-aware wrapper for [_restoreRealismStateFromMessage]. In a group the
  /// snapshot belongs to the message's SPEAKER, so the restore must go through
  /// their _groupRealism entry (load → restore scalars → save) — a bare scalar
  /// restore is overwritten by the next per-speaker load while the map keeps
  /// the un-reverted values (the swipe/delete "time travel does nothing in
  /// groups" bug). 1:1 restores the scalars directly, unchanged. No-ops when
  /// the group speaker can't be resolved (renamed/removed member): restoring
  /// into the wrong member's entry would corrupt that member's state.
  void _restoreRealismStateForSpeaker(ChatMessage msg) {
    if (_activeGroup == null) {
      _restoreRealismStateFromMessage(msg);
      return;
    }
    final speaker = _resolveGroupSpeakerForMessage(msg);
    if (speaker == null) return;
    final sid = _getCharacterIdFromCard(speaker);
    if (sid.isEmpty) return;
    final hadStoredNeeds = _getGroupNeeds(sid).isNotEmpty;
    final state = msg.activeMetadata?['realism_state'];
    final stampHasNeeds = state is Map && state['needs'] is Map;
    _loadGroupRealismIntoScalars(sid);
    _restoreRealismStateFromMessage(msg, groupSpeakerId: sid);
    if (!hadStoredNeeds && !stampHasNeeds) {
      // The load's initializeFresh() filled the scalar vector for a member
      // with no needs history, and the stamp carries none either — clear it
      // so the save below can't materialize invented needs into their entry.
      _needsSimulation.restoreFromSnapshot(const {'vector': <String, int>{}});
    }
    _saveScalarsIntoGroupRealism(sid);
  }

  /// [groupSpeakerId] names the member being rewound so the two registers
  /// that ride the group map — the hidden inter-character feelings and the
  /// decay cadence — are rewound with everything else. Only
  /// [_restoreRealismStateForSpeaker] knows it, and it passes it; the 1:1
  /// callers leave it null and the cadence rides the scalar instead.
  ///
  /// Before this, ONLY the regen REVERT rewound those two. Every other
  /// time-travel door — the regen merge, swipe navigation, delete rollback —
  /// restored bond/trust/emotion faithfully and silently left the feelings
  /// and cadence where the discarded turn had pushed them (independent review
  /// of 848309c4 found the gap; the original fix closed one doorway of four).
  void _restoreRealismStateFromMessage(
    ChatMessage? msg, {
    String? groupSpeakerId,
  }) {
    if (msg == null) return;

    // Check if the current visible node has an active swipe metadata array or just the base metadata
    final meta = msg.activeMetadata;
    if (meta == null || !meta.containsKey('realism_state')) {
      debugPrint(
        '[Realism] No time-travel snapshot found in message. Legacy state kept.',
      );
      return;
    }

    final state = meta['realism_state'] as Map<String, dynamic>;
    _relationshipService.restoreFromMessageState(
      state,
      groupSpeakerId: groupSpeakerId,
    );
    _characterEmotion =
        state['characterEmotion'] as String? ?? _characterEmotion;
    _emotionIntensity =
        state['emotionIntensity'] as String? ?? _emotionIntensity;

    _timeService.restoreTimeFromRealismState(state);

    _nsfwService.restoreNsfwFromRealismState(state);

    // v3.0 Restorations (relationship via service; already covered by restoreFromMessageState above for most).
    // (Direct sets removed; service owns the scalars.)

    // Needs simulation snapshot (clean port)
    // Only restore the vector if the sim is currently enabled for this session.
    // Never let a historical snapshot flip _needsSimEnabled back on (supports
    // clean mid-chat toggle-off via setNeedsSimEnabled without stale state).
    if (state.containsKey('needs') &&
        state['needs'] is Map &&
        _needsSimEnabled) {
      final needsData = state['needs'] as Map;
      _needsSimulation.restoreFromSnapshot(needsData);
    }

    // Pockets & Wardrobe. Restored unconditionally rather than behind the
    // switch: a snapshot only exists if the feature was on when the turn ran,
    // and rolling the timeline back must put the record where it was even if
    // the user has since toggled Pockets off and on again.
    //
    // Owner key MUST be the message speaker (groupSpeakerId when rewinding a
    // group member), never bare `_activeCharacter` — after post-gen the
    // active pointer is often someone else, so restore used to write
    // speaker A's kit onto B (audit P1.7). `_restorePocketsFromStamp` already
    // keys by stamp `char`; this realism_state path is the dual for no-op /
    // stamp-less turns that only carry pockets inside realism_state.
    final pocketsSnap = state['pockets'];
    if (pocketsSnap is Map) {
      final ownerId = (groupSpeakerId != null && groupSpeakerId.isNotEmpty)
          ? groupSpeakerId
          : (_activeCharacter != null
              ? _getCharacterIdFromCard(_activeCharacter!)
              : '');
      if (ownerId.isNotEmpty) {
        setPocketsFor(ownerId, Pockets.fromJson(pocketsSnap));
      }
    }

    debugPrint(
      '[Realism] Engine state successfully rolled back to match timeline.',
    );
  }

  /// Runs all post-generation needs-related checks (climax, sexual activity,
  /// daily activities, fulfillment) via thin delegate to the consolidated
  /// NeedsImpactEvaluator (simple model + optional Director authority review loop).
  /// Orchestration (guards, group impersonation dance + loadGroupRealismIntoScalars
  /// before call so prompts see correct $charName/personality/stance, preTurn
  /// snapshot for chips, post _saveScalarsIntoGroupRealism + attach needs_deltas,
  /// (orchestration + impersonation dance in god; full in evaluator).
  Future<void> _runPostGenNeedsChecks(String responseText) async {
    // During AFK, store current needs vector so the evaluator can include it
    // in its prompt for better-contextualized delta estimates.
    final wasAfk = _pendingIdleCue != null;
    if (wasAfk) {
      _pendingRealismMetadata ??= {};
      _pendingRealismMetadata!['_afk_needs_vector'] =
          Map<String, int>.from(needsSimulation.vector);
      _pendingRealismMetadata!['_afk_decay_turns'] = 0;
    }
    await _needsImpactEvaluator.evaluateAndApply(responseText, isAfk: wasAfk);
    // During AFK, clear the scene-level reason so per-need reasons
    // ("Scene action", "Natural decay") appear in the delta chip
    // instead of the evaluator's single scene-level reason.
    if (wasAfk) {
      needsSimulation.clearLastSceneReason();
    }
  }

  // (unified thin + evaluator; prior _check* excised as dead. See CLAUDE.md).

  // ── Score / State Helpers (thinned; core logic + counters in RelationshipService) ──

  /// Apply short-term relationship decay (2 points per 10 turns toward 0)
  /// This prevents relationships from being permanently stuck at extremes.
  void _applyMoodDecay() {
    // Decay mechanism moved to RelationshipService (applyShortTermDecay).
    // Counter, 1:1/group branches, inter-char decay all delegated for mechanical fidelity.
    _relationshipService.applyShortTermDecay();
  }
}
