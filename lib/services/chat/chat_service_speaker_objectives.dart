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

    baseline[charId] = {
      'affection': (values['affection'] as num?)?.toInt() ?? 50,
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
    notifyListeners();
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
          final newId =
              'obj_${DateTime.now().millisecondsSinceEpoch}_${charId.hashCode}';
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

      // Remove the marker so it doesn't seed again
      map.remove('imported_member_objectives');
      _activeGroup!.defaultMemberRealismState = jsonEncode(map);
      await _saveChat();
    } catch (_) {}
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
    final idx = _groupCharacters.indexWhere((c) => c.name == msg.sender);
    if (idx < 0) return;
    final sid = _getCharacterIdFromCard(_groupCharacters[idx]);
    if (sid.isEmpty) return;
    final hadStoredNeeds = _getGroupNeeds(sid).isNotEmpty;
    final state = msg.activeMetadata?['realism_state'];
    final stampHasNeeds = state is Map && state['needs'] is Map;
    _loadGroupRealismIntoScalars(sid);
    _restoreRealismStateFromMessage(msg);
    if (!hadStoredNeeds && !stampHasNeeds) {
      // The load's initializeFresh() filled the scalar vector for a member
      // with no needs history, and the stamp carries none either — clear it
      // so the save below can't materialize invented needs into their entry.
      _needsSimulation.restoreFromSnapshot(const {'vector': <String, int>{}});
    }
    _saveScalarsIntoGroupRealism(sid);
  }

  void _restoreRealismStateFromMessage(ChatMessage? msg) {
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
    _relationshipService.restoreFromMessageState(state);
    _moodDecayCounter = state['moodDecayCounter'] as int? ?? _moodDecayCounter;
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
