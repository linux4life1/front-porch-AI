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

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';

/// The realism restore from a message's snapshot (1:1 scalars, or a group
/// speaker's slot by message speaker id), the post-gen Needs checks, mood
/// decay and a group member's creation baseline.
///
/// test/hygiene/needs_gate_ratchet_test.dart allows this file to read the
/// chat's stored Needs switch: a restore rewinds Needs state, it does not
/// run Needs. test/services/chat/needs_beat_span_test.dart reads the
/// post-gen check here.
class RealismRestores {
  RealismRestores(this._g);

  final RealismGraph _g;

  ChatSessionState get _session => _g.session;
  GroupChat? get _activeGroup => _session.activeGroup;
  GroupRealismStore get _groupStore => _g.groups;
  NeedsSimulation get _needsSimulation => _g.needs;
  TimeService get _timeService => _g.time;
  RealismDance get _realismDance => _g.dance;
  String _getCharacterIdFromCard(CharacterCard card) =>
      _g.session.characterIdFor(card);

  /// The chat's STORED Needs switch: this file rewinds state with it.
  bool get _needsSimEnabled => _g.controls.needsSimEnabled;

  /// The stored switch a rewind reads: a group member's rewind reads that
  /// member's own, the 1:1 chat's is the chat's.
  bool _storedNeedsOn(String? sid) {
    if (_activeGroup == null || sid == null) return _needsSimEnabled;
    return _groupStore.needsOnFor(sid);
  }

  // ── Group Creation Baseline Seeding (bond/trust/emotion/time/day only) ──

  /// The immutable creation-time baseline realism values for a group member.
  /// Only the allowed seeding fields are exposed: affection (bond), trust,
  /// emotion, timeOfDay, dayCount.
  Map<String, dynamic> baselineSeedFor(CharacterCard character) {
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

  /// A group delete loads the deleted member into the live scalar
  /// registers. While another member is mid-turn, put those registers
  /// back or the next save writes the deleted member onto the speaker.
  void keepingLiveSpeaker(void Function() body) {
    final live = _session.activeCharacter;
    if (_activeGroup == null ||
        !_g.deps.doors.turn().isTurnBusy ||
        live == null) {
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

  /// Group-aware wrapper for [fromMessage]. In a group the snapshot belongs
  /// to the message's SPEAKER, so the restore must go through their group
  /// slot (load → restore scalars → save) — a bare scalar restore is
  /// overwritten by the next per-speaker load while the map keeps the
  /// un-reverted values (the swipe/delete "time travel does nothing in
  /// groups" bug). 1:1 restores the scalars directly, unchanged. No-ops when
  /// the group speaker can't be resolved (renamed/removed member): restoring
  /// into the wrong member's entry would corrupt that member's state.
  void forSpeaker(ChatMessage msg, {bool restoreClock = false}) {
    if (_activeGroup == null) {
      fromMessage(msg, restoreClock: restoreClock);
      return;
    }
    final speaker = _g.speakerFor(msg);
    if (speaker == null) return;
    final sid = _getCharacterIdFromCard(speaker);
    if (sid.isEmpty) return;
    // Every gate below is named by the message's speaker id (their Needs
    // switch, their kit, their Afterglow through the loaded member), never
    // read off whoever is up next, so no speaker pin is needed here.
    final hadStoredNeeds = _groupStore.needsOf(sid).isNotEmpty;
    final state = msg.activeMetadata?['realism_state'];
    final stampHasNeeds = state is Map && state['needs'] is Map;
    _realismDance.loadIntoScalars(sid);
    fromMessage(msg, groupSpeakerId: sid, restoreClock: restoreClock);
    if (!hadStoredNeeds && !stampHasNeeds) {
      // The load's initializeFresh() filled the scalar vector for a member
      // with no needs history, and the stamp carries none either — clear
      // it so the save below can't materialize invented needs into their
      // entry.
      _needsSimulation.restoreFromSnapshot(const {'vector': <String, int>{}});
    }
    _realismDance.saveScalarsIntoGroup(sid);
  }

  /// [groupSpeakerId] names the member being rewound so the two registers
  /// that ride the group map — the hidden inter-character feelings and the
  /// decay cadence — are rewound with everything else. Only [forSpeaker]
  /// knows it, and it passes it; the 1:1 callers leave it null and the
  /// cadence rides the scalar instead.
  ///
  /// Before this, ONLY the regen REVERT rewound those two. Every other
  /// time-travel door — the regen merge, swipe navigation, delete rollback —
  /// restored bond/trust/emotion faithfully and silently left the feelings
  /// and cadence where the discarded turn had pushed them (independent review
  /// of 848309c4 found the gap; the original fix closed one doorway of four).
  void fromMessage(
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
      _g.clockReader.applyTipClock();
    }

    if (state == null) {
      debugPrint(
        '[Realism] No time-travel snapshot found in message. Legacy state kept.',
      );
      return;
    }

    _g.relationship.restoreFromMessageState(
      state,
      groupSpeakerId: groupSpeakerId,
    );
    _g.mood.restoreFromStamp(state);

    _g.nsfw.restoreNsfwFromRealismState(state);

    // Needs simulation snapshot (clean port)
    // Only restore the vector if the sim is currently enabled for this session.
    // Never let a historical snapshot flip the stored switch back on (supports
    // clean mid-chat toggle-off via setNeedsSimEnabled without stale state).
    if (state.containsKey('needs') &&
        state['needs'] is Map &&
        _storedNeedsOn(groupSpeakerId)) {
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
    // group member), never bare `session.activeCharacter` — after post-gen the
    // active pointer is often someone else, so restore used to write
    // speaker A's kit onto B (audit P1.7).
    // PocketsRewinds.restoreFromStamp already keys by stamp `char`; this
    // realism_state path is the dual for no-op / stamp-less turns that only
    // carry pockets inside realism_state.
    final pocketsSnap = state['pockets'];
    if (pocketsSnap is Map) {
      final ownerId = (groupSpeakerId != null && groupSpeakerId.isNotEmpty)
          ? groupSpeakerId
          : (_session.activeCharacter != null
                ? _getCharacterIdFromCard(_session.activeCharacter!)
                : '');
      if (ownerId.isNotEmpty && _g.pocketsLedger.pocketsWriteAllowed(ownerId)) {
        _g.setPocketsFor(ownerId, Pockets.fromJson(pocketsSnap));
      }
    }

    debugPrint(
      '[Realism] Engine state successfully rolled back to match timeline.',
    );
  }

  /// Runs all post-generation needs-related checks (climax, sexual activity,
  /// daily activities, fulfillment) via thin delegate to the consolidated
  /// NeedsImpactEvaluator (simple model + optional Director authority review
  /// loop). The caller holds the group impersonation dance around it, so the
  /// prompts see the speaker's name, personality and stance.
  Future<void> runPostGenNeedsChecks(String responseText) async {
    // During AFK, store current needs vector so the evaluator can include it
    // in its prompt for better-contextualized delta estimates.
    final wasAfk = _g.deps.doors.cast().idle.pendingIdleCue != null;
    final registers = _g.registers;
    if (wasAfk) {
      registers.pending ??= {};
      registers.pending!['_afk_needs_vector'] = Map<String, int>.from(
        _needsSimulation.vector,
      );
    }
    _g.needsImpact.beatNote = needsBeatNote(
      _timeService.needsSpanLabel,
      longSkip: _timeService.bodyBeatLongSkip,
      rested: _timeService.bodyBeatSlept,
    );
    await _g.needsImpact.evaluateAndApply(responseText, isAfk: wasAfk);
    // During time away, clear the scene-level reason so each need's own
    // reason shows on the chip.
    if (wasAfk) {
      _needsSimulation.clearLastSceneReason();
    }
  }

  /// Apply short-term relationship decay (2 points per 10 turns toward 0)
  /// This prevents relationships from being permanently stuck at extremes.
  /// The counter, 1:1/group branches and inter-char decay live in
  /// RelationshipService.applyShortTermDecay.
  void applyMoodDecay() {
    _g.relationship.applyShortTermDecay();
  }
}
