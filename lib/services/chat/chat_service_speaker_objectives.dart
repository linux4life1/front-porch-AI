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

/// Group baseline seeds, realism-state injection and restore, post-gen
/// needs checks and mood decay. The speaker objectives this part was named
/// for live in the objectives door; the file keeps its name because
/// needs_gate_ratchet_test and needs_beat_span_test read it by path.
extension ChatServiceSpeakerObjectives on ChatService {
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

  /// The pre-reply goal check. Send runs it; Continue and Regen do not
  /// (objective_check_gate_test reads this name in the send part).
  Future<void> _maybeCheckTaskCompletionSync() =>
      objectivesDoor.completion.maybeCheckSync();

  String _getRealismStateInjection() {
    // Thin delegation to the words-only state composer — the single source of
    // the "[How <Name> is right now: …]" block the model receives (salience-
    // gated natural language, no simulation scalars; see
    // docs/design/prompt-state-injection.md §3).
    return _realismStateInjection.buildRealismStateInjection();
  }

  /// A group delete loads the deleted member into the live scalar
  /// registers. While another member is mid-turn, put those registers
  /// back or the next save writes the deleted member onto the speaker.
  void _keepingLiveSpeaker(void Function() body) {
    final live = _session.activeCharacter;
    if (_activeGroup == null || !_isTurnBusy || live == null) {
      body();
      return;
    }
    final sid = _getCharacterIdFromCard(live);
    if (sid.isEmpty) {
      body();
      return;
    }
    _realismDance.saveScalarsIntoGroup(sid);
    try {
      body();
    } finally {
      _realismDance.loadIntoScalars(sid);
    }
  }

  /// Group-aware wrapper for [_restoreRealismStateFromMessage]. In a group the
  /// snapshot belongs to the message's SPEAKER, so the restore must go through
  /// their _groupRealism entry (load → restore scalars → save) — a bare scalar
  /// restore is overwritten by the next per-speaker load while the map keeps
  /// the un-reverted values (the swipe/delete "time travel does nothing in
  /// groups" bug). 1:1 restores the scalars directly, unchanged. No-ops when
  /// the group speaker can't be resolved (renamed/removed member): restoring
  /// into the wrong member's entry would corrupt that member's state.
  void _restoreRealismStateForSpeaker(
    ChatMessage msg, {
    bool restoreClock = false,
  }) {
    if (_activeGroup == null) {
      _restoreRealismStateFromMessage(msg, restoreClock: restoreClock);
      return;
    }
    final speaker = _resolveGroupSpeakerForMessage(msg);
    if (speaker == null) return;
    final sid = _getCharacterIdFromCard(speaker);
    if (sid.isEmpty) return;
    final hadStoredNeeds = _groupStore.needsOf(sid).isNotEmpty;
    final state = msg.activeMetadata?['realism_state'];
    final stampHasNeeds = state is Map && state['needs'] is Map;
    _realismDance.loadIntoScalars(sid);
    _restoreRealismStateFromMessage(
      msg,
      groupSpeakerId: sid,
      restoreClock: restoreClock,
    );
    if (!hadStoredNeeds && !stampHasNeeds) {
      // The load's initializeFresh() filled the scalar vector for a member
      // with no needs history, and the stamp carries none either — clear it
      // so the save below can't materialize invented needs into their entry.
      _needsSimulation.restoreFromSnapshot(const {'vector': <String, int>{}});
    }
    _realismDance.saveScalarsIntoGroup(sid);
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
    bool restoreClock = false,
  }) {
    if (msg == null) return;

    // Check if the current visible node has an active swipe metadata array or just the base metadata
    final meta = msg.activeMetadata;
    final rawState = meta?['realism_state'];
    final state = rawState is Map ? Map<String, dynamic>.from(rawState) : null;

    // Default false. Regen/swipe/delete never pass true — the tip
    // after is the clock. Fork/import pass true only as applyTipClock.
    if (restoreClock) {
      _clockReader.applyTipClock();
    }

    if (state == null) {
      debugPrint(
        '[Realism] No time-travel snapshot found in message. Legacy state kept.',
      );
      return;
    }

    _relationshipService.restoreFromMessageState(
      state,
      groupSpeakerId: groupSpeakerId,
    );
    _mood.restoreFromStamp(state);

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

    // Pockets & Wardrobe. Restored even when the global is off (HIDES≠erase
    // for the Porch Life switch — toggle-back finds the kit). A per-char-off
    // owner is skipped: inventing or wiping a hidden record is the other
    // HIDES≠erase. A snapshot only exists if the feature was on when the
    // turn ran.
    //
    // Owner key MUST be the message speaker (groupSpeakerId when rewinding a
    // group member), never bare `_session.activeCharacter` — after post-gen the
    // active pointer is often someone else, so restore used to write
    // speaker A's kit onto B (audit P1.7).
    // `_pocketsRewinds.restoreFromStamp` already keys by stamp `char`; this realism_state path is the dual for no-op /
    // stamp-less turns that only carry pockets inside realism_state.
    final pocketsSnap = state['pockets'];
    if (pocketsSnap is Map) {
      final ownerId = (groupSpeakerId != null && groupSpeakerId.isNotEmpty)
          ? groupSpeakerId
          : (_session.activeCharacter != null
                ? _getCharacterIdFromCard(_session.activeCharacter!)
                : '');
      if (ownerId.isNotEmpty && _pocketsLedger.pocketsWriteAllowed(ownerId)) {
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
  /// snapshot for chips, post RealismDance.saveScalarsIntoGroup + attach needs_deltas,
  /// (orchestration + impersonation dance in god; full in evaluator).
  Future<void> _runPostGenNeedsChecks(String responseText) async {
    // During AFK, store current needs vector so the evaluator can include it
    // in its prompt for better-contextualized delta estimates.
    final wasAfk = _pendingIdleCue != null;
    if (wasAfk) {
      _pendingRealismMetadata ??= {};
      _pendingRealismMetadata!['_afk_needs_vector'] = Map<String, int>.from(
        needsSimulation.vector,
      );
    }
    _needsImpactEvaluator.beatNote = needsBeatNote(
      _timeService.needsSpanLabel,
      longSkip: _timeService.bodyBeatLongSkip,
      rested: _timeService.bodyBeatSlept,
    );
    await _needsImpactEvaluator.evaluateAndApply(responseText, isAfk: wasAfk);
    // During time away, clear the scene-level reason so each need's own
    // reason shows on the chip.
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
