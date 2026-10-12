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

import '../relationship_service.dart';
import '../relationship_tiers.dart';
import 'relationship_scalars.dart';

/// Per-speaker group load/save of the relationship registers: moves a
/// member's scalars between the parent's _groupRealism entry (via the
/// [RelationshipService] callbacks) and the working [RelationshipScalars].
class RelationshipGroupSync {
  RelationshipGroupSync(this._h, this._s);

  final RelationshipService _h;
  final RelationshipScalars _s;

  /// Load per-speaker relationship scalars (affection/trust/fixation/tiers/spatial)
  /// from the group's _groupRealism map into this service's 1:1-style scalars so
  /// eval/delta/injection paths can operate on them. Mirrors needs pattern.
  void loadRelationshipScalarsForSpeaker(String charId) {
    final aff = _h.getGroupAffectionScore(charId);
    _s.affectionScore = aff;
    _s.longTermScore = _h.getGroupLongTermScore(charId, defaultValue: aff);
    _s.trustLevel = _h.getGroupTrustLevel(charId);
    _s.activeFixation = _h.getGroupFixation(charId);
    _s.fixationLifespan = _h.getGroupFixationLifespan(charId, defaultValue: 0);
    _s.spatialStance = _h.getGroupSpatialStance(charId);
    _s.withUser = _h.getGroupWithUser?.call(charId);

    final relT = _h.getGroupRelationshipTier(charId, defaultValue: 0);
    _s.relationshipTier = relT != 0
        ? relT
        : RelationshipTiers.bondTierFor(_s.affectionScore);
    final ltT = _h.getGroupLongTermTier(charId, defaultValue: 0);
    _s.longTermTier = ltT != 0
        ? ltT
        : RelationshipTiers.bondTierFor(_s.longTermScore);

    // Per-speaker long-term cadence (parity): each member's growth check runs
    // on THEIR OWN eval count and THEIR OWN delta history. With the shared
    // registers, the growth-check threshold was hit by the whole group's evals
    // and the long-term bump landed on whichever member happened to be loaded.
    if (_h.getGroupCounter != null) {
      _s.turnsSinceLongTermCheck = _h.getGroupCounter!(
        charId,
        'turnsSinceLongTermCheck',
        defaultValue: 0,
      );
      _s.shortTermDeltasSummary = _h.getGroupCounter!(
        charId,
        'shortTermDeltasSummary',
        defaultValue: 0,
      );
    }
  }

  /// Write current scalars back into the target group character's _groupRealism
  /// entry (for affection/long/trust/fixation/tiers/spatial). Does not touch needs
  /// or emotion (owned elsewhere).
  void saveRelationshipScalarsToGroup(String charId) {
    _h.setGroupAffectionScore(charId, _s.affectionScore);
    _h.setGroupLongTermScore(charId, _s.longTermScore);
    _h.setGroupTrustLevel(charId, _s.trustLevel);

    // Persist fixation/spatial UNCONDITIONALLY (including clears) so the
    // per-character store is a faithful snapshot of the working registers.
    // Previously these were guarded behind non-empty checks, which meant a
    // cleared fixation/spatial never propagated through save/load — fine while
    // only group members used this path (fixation re-set each turn), but it would
    // silently break fixation-clearing once the always-loaded 1:1 host is unified
    // onto the same store. See relationship_service_test round-trip coverage.
    _h.setGroupFixation(charId, _s.activeFixation);
    _h.setGroupFixationLifespan(charId, _s.fixationLifespan);
    _h.setGroupSpatialStance(charId, _s.spatialStance);
    _h.setGroupWithUser?.call(charId, _s.withUser);

    _h.setGroupRelationshipTier(charId, _s.relationshipTier);
    _h.setGroupLongTermTier(charId, _s.longTermTier);

    // Per-speaker long-term cadence counters (see the load-side comment).
    if (_h.setGroupCounter != null) {
      _h.setGroupCounter!(
        charId,
        'turnsSinceLongTermCheck',
        _s.turnsSinceLongTermCheck,
      );
      _h.setGroupCounter!(
        charId,
        'shortTermDeltasSummary',
        _s.shortTermDeltasSummary,
      );
    }
  }
}
