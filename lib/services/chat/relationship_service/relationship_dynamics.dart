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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/chat/relationship_milestones.dart';

import '../relationship_service.dart';
import '../relationship_tiers.dart';
import 'relationship_scalars.dart';

// ── Deltas, growth, decay (verbatim) ───────────────────────────────────────

/// Forward bond / trust deltas, long-term growth and short-term decay for a
/// [RelationshipService]. Mutates the service's [RelationshipScalars] and
/// reaches parent-owned group state through the service's callbacks.
class RelationshipDynamics {
  RelationshipDynamics(this._h, this._s);

  final RelationshipService _h;
  final RelationshipScalars _s;

  /// Apply a short-term bond delta. When the named short-term tier changes
  /// and [recordMilestone] is true, fires [RelationshipService.onTierCrossing] (Living Time
  /// v1.5). Every [kLongTermCheckEvery] applies also runs long-term growth,
  /// which may fire a separate `long_term` crossing (v1.5.1). Regen/reprocess
  /// passes [recordMilestone]: false so undoing a rejected reply never invents
  /// reverse story beats (short- or long-term).
  void applyScoreDelta(int delta, {bool recordMilestone = true}) {
    _s.shortTermDeltasSummary += delta;
    _s.turnsSinceLongTermCheck++;

    if (_s.turnsSinceLongTermCheck >= kLongTermCheckEvery) {
      _evalLongTermGrowth(recordMilestone: recordMilestone);
    }

    if (delta == 0) return;
    final oldScore = _s.affectionScore;
    final oldTier = _s.relationshipTier;
    final oldLabel = RelationshipTiers.bondTierLabel(oldTier);

    _s.affectionScore = (_s.affectionScore + delta).clamp(-300, 300);
    _s.relationshipTier = RelationshipTiers.bondTierFor(_s.affectionScore);

    if (_s.affectionScore != oldScore || _s.relationshipTier != oldTier) {
      debugPrint(
        '[Realism] Short-Term Bond: $oldScore \u2192 ${_s.affectionScore}, '
        'Tier: $oldTier \u2192 ${_s.relationshipTier} (${_h.shortTermTierName})',
      );
      _h.onNotify();
    }
    if (recordMilestone &&
        oldTier != _s.relationshipTier &&
        _h.onTierCrossing != null) {
      _h.onTierCrossing!(
        TierCrossing(
          axis: 'bond',
          oldTier: oldTier,
          newTier: _s.relationshipTier,
          oldLabel: oldLabel,
          newLabel: _h.shortTermTierName,
        ),
      );
    }
  }

  /// Apply a trust delta. Tier crossings fire [RelationshipService.onTierCrossing] when
  /// [recordMilestone] is true (default). Severe drops still arm repair.
  void applyTrustDelta(int delta, {bool recordMilestone = true}) {
    if (delta == 0) return;
    final oldTier = _h.trustTier;
    final oldLabel = RelationshipTiers.trustTierLabel(oldTier);
    _s.trustLevel = (_s.trustLevel + delta).clamp(-100, 100);
    final newTier = _h.trustTier;
    debugPrint(
      '[Realism:Relationship] Trust shifted by $delta -> ${_s.trustLevel}',
    );
    _h.onNotify(); // notify on any trust shift (bond/long/short already do on change) so sidebar live-updates from realism eval results / chips
    // Arm the repair window on any severe single-turn drop
    if (delta <= -20) {
      _s.pendingTrustRepair = true;
      debugPrint('[Realism:Trust] Severe drop — repair window armed');
    }
    if (recordMilestone && oldTier != newTier && _h.onTierCrossing != null) {
      _h.onTierCrossing!(
        TierCrossing(
          axis: 'trust',
          oldTier: oldTier,
          newTier: newTier,
          oldLabel: oldLabel,
          newLabel: RelationshipTiers.trustTierLabel(newTier),
        ),
      );
    }
  }

  void _evalLongTermGrowth({bool recordMilestone = true}) {
    final oldLTScore = _s.longTermScore;
    final oldLTTier = _s.longTermTier;
    final oldLabel = RelationshipTiers.longTermTierLabel(oldLTTier);

    // Proportional growth based on average short-term tier over the evaluation window
    // (use current tier as proxy for recent average)
    final avgTier = _s.relationshipTier;

    if (avgTier >= 7) {
      _s.longTermScore = (_s.longTermScore + 3).clamp(-300, 300);
    } else if (avgTier >= 4) {
      _s.longTermScore = (_s.longTermScore + 2).clamp(-300, 300);
    } else if (avgTier >= 2) {
      _s.longTermScore = (_s.longTermScore + 1).clamp(-300, 300);
    } else if (avgTier <= -7) {
      _s.longTermScore = (_s.longTermScore - 3).clamp(-300, 300);
    } else if (avgTier <= -4) {
      _s.longTermScore = (_s.longTermScore - 2).clamp(-300, 300);
    } else if (avgTier <= -2) {
      _s.longTermScore = (_s.longTermScore - 1).clamp(-300, 300);
    }
    // Between -1 and +1: no long-term change (neutral drift doesn't cement)

    _s.longTermTier = RelationshipTiers.bondTierFor(_s.longTermScore);
    _s.turnsSinceLongTermCheck = 0;
    _s.shortTermDeltasSummary = 0;

    if (_s.longTermScore != oldLTScore || _s.longTermTier != oldLTTier) {
      debugPrint(
        '[Realism] Long-Term Bond updated: $oldLTScore \u2192 ${_s.longTermScore}, '
        'Tier: $oldLTTier \u2192 ${_s.longTermTier} (${_h.longTermTierName})',
      );
      _h.onNotify();
    } else {
      debugPrint(
        '[Realism] Long-Term Bond check (No change) - Status: ${_s.longTermScore} (${_h.longTermTierName})',
      );
    }
    // Living Time v1.5.1: plant only when the *named* long-term tier moves.
    // Score ticks inside the same tier stay silent (climate, not weather).
    if (recordMilestone &&
        oldLTTier != _s.longTermTier &&
        _h.onTierCrossing != null) {
      _h.onTierCrossing!(
        TierCrossing(
          axis: 'long_term',
          oldTier: oldLTTier,
          newTier: _s.longTermTier,
          oldLabel: oldLabel,
          newLabel: _h.longTermTierName,
        ),
      );
    }
  }

  /// Short-term relationship decay (toward 0 by 1 every 10 turns) + hidden
  /// inter-char decay (when under cap). Extracted from _applyMoodDecay body.
  ///
  /// Cadence counter: in a group with the counter callbacks wired, the check
  /// runs on the SPEAKER's own counter (their map entry) — so it is safe to
  /// call before the scalar load, and each member decays every 10 of THEIR
  /// OWN turns, exactly like a 1:1 host. Unwired (tests) falls back to the
  /// legacy shared register.
  void applyShortTermDecay() {
    final isGroup = _h.getIsGroupActive() && !_h.getObserverMode();
    final perSpeaker = _h.perSpeakerDecay;
    final speakerId = isGroup ? _h.decaySpeakerId : '';
    var turns = perSpeaker
        ? _h.getGroupCounter!(
            speakerId,
            'turnsSinceDecayCheck',
            defaultValue: 0,
          )
        : _s.turnsSinceDecayCheck;
    turns++;
    if (turns < 10) {
      if (perSpeaker) {
        _h.setGroupCounter!(speakerId, 'turnsSinceDecayCheck', turns);
      } else {
        _s.turnsSinceDecayCheck = turns;
      }
      return;
    }
    if (perSpeaker) {
      _h.setGroupCounter!(speakerId, 'turnsSinceDecayCheck', 0);
    } else {
      _s.turnsSinceDecayCheck = 0;
    }
    {
      if (isGroup) {
        final id = speakerId;
        final current = _h.getGroupAffectionScore(
          id,
          defaultValue: _s.affectionScore,
        );
        final next = current > 0
            ? (current - 1).clamp(-300, 300)
            : current < 0
            ? (current + 1).clamp(-300, 300)
            : current;
        _h.setGroupAffectionScore(id, next);
        if (next != 0) {
          debugPrint('[Realism] Group short-term decay for $id: $next');
        }

        // Phase 2/3: Decay hidden inter-character relationships (only when under the 4-char cap)
        // mirrors outer group non-observer scoping for inter decay (verbatim)
        if (_h.getShouldTrackInterCharacterRelationships() &&
            _h.getCurrentGroupMemberIds().contains(id)) {
          final rels = Map<String, int>.from(
            _h.getInterCharacterRelationships(id),
          );
          final fullIds = _h.getCurrentGroupMemberIds();
          if (rels.isNotEmpty) {
            bool relChanged = false;
            rels.forEach((otherId, value) {
              if (!fullIds.contains(otherId)) return;
              if (value > 0) {
                rels[otherId] = (value - 1).clamp(-300, 300);
                relChanged = true;
              } else if (value < 0) {
                rels[otherId] = (value + 1).clamp(-300, 300);
                relChanged = true;
              }
            });
            if (relChanged) {
              _h.setGroupInterCharacterRelationships(id, rels);
              debugPrint(
                '[Realism:Group] Decayed inter-character relationships for $id',
              );
            }
          }
        }
      } else {
        // 1:1 scalar path
        if (_s.affectionScore > 0) {
          _s.affectionScore = (_s.affectionScore - 1).clamp(-300, 300);
        } else if (_s.affectionScore < 0) {
          _s.affectionScore = (_s.affectionScore + 1).clamp(-300, 300);
        }
        if (_s.affectionScore != 0) {
          debugPrint(
            '[Realism] Short-term decay applied: ${_s.affectionScore}',
          );
        }
      }
      _h.onNotify();
    }
  }
}
