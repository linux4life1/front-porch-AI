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

import '../relationship_tiers.dart';

/// The owned relationship simulation registers (moved verbatim from
/// ChatService, then from `RelationshipService`'s body). Plain mutable state
/// plus the pure reset / seed / load / small-setter mutations that touch
/// nothing but these registers. `RelationshipService` owns one instance and
/// shares it with its collaborators.
class RelationshipScalars {
  int affectionScore = 0;
  int relationshipTier = 0;

  // Long-Term Bond
  int longTermScore = 0;
  int longTermTier = 0;
  int turnsSinceLongTermCheck = 0;
  int shortTermDeltasSummary = 0;
  int turnsSinceDecayCheck =
      0; // counter for short-term relationship decay (every 10 turns)

  // v3 Behavioral
  int trustLevel = 0; // -100 to 100
  String activeFixation = '';
  int fixationLifespan = 0; // turns until fixation naturally clears
  String spatialStance = '';

  /// null = unknown (fail closed — glance uses keywords / inScene).
  bool? withUser;

  // Armed on each severe trust drop (≥ -20 delta). Consumed on the very next user
  // message, then resets so future drops each get one shot.
  bool pendingTrustRepair = false;

  // ── Reset / seed / load helpers (support "keep reset blocks in sync" in parent) ──

  void reset() {
    affectionScore = 0;
    relationshipTier = 0;
    longTermScore = 0;
    longTermTier = 0;
    turnsSinceLongTermCheck = 0;
    shortTermDeltasSummary = 0;
    turnsSinceDecayCheck = 0;
    trustLevel = 0;
    activeFixation = '';
    fixationLifespan = 0;
    spatialStance = '';
    withUser = null;
    pendingTrustRepair = false;
  }

  /// Card V2/Ext seed path: plain clamp (current ±300 scale authored by V2.5 cards
  /// and the creator UI). No legacy *2 migration. Tiers computed after. Used by the
  /// two fresh ext-seed sites in ChatService (setActiveCharacter 0-session path and
  /// startNewChat 1:1 ext branch). Group paths untouched (never used the doubling).
  /// See god comments for "card-seed bypass" + cross-refs.
  void seedFromCard({
    required int shortTermBond,
    required int longTermBond,
    required int trustLevel,
  }) {
    affectionScore = shortTermBond.clamp(-300, 300);
    longTermScore = longTermBond.clamp(-300, 300);
    this.trustLevel = trustLevel.clamp(-100, 100);
    relationshipTier = RelationshipTiers.bondTierFor(affectionScore);
    longTermTier = RelationshipTiers.bondTierFor(longTermScore);
  }

  /// Canonical scalar-restore entry (realism_state load, chip revert, tests).
  void load({
    required int affectionScore,
    required int longTermScore,
    required int trustLevel,
    String activeFixation = '',
    int fixationLifespan = 0,
    String spatialStance = '',
    bool? withUser,
    bool trustRepairPending = false,
    int turnsSinceLongTermCheck = 0,
    int shortTermDeltasSummary = 0,
    int turnsSinceDecayCheck = 0,
  }) {
    this.affectionScore = affectionScore;
    this.longTermScore = longTermScore;
    this.trustLevel = trustLevel;
    this.activeFixation = activeFixation;
    this.fixationLifespan = fixationLifespan;
    this.spatialStance = spatialStance;
    this.withUser = withUser;
    pendingTrustRepair = trustRepairPending;
    this.turnsSinceLongTermCheck = turnsSinceLongTermCheck;
    this.shortTermDeltasSummary = shortTermDeltasSummary;
    this.turnsSinceDecayCheck = turnsSinceDecayCheck;

    relationshipTier = RelationshipTiers.bondTierFor(this.affectionScore);
    longTermTier = RelationshipTiers.bondTierFor(this.longTermScore);
  }

  // ── Fixation / spatial / with-user registers (verbatim) ───────────────────

  /// Tick fixation lifespan (called every narrative eval turn).
  void decayFixationOneTurn() {
    if (fixationLifespan > 0) {
      fixationLifespan--;
      if (fixationLifespan == 0) {
        activeFixation = '';
      }
    }
  }

  /// Apply fixation topic result from narrative / one-shot eval.
  /// Debugs are conditioned on isOneShot to match original log tags.
  void updateFixationFromEvalResult(String rawTopic, {bool isOneShot = false}) {
    decayFixationOneTurn();

    String f = rawTopic.trim();
    if (f.toLowerCase() == 'none' || f.isEmpty) {
      activeFixation = '';
      fixationLifespan = 0;
      if (isOneShot) {
        debugPrint('[Realism:OneShot] Fixation decayed and cleared.');
      }
    } else if (f != activeFixation) {
      activeFixation = f;
      fixationLifespan = 3;
      if (isOneShot) {
        debugPrint('[Realism:OneShot] New obsession: $f (3 turns)');
      }
    }
  }

  /// Post-load/LLM sanitize for overly long fixation topics (keeps UI/prompts sane).
  /// Called from parent after message load.
  void sanitizeFixationIfTooLong() {
    if (activeFixation.length > 200) {
      activeFixation = activeFixation.substring(0, 200).trimRight() + '…';
      if (fixationLifespan <= 0) fixationLifespan = 3;
    }
  }

  void setSpatialStance(String v) {
    spatialStance = (v.toLowerCase() == 'none' || v.isEmpty) ? '' : v;
  }

  /// Only a real verdict writes. null from a failed eval is ignored.
  void applyWithUserVerdict(bool? v) {
    if (v != null) withUser = v;
  }

  // Minimal surface for regen revert of trust (avoids re-arming the repair window
  // that applyTrustDelta does for forward deltas).
  void setTrustLevelForRevert(int v) {
    trustLevel = v.clamp(-100, 100);
  }
}
