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

part of 'relationship_service.dart';

/// Regen overlay from a rejected message's pre-gen `realism_state` — **feelings
/// only** (audit P1.10 + hostile self-review 2026-08-11).
///
/// Inter-character feelings mutate **post-gen** and are never restamped, so the
/// rejected turn's stamp still holds the honest pre-sweep map. Cadence is
/// **not** included: it is stamped **after** that turn's decay tick, and regen
/// re-applies [RelationshipService.applyShortTermDecay] after restore. Overlaying
/// post-decay cadence then re-decaying skips or double-counts the every-10 bond
/// fire. Cadence correctly comes from `previousMessageState` + one re-decay.
///
/// Pure so ChatService and unit tests share the key list.
Map<String, dynamic> rejectedTurnRewindPatch(Map? realismState) {
  if (realismState == null) return const {};
  final rels = realismState['interCharacterRelationships'];
  if (rels is! Map) return const {};
  return {'interCharacterRelationships': Map<dynamic, dynamic>.from(rels)};
}

// ── The two registers that live outside the scalar set ────────────────────
//
// Everything else the realism eval reads is a scalar, so it is snapshotted
// into every message's `realism_state` and rewound when a turn is
// regenerated. These two are not scalars — they ride the _groupRealism map —
// and both feed the eval prompt:
//
//   * the inter-character feelings map is injected verbatim, in stepped
//     bands at ±5 / ±25 / ±60 (relationship_injection
//     .buildInterCharacterFeelingsInjection)
//   * the decay cadence decides whether this turn spends a −1 bond
//
// Because neither was ever captured, a GROUP regen could not put them back.
// Every press of Regenerate re-ran the post-generation keyword scan over the
// freshly written reply (chat_service_generation.dart →
// updateInterCharacterFeelingsFromRecentExchange) and nudged the hidden
// feelings another ±2/±4 on top of the last press — permanently, in one
// direction, with no way back. Once the drift crossed a band, a whole new
// sentence appeared in the eval prompt, so the eval saw different input and
// returned different bond/trust numbers. That is the entire reason group
// regens produced fresh deltas while 1:1 regens produced the same ones every
// time: 1:1 has no inter-character map, and at temperature 0.1 an identical
// prompt yields an identical answer.
//
// (_perSpeakerDecay / _decaySpeakerId, read below, now live on the shell
// class body — RelationshipService itself — rather than in this extension;
// see the 2026-08 split's hazard notes.)
//
// Capture/restore are a pair. Keep them that way.

extension RelationshipServiceRewind on RelationshipService {
  /// Snapshot the two out-of-band registers for `realism_state`; pairs with
  /// [restoreFromMessageState]. TURN PATH ONLY (else _decaySpeakerId guesses).
  Map<String, dynamic> captureCadenceAndFeelings() {
    final id = _decaySpeakerId;
    return <String, dynamic>{
      'turnsSinceDecayCheck': _perSpeakerDecay
          ? getGroupCounter!(id, 'turnsSinceDecayCheck', defaultValue: 0)
          : _turnsSinceDecayCheck,
      if (getIsGroupActive() && getShouldTrackInterCharacterRelationships())
        'interCharacterRelationships': Map<String, int>.from(
          getInterCharacterRelationships(id),
        ),
    };
  }

  // ── Inter-character (verbatim) ─────────────────────────────────────────────

  void updateInterCharacterRelationship(
    String fromCharId,
    String toCharId,
    int delta,
  ) {
    if (!getIsGroupActive()) return;
    // Soft-exclude only when the full-member set is wired (ChatService).
    // An empty set is the extracted-leaf default — clamp/create must still
    // work for any ids the caller passes.
    final full = getCurrentGroupMemberIds();
    if (full.isNotEmpty &&
        (!full.contains(fromCharId) || !full.contains(toCharId))) {
      return;
    }

    final currentMap = Map<String, int>.from(
      getInterCharacterRelationships(fromCharId),
    );
    final currentValue = currentMap[toCharId] ?? 0;
    final newValue = (currentValue + delta).clamp(-300, 300);

    setGroupInterCharacterRelationships(fromCharId, {
      ...currentMap,
      toCharId: newValue,
    });
  }

  /// Ensures the hidden inter-character 'relationships' map for this speaker
  /// contains a neutral (0) entry for every other current member of the group.
  /// Verbatim from original (prune + seed).
  void ensureInterCharacterRelationshipsSeeded(String charId) {
    if (!getShouldTrackInterCharacterRelationships()) return;
    if (!getIsGroupActive() || getObserverMode()) return;
    if (getGroupCharacterCount() < 2) return;
    if (!getCurrentGroupMemberIds().contains(charId)) return;

    final currentRels = Map<String, int>.from(
      getInterCharacterRelationships(charId),
    );
    bool changed = false;

    // Prune relationships to characters who are no longer in the group (membership change handling)
    final currentMemberIds = getCurrentGroupMemberIds();
    final stale = currentRels.keys
        .where((id) => !currentMemberIds.contains(id))
        .toList();
    for (final staleId in stale) {
      currentRels.remove(staleId);
      changed = true;
    }

    // Seed neutral 0 for any current members we don't have an entry for yet
    for (final otherId in getOtherGroupMemberIds(charId)) {
      if (!currentRels.containsKey(otherId)) {
        currentRels[otherId] = 0;
        changed = true;
      }
    }

    if (changed) {
      setGroupInterCharacterRelationships(charId, currentRels);
      debugPrint(
        '[Realism:Group] Updated inter-character relationships for $charId (seeded + pruned stale)',
      );
    }
  }

  /// Lightweight heuristic update for hidden inter-character feelings.
  /// Verbatim from original (recent text scan + sentiment word lists + deltas).
  void updateInterCharacterFeelingsFromRecentExchange(String speakerId) {
    if (!getShouldTrackInterCharacterRelationships()) return;
    if (!getIsGroupActive() || getMessageCount() < 2) return;
    if (!getCurrentGroupMemberIds().contains(speakerId)) return;

    final rels = Map<String, int>.from(
      getInterCharacterRelationships(speakerId),
    );
    if (rels.isEmpty) return;

    final recent = getRecentExchangeLowerText();
    bool changed = false;

    final otherNames = getOtherGroupMemberIdToLowerName(speakerId);
    for (final otherId in rels.keys) {
      if (!otherNames.containsKey(otherId)) continue;
      final otherName = otherNames[otherId]!;
      if (!recent.contains(otherName)) continue;

      // Very simple sentiment heuristics
      int delta = 0;
      if (recent.contains('love') ||
          recent.contains('adore') ||
          recent.contains('wonderful') ||
          recent.contains('great') ||
          recent.contains('amazing') ||
          recent.contains('friend')) {
        delta = 4;
      } else if (recent.contains('hate') ||
          recent.contains('annoying') ||
          recent.contains('stupid') ||
          recent.contains('awful') ||
          recent.contains('dislike') ||
          recent.contains('enemy')) {
        delta = -4;
      } else if (recent.contains('like') ||
          recent.contains('nice') ||
          recent.contains('good')) {
        delta = 2;
      } else if (recent.contains('bad') ||
          recent.contains('rude') ||
          recent.contains('problem')) {
        delta = -2;
      }

      if (delta != 0) {
        final newVal = (rels[otherId]! + delta).clamp(-300, 300);
        rels[otherId] = newVal;
        changed = true;
      }
    }

    if (changed) {
      setGroupInterCharacterRelationships(speakerId, rels);
      debugPrint(
        '[Realism:Group] Updated hidden inter-char feelings for $speakerId from recent exchange',
      );
    }
  }

  // ── Snapshot / restore support (for message state roundtrips in regen) ─────

  /// [groupSpeakerId] names the member being rewound, and is passed ONLY by the
  /// regen revert — the one caller that knows which member's turn is being
  /// undone. Without it a group session skips the two out-of-band registers
  /// rather than guess: writing the 1:1 scalar would silently do nothing, and
  /// writing another member's map entry would corrupt them.
  void restoreFromMessageState(
    Map<dynamic, dynamic> state, {
    String? groupSpeakerId,
  }) {
    _affectionScore = (state['affectionScore'] as int?) ?? _affectionScore;
    _relationshipTier =
        (state['relationshipTier'] as int?) ?? _relationshipTier;
    _longTermScore = (state['longTermScore'] as int?) ?? _longTermScore;
    _longTermTier = (state['longTermTier'] as int?) ?? _longTermTier;
    _turnsSinceLongTermCheck =
        (state['turnsSinceLongTermCheck'] as int?) ?? _turnsSinceLongTermCheck;
    _shortTermDeltasSummary =
        (state['shortTermDeltasSummary'] as int?) ?? _shortTermDeltasSummary;

    _trustLevel = (state['trustLevel'] as int?) ?? _trustLevel;
    if (state.containsKey('pendingTrustRepair')) {
      final v = state['pendingTrustRepair'];
      pendingTrustRepair = v == true || v == 1;
    }
    _activeFixation = (state['activeFixation'] as String?) ?? _activeFixation;
    _fixationLifespan =
        (state['fixationLifespan'] as int?) ?? _fixationLifespan;
    _spatialStance = (state['spatialStance'] as String?) ?? _spatialStance;
    if (state.containsKey('withUser')) {
      final v = state['withUser'];
      _withUser = v is bool ? v : null;
    }

    // The pair to captureCadenceAndFeelings. Messages written before these keys
    // existed simply carry neither, so both stay null and nothing is restored —
    // which is exactly the old behaviour, not a new failure mode.
    final cadence = state['turnsSinceDecayCheck'] as int?;
    final rels = state['interCharacterRelationships'];
    if (groupSpeakerId != null && groupSpeakerId.isNotEmpty) {
      if (cadence != null && setGroupCounter != null) {
        setGroupCounter!(groupSpeakerId, 'turnsSinceDecayCheck', cadence);
      }
      if (rels is Map) {
        setGroupInterCharacterRelationships(
          groupSpeakerId,
          rels.map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        );
      }
    } else if (!getIsGroupActive() && cadence != null) {
      _turnsSinceDecayCheck = cadence;
    }
  }

  // Minimal surface for regen revert of trust (avoids re-arming the repair window
  // that applyTrustDelta does for forward deltas).
  void setTrustLevelForRevert(int v) {
    _trustLevel = v.clamp(-100, 100);
  }
}
