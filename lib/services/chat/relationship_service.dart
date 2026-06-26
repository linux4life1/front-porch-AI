// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Software Foundation, either version 3 of the License, or
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

/// Plain (non-ChangeNotifier) domain service owning relationship / affection /
/// trust / fixation / inter-character feelings state and logic (scores, bond+trust
/// deltas via apply, tier calculation, fixation lifespan+update, short/long term
/// progress, legacy migrations, short-term decay toward neutral + inter-char
/// decay, inter-char seeding + heuristic update from recent exchange, group per-char
/// scalar load/save, reset/seed/load helpers).
///
/// ChatService owns the instance via a private late final and delegates. All cross
/// state that lives in the parent for now (_groupRealism map for per-char in group,
/// messages for inter-char heuristic, group membership for seeding/prune, current
/// speaker, observer mode, etc.) is accessed exclusively via callbacks supplied at
/// construction. This keeps the extracted service testable and avoids cycles.
/// (Granular callbacks chosen over a full parent interface ref for this leaf
/// extraction per the Stage 3 precedent in needs/chaos and updated plan guidance
/// in refactoring-guide.md.)
///
/// Extraction is mechanical: original fields, _calculateTier, _migrate*, tier name
/// getters, the decay logic (formerly inside _applyMoodDecay), fixation tick/set logic
/// (from narrative + one-shot paths),
/// _ensureInterCharacterRelationshipsSeeded, _updateInterCharacterFeelingsFromRecentExchange,
/// all the reset/seed/load sites logic, group scalar syncs for rel fields, and
/// snapshot/restore mutations copied verbatim (no rewrite of delta math, tier calc,
/// clamp ranges, inter-char heuristic, prune+seed, decay rules, fixation 3-turn,
/// legacy *10 migration, group vs 1:1 scoping).
///
/// Group vs 1:1 parity preserved exactly: in group, per-speaker scalars live in
/// _groupRealism (via load/save helpers + granular cbs) and inter-char 'relationships'
/// map per speaker (only when <=4 members); 1:1 uses the owned scalars directly.
/// Chat-scoped aspects (e.g. some overall) unchanged.
///
/// UI-coordination / prompt injection related surfaces (_getRelationshipInjection,
/// _getTrustBehaviorInjection, pendingRealismMetadata writes, some mood counter,
/// _groupRealism map itself) stay in ChatService (to be thinned in step 8+).
/// @Deprecated shims on ChatService preserve the public surface (affectionScore,
/// relationshipTier, trustLevel, trustTier, activeFixation, fixationLifespan,
/// short/longTerm*Score/Tier + progress getters + tierName getters + inter-char
/// public methods) for callers and tests.
///
/// Reset helpers (resetForFreshChat, seedFromV2OrExt, seedFromCardV2OrExt,
/// loadScalars, applyLegacyMigrationIfNeeded, loadRelationshipScalarsForSpeaker,
/// saveRelationshipScalarsToGroup) support the documented "keep reset blocks in sync"
/// sites in parent without adding private helpers to the god file.
///
/// seedFromCardV2OrExt does *plain clamp only* (no migration) for fresh V2.5 card
/// ext seeds on new 1:1 chats (card authors use the current ±300 scale). The
/// original seedFromV2OrExt (which applies legacy ±150->*2 migration) is retained
/// for direct test coverage of the migration path and any future legacy session
/// seed compatibility; production legacy session loads use the explicit
/// migrateShortTermScore / migrateLongTermScore + loadScalars + applyLegacy...
/// paths in ChatService (see "card-seed bypass" notes in god keep-sync comments).
///
/// 0 new private methods added to ChatService as part of this step (thins + delegations only;
/// deletions of moved code are mandatory part of the task).
class RelationshipService {
  final VoidCallback onNotify;
  final Future<void> Function() onSaveChat;

  // Callbacks for parent-owned cross-domain state (group realism map, membership,
  // messages for heuristic, speaker/observer for scoping, etc.). These remain in
  // ChatService until their owning domains are extracted in later steps.
  final bool Function() getIsGroupActive;
  final bool Function() getObserverMode;
  final int Function() getGroupCharacterCount;
  final bool Function() getShouldTrackInterCharacterRelationships;
  final String Function() getCurrentSpeakerIdForRealism;
  final Set<String> Function() getCurrentGroupMemberIds;
  final List<String> Function(String selfId) getOtherGroupMemberIds;
  final Map<String, String> Function(String selfId)
  getOtherGroupMemberIdToLowerName;
  final String Function() getRecentExchangeLowerText;
  final int Function() getMessageCount;
  final bool Function() getIsGroupRealismActive;

  // Granular per-char group realism accessors (for bond/trust/fixation/tiers/scores
  // that live in _groupRealism map while in group mode; mirrors needs get/setGroupNeeds).
  final int Function(String charId, {int defaultValue}) getGroupAffectionScore;
  final void Function(String charId, int value) setGroupAffectionScore;
  final int Function(String charId, {int defaultValue}) getGroupLongTermScore;
  final void Function(String charId, int value) setGroupLongTermScore;
  final int Function(String charId, {int defaultValue}) getGroupTrustLevel;
  final void Function(String charId, int value) setGroupTrustLevel;
  final String Function(String charId, {String defaultValue}) getGroupFixation;
  final void Function(String charId, String value) setGroupFixation;
  final int Function(String charId, {int defaultValue})
  getGroupFixationLifespan;
  final void Function(String charId, int value) setGroupFixationLifespan;
  final int Function(String charId, {int defaultValue})
  getGroupRelationshipTier;
  final void Function(String charId, int value) setGroupRelationshipTier;
  final int Function(String charId, {int defaultValue}) getGroupLongTermTier;
  final void Function(String charId, int value) setGroupLongTermTier;
  final String Function(String charId, {String defaultValue})
  getGroupSpatialStance;
  final void Function(String charId, String value) setGroupSpatialStance;

  // Inter-character hidden feelings map (per speaker, only when group <=4).
  final Map<String, int> Function(String charId)
  getGroupInterCharacterRelationships;
  final void Function(String charId, Map<String, int> rels)
  setGroupInterCharacterRelationships;

  // Owned simulation state (moved verbatim from ChatService).
  int _affectionScore = 0;
  int _relationshipTier = 0;

  // Long-Term Bond
  int _longTermScore = 0;
  int _longTermTier = 0;
  int _turnsSinceLongTermCheck = 0;
  int _shortTermDeltasSummary = 0;
  int _turnsSinceDecayCheck =
      0; // counter for short-term relationship decay (every 10 turns)

  // v3 Behavioral
  int _trustLevel = 0; // -100 to 100
  String _activeFixation = '';
  int _fixationLifespan = 0; // turns until fixation naturally clears
  String _spatialStance = '';

  // Armed on each severe trust drop (≥ -20 delta). Consumed on the very next user
  // message, then resets so future drops each get one shot.
  bool _pendingTrustRepair = false;

  RelationshipService({
    required this.onNotify,
    required this.onSaveChat,
    required this.getIsGroupActive,
    required this.getObserverMode,
    required this.getGroupCharacterCount,
    required this.getShouldTrackInterCharacterRelationships,
    required this.getCurrentSpeakerIdForRealism,
    required this.getCurrentGroupMemberIds,
    required this.getOtherGroupMemberIds,
    required this.getOtherGroupMemberIdToLowerName,
    required this.getRecentExchangeLowerText,
    required this.getMessageCount,
    required this.getIsGroupRealismActive,
    required this.getGroupAffectionScore,
    required this.setGroupAffectionScore,
    required this.getGroupLongTermScore,
    required this.setGroupLongTermScore,
    required this.getGroupTrustLevel,
    required this.setGroupTrustLevel,
    required this.getGroupFixation,
    required this.setGroupFixation,
    required this.getGroupFixationLifespan,
    required this.setGroupFixationLifespan,
    required this.getGroupRelationshipTier,
    required this.setGroupRelationshipTier,
    required this.getGroupLongTermTier,
    required this.setGroupLongTermTier,
    required this.getGroupSpatialStance,
    required this.setGroupSpatialStance,
    required this.getGroupInterCharacterRelationships,
    required this.setGroupInterCharacterRelationships,
  });

  // ── Public surface (for @Deprecated shims in ChatService + direct test/UI callers) ──────

  int get affectionScore => _affectionScore;
  int get relationshipTier => _relationshipTier;
  int get longTermScore => _longTermScore;
  int get longTermTier => _longTermTier;
  int get trustLevel => _trustLevel;
  int get trustTier => _calculateTier(_trustLevel);
  bool get pendingTrustRepair => _pendingTrustRepair;
  String get activeFixation => _activeFixation;
  int get fixationLifespan => _fixationLifespan;
  String get spatialStance => _spatialStance;

  // Counters for snapshot/restore parity (used by capture in parent).
  int get turnsSinceLongTermCheck => _turnsSinceLongTermCheck;
  int get shortTermDeltasSummary => _shortTermDeltasSummary;

  // Progress helpers for relationship bars (UI + tests). Delegate to the pure
  // static scale helpers (below) so the band math is one source of truth, shared
  // with read-only per-member consumers (the web group stats panel).
  int get shortTermProgressTarget => _bondScaleTarget(_affectionScore.abs());
  int get shortTermProgressBase => _bondScaleBase(_affectionScore.abs());
  double get shortTermProgressPercent => bondScalePercent(_affectionScore);

  int get longTermProgressTarget => _bondScaleTarget(_longTermScore.abs());
  int get longTermProgressBase => _bondScaleBase(_longTermScore.abs());
  double get longTermProgressPercent => bondScalePercent(_longTermScore);

  int get trustProgressBase => _trustScaleBase(_trustLevel.abs());
  int get trustProgressTarget => _trustScaleTarget(_trustLevel.abs());
  double get trustProgressPercent => trustScalePercent(_trustLevel);

  // ── Pure tier/percent scale helpers — single source of truth, shared by the
  // live instance getters above AND read-only per-member consumers (the web
  // group stats panel computes a member's tier/bar from its raw scores). ──────
  /// 0..1 progress within the current bond / long-term tier band (±300 scale).
  static double bondScalePercent(int score) {
    final abs = score.abs();
    final base = _bondScaleBase(abs);
    final total = _bondScaleTarget(abs) - base;
    return total <= 0 ? 0.0 : ((abs - base) / total).clamp(0.0, 1.0);
  }

  static int _bondScaleBase(int abs) {
    if (abs < 15) return 0;
    if (abs < 30) return 15;
    if (abs < 50) return 30;
    if (abs < 80) return 50;
    if (abs < 120) return 80;
    if (abs < 160) return 120;
    if (abs < 200) return 160;
    if (abs < 250) return 200;
    return 250;
  }

  static int _bondScaleTarget(int abs) {
    if (abs < 15) return 15;
    if (abs < 30) return 30;
    if (abs < 50) return 50;
    if (abs < 80) return 80;
    if (abs < 120) return 120;
    if (abs < 160) return 160;
    if (abs < 200) return 200;
    if (abs < 250) return 250;
    return 300; // max for ±300 range
  }

  /// 0..1 progress within the current trust tier band (±100 scale).
  static double trustScalePercent(int level) {
    final abs = level.abs();
    final base = _trustScaleBase(abs);
    final total = _trustScaleTarget(abs) - base;
    return total <= 0 ? 0.0 : ((abs - base) / total).clamp(0.0, 1.0);
  }

  static int _trustScaleBase(int abs) {
    if (abs < 10) return 0;
    if (abs < 25) return 10;
    if (abs < 45) return 25;
    if (abs < 70) return 45;
    if (abs < 100) return 70;
    return 100;
  }

  static int _trustScaleTarget(int abs) {
    if (abs < 10) return 10;
    if (abs < 25) return 25;
    if (abs < 45) return 45;
    if (abs < 70) return 70;
    return 100;
  }

  /// Human-readable tier name for the current relationship level.
  /// Calculate tier for 21-tier system (-10 to +10) for short/long-term bonds
  /// with new range ±300.
  String get shortTermTierName => bondTierLabel(_relationshipTier);

  /// Pure bond/short-term tier name for a tier index (-10..10). Shared by the
  /// live getter and read-only per-member consumers (web group stats panel).
  static String bondTierLabel(int tier) {
    switch (tier) {
      case 10:
        return 'Devoted';
      case 9:
        return 'Enamored';
      case 8:
        return 'Devoted';
      case 7:
        return 'Intimate';
      case 6:
        return 'Close';
      case 5:
        return 'Amiable';
      case 4:
        return 'Friendly';
      case 3:
        return 'Warm';
      case 2:
        return 'Receptive';
      case 1:
        return 'Neutral';
      case 0:
        return 'Neutral';
      case -1:
        return 'Reserved';
      case -2:
        return 'Cool';
      case -3:
        return 'Unimpressed';
      case -4:
        return 'Annoyed';
      case -5:
        return 'Disliked';
      case -6:
        return 'Hostile';
      case -7:
        return 'Adversarial';
      case -8:
        return 'Disdain';
      case -9:
        return 'Contempt';
      case -10:
        return 'Vitriolic';
      default:
        return 'Unknown';
    }
  }

  String get longTermTierName => longTermTierLabel(_longTermTier);

  /// Pure long-term tier name for a tier index (-10..10).
  static String longTermTierLabel(int tier) {
    switch (tier) {
      case 10:
        return 'Soulmate / Devoted';
      case 9:
        return 'Life Partner';
      case 8:
        return 'Devoted';
      case 7:
        return 'Deeply Attached';
      case 6:
        return 'Intimate';
      case 5:
        return 'Close';
      case 4:
        return 'Friendly';
      case 3:
        return 'Warm';
      case 2:
        return 'Receptive';
      case 1:
        return 'Neutral';
      case 0:
        return 'Neutral';
      case -1:
        return 'Reserved';
      case -2:
        return 'Cool';
      case -3:
        return 'Disappointed';
      case -4:
        return 'Fractured';
      case -5:
        return 'Broken Trust';
      case -6:
        return 'Deep Resentment';
      case -7:
        return 'Hostile';
      case -8:
        return 'Adversarial';
      case -9:
        return 'Contempt';
      case -10:
        return 'Vitriolic';
      default:
        return 'Unknown';
    }
  }

  String get trustTierName => trustTierLabel(trustTier);

  /// Pure trust tier name for a trust tier index.
  static String trustTierLabel(int tier) {
    switch (tier) {
      case 7:
        return 'Blind Trust';
      case 6:
        return 'Implicit Trust';
      case 5:
        return 'Deeply Trusting';
      case 4:
        return 'Confident Trust';
      case 3:
        return 'Trusting';
      case 2:
        return 'Leaning Positive';
      case 1:
        return 'Cautious';
      case 0:
        return 'Neutral';
      case -1:
        return 'Cautious';
      case -2:
        return 'Guarded';
      case -3:
        return 'Skeptical';
      case -4:
        return 'Wary';
      case -5:
        return 'Suspicious';
      case -6:
        return 'Distrustful';
      case -7:
        return 'Paranoid';
      default:
        return 'Unknown';
    }
  }

  /// Public for any load-site default computation that needs it (e.g. group scalar
  /// fallbacks). Internal logic always prefers provided group tier or computes.
  int calculateTier(int score) => _calculateTier(score);

  // Per-score read helpers for consumers that need a tier name / bar percent for
  // an arbitrary score without mutating live state (e.g. the web per-group-member
  // stats panel). Compose the pure label/scale statics — single source of truth.
  String bondTierNameForScore(int score) => bondTierLabel(calculateTier(score));
  String longTermTierNameForScore(int score) =>
      longTermTierLabel(calculateTier(score));
  String trustTierNameForLevel(int level) => trustTierLabel(calculateTier(level));
  double bondPercentForScore(int score) => bondScalePercent(score);
  double trustPercentForLevel(int level) => trustScalePercent(level);

  /// Public migrate helpers for load paths (kept internal impl private; surface
  /// only for the 2-3 legacy scale sites in ChatService that load persisted old
  /// ±150 session data). Card V2/Ext fresh seeds use seedFromCardV2OrExt (plain
  /// clamp, no migration) to avoid doubling author-intended values on new chats.
  int migrateShortTermScore(int rawScore) => _migrateShortTermScore(rawScore);
  int migrateLongTermScore(int rawScore) => _migrateLongTermScore(rawScore);

  // ── Core logic (verbatim mechanical extraction) ───────────────────────────

  int _calculateTier(int score) {
    final absScore = score.abs();
    if (absScore < 5) return 0;
    if (absScore < 15) return score > 0 ? 1 : -1;
    if (absScore < 30) return score > 0 ? 2 : -2;
    if (absScore < 50) return score > 0 ? 3 : -3;
    if (absScore < 80) return score > 0 ? 4 : -4;
    if (absScore < 120) return score > 0 ? 5 : -5;
    if (absScore < 160) return score > 0 ? 6 : -6;
    if (absScore < 200) return score > 0 ? 7 : -7;
    if (absScore < 250) return score > 0 ? 8 : -8;
    if (absScore < 300) return score > 0 ? 9 : -9;
    return score > 0 ? 10 : -10;
  }

  /// Migration: scale old short-term scores (±150) to new range (±300)
  int _migrateShortTermScore(int rawScore) {
    if (rawScore.abs() <= 150) {
      return (rawScore * 2).clamp(-300, 300);
    }
    return rawScore;
  }

  /// Migration: scale old long-term scores (±150) to new range (±300)
  int _migrateLongTermScore(int rawScore) {
    if (rawScore.abs() <= 150) {
      return (rawScore * 2).clamp(-300, 300);
    }
    return rawScore;
  }

  // ── Reset / seed / load helpers (support "keep reset blocks in sync" in parent) ──

  void resetForFreshChat() {
    _affectionScore = 0;
    _relationshipTier = 0;
    _longTermScore = 0;
    _longTermTier = 0;
    _turnsSinceLongTermCheck = 0;
    _shortTermDeltasSummary = 0;
    _turnsSinceDecayCheck = 0;
    _trustLevel = 0;
    _activeFixation = '';
    _fixationLifespan = 0;
    _spatialStance = '';
    _pendingTrustRepair = false;
  }

  void seedFromV2OrExt({
    required int shortTermBond,
    required int longTermBond,
    required int trustLevel,
  }) {
    _affectionScore = _migrateShortTermScore(shortTermBond.clamp(-300, 300));
    _longTermScore = _migrateLongTermScore(longTermBond.clamp(-300, 300));
    _trustLevel = trustLevel.clamp(-100, 100);
    _relationshipTier = _calculateTier(_affectionScore);
    _longTermTier = _calculateTier(_longTermScore);
  }

  /// Card V2/Ext seed path: plain clamp (current ±300 scale authored by V2.5 cards
  /// and the creator UI). No legacy *2 migration. Tiers computed after. Used by the
  /// two fresh ext-seed sites in ChatService (setActiveCharacter 0-session path and
  /// startNewChat 1:1 ext branch). Group paths untouched (never used the doubling).
  /// See god comments for "card-seed bypass" + cross-refs.
  void seedFromCardV2OrExt({
    required int shortTermBond,
    required int longTermBond,
    required int trustLevel,
  }) {
    _affectionScore = shortTermBond.clamp(-300, 300);
    _longTermScore = longTermBond.clamp(-300, 300);
    _trustLevel = trustLevel.clamp(-100, 100);
    _relationshipTier = _calculateTier(_affectionScore);
    _longTermTier = _calculateTier(_longTermScore);
  }

  void loadScalars({
    required int affectionScore,
    required int longTermScore,
    required int trustLevel,
    String activeFixation = '',
    int fixationLifespan = 0,
    String spatialStance = '',
    bool trustRepairPending = false,
    int turnsSinceLongTermCheck = 0,
    int shortTermDeltasSummary = 0,
    int turnsSinceDecayCheck = 0,
  }) {
    _affectionScore = affectionScore;
    _longTermScore = longTermScore;
    _trustLevel = trustLevel;
    _activeFixation = activeFixation;
    _fixationLifespan = fixationLifespan;
    _spatialStance = spatialStance;
    _pendingTrustRepair = trustRepairPending;
    _turnsSinceLongTermCheck = turnsSinceLongTermCheck;
    _shortTermDeltasSummary = shortTermDeltasSummary;
    _turnsSinceDecayCheck = turnsSinceDecayCheck;

    _relationshipTier = _calculateTier(_affectionScore);
    _longTermTier = _calculateTier(_longTermScore);
  }

  void applyLegacyShortTermMigrationIfNeeded() {
    if (_affectionScore > 0 &&
        _affectionScore <= 15 &&
        _relationshipTier >= 3) {
      _affectionScore = _affectionScore * 10;
      if (_longTermScore == 0) {
        _longTermScore = _affectionScore;
        _longTermTier = _calculateTier(_longTermScore);
      }
      _relationshipTier = _calculateTier(_affectionScore);
      debugPrint(
        '[Realism] Legacy session migrated to REv2 scales (via RelationshipService).',
      );
    }
  }

  /// Load per-speaker relationship scalars (affection/trust/fixation/tiers/spatial)
  /// from the group's _groupRealism map into this service's 1:1-style scalars so
  /// eval/delta/injection paths can operate on them. Mirrors needs pattern.
  void loadRelationshipScalarsForSpeaker(String charId) {
    final aff = getGroupAffectionScore(charId);
    _affectionScore = aff;
    _longTermScore = getGroupLongTermScore(charId, defaultValue: aff);
    _trustLevel = getGroupTrustLevel(charId);
    _activeFixation = getGroupFixation(charId);
    _fixationLifespan = getGroupFixationLifespan(charId, defaultValue: 0);
    _spatialStance = getGroupSpatialStance(charId);

    final relT = getGroupRelationshipTier(charId, defaultValue: 0);
    _relationshipTier = relT != 0 ? relT : _calculateTier(_affectionScore);
    final ltT = getGroupLongTermTier(charId, defaultValue: 0);
    _longTermTier = ltT != 0 ? ltT : _calculateTier(_longTermScore);
  }

  /// Write current scalars back into the target group character's _groupRealism
  /// entry (for affection/long/trust/fixation/tiers/spatial). Does not touch needs
  /// or emotion (owned elsewhere).
  void saveRelationshipScalarsToGroup(String charId) {
    setGroupAffectionScore(charId, _affectionScore);
    setGroupLongTermScore(charId, _longTermScore);
    setGroupTrustLevel(charId, _trustLevel);

    // Persist fixation/spatial UNCONDITIONALLY (including clears) so the
    // per-character store is a faithful snapshot of the working registers.
    // Previously these were guarded behind non-empty checks, which meant a
    // cleared fixation/spatial never propagated through save/load — fine while
    // only group members used this path (fixation re-set each turn), but it would
    // silently break fixation-clearing once the always-loaded 1:1 host is unified
    // onto the same store. See relationship_service_test round-trip coverage.
    setGroupFixation(charId, _activeFixation);
    setGroupFixationLifespan(charId, _fixationLifespan);
    setGroupSpatialStance(charId, _spatialStance);

    setGroupRelationshipTier(charId, _relationshipTier);
    setGroupLongTermTier(charId, _longTermTier);
  }

  // ── Deltas, growth, decay, fixation (verbatim) ─────────────────────────────

  void applyScoreDelta(int delta) {
    _shortTermDeltasSummary += delta;
    _turnsSinceLongTermCheck++;

    if (_turnsSinceLongTermCheck >= 5) {
      _evalLongTermGrowth();
    }

    if (delta == 0) return;
    final oldScore = _affectionScore;
    final oldTier = _relationshipTier;

    _affectionScore = (_affectionScore + delta).clamp(-300, 300);
    _relationshipTier = _calculateTier(_affectionScore);

    if (_affectionScore != oldScore || _relationshipTier != oldTier) {
      debugPrint(
        '[Realism] Short-Term Bond: $oldScore \u2192 $_affectionScore, '
        'Tier: $oldTier \u2192 $_relationshipTier ($shortTermTierName)',
      );
      onNotify();
    }
  }

  void applyTrustDelta(int delta) {
    if (delta == 0) return;
    _trustLevel = (_trustLevel + delta).clamp(-100, 100);
    debugPrint(
      '[Realism:Relationship] Trust shifted by $delta -> $_trustLevel',
    );
    onNotify(); // notify on any trust shift (bond/long/short already do on change) so sidebar live-updates from realism eval results / chips
    // Arm the repair window on any severe single-turn drop
    if (delta <= -20) {
      _pendingTrustRepair = true;
      debugPrint('[Realism:Trust] Severe drop — repair window armed');
    }
  }

  void _evalLongTermGrowth() {
    final oldLTScore = _longTermScore;
    final oldLTTier = _longTermTier;

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
  }

  /// Short-term relationship decay (toward 0 by 1 every 10 turns) + hidden
  /// inter-char decay (when under cap). Extracted from _applyMoodDecay body.
  void applyShortTermDecay() {
    _turnsSinceDecayCheck++;
    if (_turnsSinceDecayCheck >= 10) {
      if (getIsGroupActive() && !getObserverMode()) {
        final id = getCurrentSpeakerIdForRealism();
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
        if (getShouldTrackInterCharacterRelationships()) {
          final rels = Map<String, int>.from(
            getInterCharacterRelationships(id),
          );
          if (rels.isNotEmpty) {
            bool relChanged = false;
            rels.forEach((otherId, value) {
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
      _turnsSinceDecayCheck = 0;
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

  // ── Inter-character (verbatim) ─────────────────────────────────────────────

  Map<String, int> getInterCharacterRelationships(String charId) {
    if (!getIsGroupRealismActive()) return const {};
    final raw = getGroupInterCharacterRelationships(charId);
    if (raw.isNotEmpty) {
      return raw.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    }
    return const {};
  }

  void updateInterCharacterRelationship(
    String fromCharId,
    String toCharId,
    int delta,
  ) {
    if (!getIsGroupActive()) return;

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

  void restoreFromMessageState(Map<dynamic, dynamic> state) {
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
    _activeFixation = (state['activeFixation'] as String?) ?? _activeFixation;
    _fixationLifespan =
        (state['fixationLifespan'] as int?) ?? _fixationLifespan;
    _spatialStance = (state['spatialStance'] as String?) ?? _spatialStance;
  }

  // Minimal surface for regen revert of trust (avoids re-arming the repair window
  // that applyTrustDelta does for forward deltas).
  void setTrustLevelForRevert(int v) {
    _trustLevel = v.clamp(-100, 100);
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

  /// Consume the one-shot repair window (called on next user turn after armed severe drop).
  void consumePendingTrustRepair() {
    _pendingTrustRepair = false;
  }

  Map<String, dynamic> buildRelationshipStateSnapshot() {
    return {
      'affectionScore': _affectionScore,
      'relationshipTier': _relationshipTier,
      'longTermScore': _longTermScore,
      'longTermTier': _longTermTier,
      'turnsSinceLongTermCheck': _turnsSinceLongTermCheck,
      'shortTermDeltasSummary': _shortTermDeltasSummary,
      'trustLevel': _trustLevel,
      'activeFixation': _activeFixation,
      'fixationLifespan': _fixationLifespan,
      'spatialStance': _spatialStance,
    };
  }
}
