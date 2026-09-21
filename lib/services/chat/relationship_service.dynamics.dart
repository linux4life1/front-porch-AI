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

// ── Deltas, growth, decay, fixation (verbatim) ─────────────────────────────

extension RelationshipServiceDynamics on RelationshipService {
  /// Apply a short-term bond delta. When the named short-term tier changes
  /// and [recordMilestone] is true, fires [onTierCrossing] (Living Time
  /// v1.5). Every [kLongTermCheckEvery] applies also runs long-term growth,
  /// which may fire a separate `long_term` crossing (v1.5.1). Regen/reprocess
  /// passes [recordMilestone]: false so undoing a rejected reply never invents
  /// reverse story beats (short- or long-term).
  void applyScoreDelta(int delta, {bool recordMilestone = true}) {
    _shortTermDeltasSummary += delta;
    _turnsSinceLongTermCheck++;

    if (_turnsSinceLongTermCheck >= kLongTermCheckEvery) {
      _evalLongTermGrowth(recordMilestone: recordMilestone);
    }

    if (delta == 0) return;
    final oldScore = _affectionScore;
    final oldTier = _relationshipTier;
    final oldLabel = RelationshipTiers.bondTierLabel(oldTier);

    _affectionScore = (_affectionScore + delta).clamp(-300, 300);
    _relationshipTier = _calculateTier(_affectionScore);

    if (_affectionScore != oldScore || _relationshipTier != oldTier) {
      debugPrint(
        '[Realism] Short-Term Bond: $oldScore \u2192 $_affectionScore, '
        'Tier: $oldTier \u2192 $_relationshipTier ($shortTermTierName)',
      );
      onNotify();
    }
    if (recordMilestone &&
        oldTier != _relationshipTier &&
        onTierCrossing != null) {
      onTierCrossing!(
        TierCrossing(
          axis: 'bond',
          oldTier: oldTier,
          newTier: _relationshipTier,
          oldLabel: oldLabel,
          newLabel: shortTermTierName,
        ),
      );
    }
  }

  /// Apply a trust delta. Tier crossings fire [onTierCrossing] when
  /// [recordMilestone] is true (default). Severe drops still arm repair.
  void applyTrustDelta(int delta, {bool recordMilestone = true}) {
    if (delta == 0) return;
    final oldTier = trustTier;
    final oldLabel = RelationshipTiers.trustTierLabel(oldTier);
    _trustLevel = (_trustLevel + delta).clamp(-100, 100);
    final newTier = trustTier;
    debugPrint(
      '[Realism:Relationship] Trust shifted by $delta -> $_trustLevel',
    );
    onNotify(); // notify on any trust shift (bond/long/short already do on change) so sidebar live-updates from realism eval results / chips
    // Arm the repair window on any severe single-turn drop
    if (delta <= -20) {
      pendingTrustRepair = true;
      debugPrint('[Realism:Trust] Severe drop — repair window armed');
    }
    if (recordMilestone && oldTier != newTier && onTierCrossing != null) {
      onTierCrossing!(
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
    final oldLTScore = _longTermScore;
    final oldLTTier = _longTermTier;
    final oldLabel = RelationshipTiers.longTermTierLabel(oldLTTier);

    // Proportional growth based on average short-term tier over the evaluation window
    // (use current tier as proxy for recent average)
    final avgTier = _relationshipTier;

    if (avgTier >= 7) {
      _longTermScore = (_longTermScore + 3).clamp(-300, 300);
    } else if (avgTier >= 4) {
      _longTermScore = (_longTermScore + 2).clamp(-300, 300);
    } else if (avgTier >= 2) {
      _longTermScore = (_longTermScore + 1).clamp(-300, 300);
    } else if (avgTier <= -7) {
      _longTermScore = (_longTermScore - 3).clamp(-300, 300);
    } else if (avgTier <= -4) {
      _longTermScore = (_longTermScore - 2).clamp(-300, 300);
    } else if (avgTier <= -2) {
      _longTermScore = (_longTermScore - 1).clamp(-300, 300);
    }
    // Between -1 and +1: no long-term change (neutral drift doesn't cement)

    _longTermTier = _calculateTier(_longTermScore);
    _turnsSinceLongTermCheck = 0;
    _shortTermDeltasSummary = 0;

    if (_longTermScore != oldLTScore || _longTermTier != oldLTTier) {
      debugPrint(
        '[Realism] Long-Term Bond updated: $oldLTScore \u2192 $_longTermScore, '
        'Tier: $oldLTTier \u2192 $_longTermTier ($longTermTierName)',
      );
      onNotify();
    } else {
      debugPrint(
        '[Realism] Long-Term Bond check (No change) - Status: $_longTermScore ($longTermTierName)',
      );
    }
    // Living Time v1.5.1: plant only when the *named* long-term tier moves.
    // Score ticks inside the same tier stay silent (climate, not weather).
    if (recordMilestone &&
        oldLTTier != _longTermTier &&
        onTierCrossing != null) {
      onTierCrossing!(
        TierCrossing(
          axis: 'long_term',
          oldTier: oldLTTier,
          newTier: _longTermTier,
          oldLabel: oldLabel,
          newLabel: longTermTierName,
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
    final isGroup = getIsGroupActive() && !getObserverMode();
    final perSpeaker = _perSpeakerDecay;
    final speakerId = isGroup ? _decaySpeakerId : '';
    var turns = perSpeaker
        ? getGroupCounter!(speakerId, 'turnsSinceDecayCheck', defaultValue: 0)
        : _turnsSinceDecayCheck;
    turns++;
    if (turns < 10) {
      if (perSpeaker) {
        setGroupCounter!(speakerId, 'turnsSinceDecayCheck', turns);
      } else {
        _turnsSinceDecayCheck = turns;
      }
      return;
    }
    if (perSpeaker) {
      setGroupCounter!(speakerId, 'turnsSinceDecayCheck', 0);
    } else {
      _turnsSinceDecayCheck = 0;
    }
    {
      if (isGroup) {
        final id = speakerId;
        final current = getGroupAffectionScore(
          id,
          defaultValue: _affectionScore,
        );
        final next = current > 0
            ? (current - 1).clamp(-300, 300)
            : current < 0
            ? (current + 1).clamp(-300, 300)
            : current;
        setGroupAffectionScore(id, next);
        if (next != 0) {
          debugPrint('[Realism] Group short-term decay for $id: $next');
        }

        // Phase 2/3: Decay hidden inter-character relationships (only when under the 4-char cap)
        // mirrors outer group non-observer scoping for inter decay (verbatim)
        if (getShouldTrackInterCharacterRelationships() &&
            getCurrentGroupMemberIds().contains(id)) {
          final rels = Map<String, int>.from(
            getInterCharacterRelationships(id),
          );
          final fullIds = getCurrentGroupMemberIds();
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
              setGroupInterCharacterRelationships(id, rels);
              debugPrint(
                '[Realism:Group] Decayed inter-character relationships for $id',
              );
            }
          }
        }
      } else {
        // 1:1 scalar path
        if (_affectionScore > 0) {
          _affectionScore = (_affectionScore - 1).clamp(-300, 300);
        } else if (_affectionScore < 0) {
          _affectionScore = (_affectionScore + 1).clamp(-300, 300);
        }
        if (_affectionScore != 0) {
          debugPrint('[Realism] Short-term decay applied: $_affectionScore');
        }
      }
      onNotify();
    }
  }

  /// Tick fixation lifespan (called every narrative eval turn).
  void decayFixationOneTurn() {
    if (_fixationLifespan > 0) {
      _fixationLifespan--;
      if (_fixationLifespan == 0) {
        _activeFixation = '';
      }
    }
  }

  /// Apply fixation topic result from narrative / one-shot eval.
  /// Debugs are conditioned on isOneShot to match original log tags.
  void updateFixationFromEvalResult(String rawTopic, {bool isOneShot = false}) {
    decayFixationOneTurn();

    String f = rawTopic.trim();
    if (f.toLowerCase() == 'none' || f.isEmpty) {
      _activeFixation = '';
      _fixationLifespan = 0;
      if (isOneShot) {
        debugPrint('[Realism:OneShot] Fixation decayed and cleared.');
      }
    } else if (f != _activeFixation) {
      _activeFixation = f;
      _fixationLifespan = 3;
      if (isOneShot) {
        debugPrint('[Realism:OneShot] New obsession: $f (3 turns)');
      }
    }
  }

  /// Post-load/LLM sanitize for overly long fixation topics (keeps UI/prompts sane).
  /// Called from parent after message load.
  void sanitizeFixationIfTooLong() {
    if (_activeFixation.length > 200) {
      _activeFixation = _activeFixation.substring(0, 200).trimRight() + '…';
      if (_fixationLifespan <= 0) _fixationLifespan = 3;
    }
  }

  void setSpatialStance(String v) {
    _spatialStance = (v.toLowerCase() == 'none' || v.isEmpty) ? '' : v;
  }

  /// Only a real verdict writes. null from a failed eval is ignored.
  void applyWithUserVerdict(bool? v) {
    if (v != null) _withUser = v;
  }

  /// Restore / reset path — null is allowed (unknown).
  void setWithUser(bool? v) {
    _withUser = v;
  }

  /// Consume the one-shot repair window (called on next user turn after armed severe drop).
  void consumePendingTrustRepair() {
    pendingTrustRepair = false;
  }
}
