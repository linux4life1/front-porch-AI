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

import 'relationship_service/relationship_service.dart';
import 'relationship_tiers.dart';

export 'relationship_service/relationship_rewind.dart'
    show rejectedTurnRewindPatch;

/// Bond applies between long-term growth checks. Going forward only —
/// stored session counters and [RelationshipService.longTermScore] are
/// never recomputed from chat history when this number changes.
const int kLongTermCheckEvery = 3;

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
/// ChatService forwards the public surface (affectionScore, relationshipTier,
/// trustLevel, trustTier, activeFixation, fixationLifespan, short/longTerm
/// scores and tiers, tier names, inter-char methods) for callers and tests.
///
/// Reset helpers (resetForFreshChat, seedFromCardV2OrExt, loadScalars,
/// loadRelationshipScalarsForSpeaker, saveRelationshipScalarsToGroup) support
/// the documented "keep reset blocks in sync" sites in parent without adding
/// private helpers to the god file.
///
/// seedFromCardV2OrExt does *plain clamp only* for fresh V2.5 card ext seeds
/// on new 1:1 chats (card authors use the current ±300 scale), and loadScalars
/// takes persisted session values raw. The legacy ±150→×2 era migration
/// (migrate*Score wrappers, seedFromV2OrExt, applyLegacyShortTermMigration-
/// IfNeeded) was DELETED 2026-07-27: it inferred "old era" from |score| ≤ 150,
/// which every current chat passes through on its way up, so each library
/// open→save cycle re-doubled live bonds (40→80→160) until they crossed 150 —
/// while groups and the history-picker load path never migrated at all
/// (parity break). Do not reintroduce an era heuristic keyed on score
/// magnitude; a real era marker (schema version / column) is the only safe
/// trigger for any future scale change.
///
/// 0 new private methods added to ChatService as part of this step (thins + delegations only;
/// deletions of moved code are mandatory part of the task).
///
/// This library was split 2026-08 (god-file elimination campaign) into this shell
/// plus one pure leaf (`relationship_tiers.dart`, which holds the tier/percent
/// scale statics this class still exposes via the six one-line delegating
/// statics below for source compatibility). Its former `part` files are now
/// real collaborators under `relationship_service/`: [RelationshipScalars]
/// (the owned registers + pure reset/seed/load/setters),
/// [RelationshipDynamics] (deltas, growth, decay), [RelationshipGroupSync]
/// (per-speaker group load/save) and [RelationshipRewinder] (capture/restore +
/// inter-character feelings). This class forwards to them one line each.
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
  final bool? Function(String charId)? getGroupWithUser;
  final void Function(String charId, bool? value)? setGroupWithUser;

  // Inter-character hidden feelings map (per speaker, only when group <=4).
  final Map<String, int> Function(String charId)
  getGroupInterCharacterRelationships;
  final void Function(String charId, Map<String, int> rels)
  setGroupInterCharacterRelationships;

  // Generic per-speaker cadence-counter access (turnsSinceLongTermCheck /
  // shortTermDeltasSummary / turnsSinceDecayCheck ride the same _groupRealism
  // entry as the scalars above). Optional: when unwired (tests), the legacy
  // shared working registers are used — in production ChatService wires these
  // so each group member grows/decays on their OWN turn count instead of the
  // whole group's shared cadence (parity with 1:1).
  final int Function(String charId, String key, {int defaultValue})?
  getGroupCounter;
  final void Function(String charId, String key, int value)? setGroupCounter;

  /// Living Time §7 v1.5 / v1.5.1: fired when short-term bond, long-term bond,
  /// or trust *tier* changes via a forward apply. Null in tests that don't
  /// care. ChatService plants a journal milestone card. Never fires on
  /// load/seed/snapshot restore or when [applyScoreDelta] /
  /// [applyTrustDelta] run with recordMilestone: false (regen revert).
  final void Function(TierCrossing crossing)? onTierCrossing;

  // Owned simulation state (moved verbatim from ChatService) and the
  // collaborators that mutate it.
  final RelationshipScalars _s = RelationshipScalars();
  late final RelationshipDynamics _dynamics = RelationshipDynamics(this, _s);
  late final RelationshipGroupSync _groupSync = RelationshipGroupSync(this, _s);
  late final RelationshipRewinder _rewinder = RelationshipRewinder(this, _s);

  // Armed on each severe trust drop (≥ -20 delta). Consumed on the very next user
  // message, then resets so future drops each get one shot.
  bool get pendingTrustRepair => _s.pendingTrustRepair;
  set pendingTrustRepair(bool v) => _s.pendingTrustRepair = v;

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
    this.getGroupCounter,
    this.setGroupCounter,
    required this.getGroupSpatialStance,
    required this.setGroupSpatialStance,
    this.getGroupWithUser,
    this.setGroupWithUser,
    required this.getGroupInterCharacterRelationships,
    required this.setGroupInterCharacterRelationships,
    this.onTierCrossing,
  });

  // ── Public surface (ChatService forwarders + direct test/UI callers) ──────

  int get affectionScore => _s.affectionScore;
  int get relationshipTier => _s.relationshipTier;
  int get longTermScore => _s.longTermScore;
  int get longTermTier => _s.longTermTier;
  int get trustLevel => _s.trustLevel;
  int get trustTier => RelationshipTiers.bondTierFor(_s.trustLevel);

  String get activeFixation => _s.activeFixation;
  int get fixationLifespan => _s.fixationLifespan;
  String get spatialStance => _s.spatialStance;
  bool? get withUser => _s.withUser;

  // Counters for snapshot/restore parity (used by capture in parent).
  int get turnsSinceLongTermCheck => _s.turnsSinceLongTermCheck;
  int get shortTermDeltasSummary => _s.shortTermDeltasSummary;

  // Progress helpers for relationship bars (UI + tests). Delegate to the pure
  // static scale helpers on [RelationshipTiers] (moved there in the 2026-08
  // split) so the band math is one source of truth, shared with read-only
  // per-member consumers (the web group stats panel).
  int get shortTermProgressTarget =>
      RelationshipTiers.bondScaleTarget(_s.affectionScore.abs());
  int get shortTermProgressBase =>
      RelationshipTiers.bondScaleBase(_s.affectionScore.abs());
  double get shortTermProgressPercent => bondScalePercent(_s.affectionScore);

  int get longTermProgressTarget =>
      RelationshipTiers.bondScaleTarget(_s.longTermScore.abs());
  double get longTermProgressPercent => bondScalePercent(_s.longTermScore);

  int get trustProgressTarget =>
      RelationshipTiers.trustScaleTarget(_s.trustLevel.abs());
  double get trustProgressPercent => trustScalePercent(_s.trustLevel);

  /// Human-readable tier name for the current relationship level.
  /// Calculate tier for 21-tier system (-10 to +10) for short/long-term bonds
  /// with new range ±300.
  String get shortTermTierName => bondTierLabel(_s.relationshipTier);

  String get longTermTierName => longTermTierLabel(_s.longTermTier);

  String get trustTierName => trustTierLabel(trustTier);

  // ── Delegating statics — bodies now live in [RelationshipTiers] (2026-08
  // split); kept here as one-liners so `RelationshipService.bondTierFor(...)`
  // etc. keep compiling for every existing call site (group_member_card.dart,
  // relationship_clamp_and_speaker_roundtrip_test.dart) with zero edits there. ──

  /// See [RelationshipTiers.bondScalePercent].
  static double bondScalePercent(int score) =>
      RelationshipTiers.bondScalePercent(score);

  /// See [RelationshipTiers.trustScalePercent].
  static double trustScalePercent(int level) =>
      RelationshipTiers.trustScalePercent(level);

  /// See [RelationshipTiers.bondTierLabel].
  static String bondTierLabel(int tier) =>
      RelationshipTiers.bondTierLabel(tier);

  /// See [RelationshipTiers.longTermTierLabel].
  static String longTermTierLabel(int tier) =>
      RelationshipTiers.longTermTierLabel(tier);

  /// See [RelationshipTiers.trustTierLabel].
  static String trustTierLabel(int tier) =>
      RelationshipTiers.trustTierLabel(tier);

  /// See [RelationshipTiers.bondTierFor].
  static int bondTierFor(int score) => RelationshipTiers.bondTierFor(score);

  /// Public for any load-site default computation that needs it (e.g. group scalar
  /// fallbacks). Internal logic always prefers provided group tier or computes.
  int calculateTier(int score) => RelationshipTiers.bondTierFor(score);

  // Per-score read helpers for consumers that need a tier name / bar percent for
  // an arbitrary score without mutating live state (e.g. the web per-group-member
  // stats panel). Compose the pure label/scale statics — single source of truth.
  String bondTierNameForScore(int score) => bondTierLabel(calculateTier(score));
  String longTermTierNameForScore(int score) =>
      longTermTierLabel(calculateTier(score));
  String trustTierNameForLevel(int level) =>
      trustTierLabel(calculateTier(level));
  double bondPercentForScore(int score) => bondScalePercent(score);
  double trustPercentForLevel(int level) => trustScalePercent(level);

  // ── Cadence scoping shared by [RelationshipDynamics] (decay) and
  // [RelationshipRewinder] (capture). ─────────────────────────────────────

  /// True when decay cadence runs on the group speaker's own counter.
  bool get perSpeakerDecay =>
      getIsGroupActive() &&
      !getObserverMode() &&
      getGroupCounter != null &&
      setGroupCounter != null;

  /// The member whose cadence/feelings a turn-path decay or capture targets.
  String get decaySpeakerId => getCurrentSpeakerIdForRealism();

  /// Public inter-character read API. Called from the dynamics part
  /// ([applyShortTermDecay]) and the rewind part (capture + the seeding/
  /// heuristic/update methods) — see the note above.
  Map<String, int> getInterCharacterRelationships(String charId) {
    if (!getIsGroupRealismActive()) return const {};
    final raw = getGroupInterCharacterRelationships(charId);
    if (raw.isNotEmpty) {
      return raw.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    }
    return const {};
  }

  /// Canonical scalar-restore entry (realism_state load, chip revert, tests).
  void loadScalars({
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
  }) => _s.load(
    affectionScore: affectionScore,
    longTermScore: longTermScore,
    trustLevel: trustLevel,
    activeFixation: activeFixation,
    fixationLifespan: fixationLifespan,
    spatialStance: spatialStance,
    withUser: withUser,
    trustRepairPending: trustRepairPending,
    turnsSinceLongTermCheck: turnsSinceLongTermCheck,
    shortTermDeltasSummary: shortTermDeltasSummary,
    turnsSinceDecayCheck: turnsSinceDecayCheck,
  );

  // ── Reset / seed / group load-save ([RelationshipScalars],
  // [RelationshipGroupSync]) ─────────────────────────────────────────────

  void resetForFreshChat() => _s.reset();

  /// See [RelationshipScalars.seedFromCard].
  void seedFromCardV2OrExt({
    required int shortTermBond,
    required int longTermBond,
    required int trustLevel,
  }) => _s.seedFromCard(
    shortTermBond: shortTermBond,
    longTermBond: longTermBond,
    trustLevel: trustLevel,
  );

  /// See [RelationshipGroupSync.loadRelationshipScalarsForSpeaker].
  void loadRelationshipScalarsForSpeaker(String charId) =>
      _groupSync.loadRelationshipScalarsForSpeaker(charId);

  /// See [RelationshipGroupSync.saveRelationshipScalarsToGroup].
  void saveRelationshipScalarsToGroup(String charId) =>
      _groupSync.saveRelationshipScalarsToGroup(charId);

  // ── Deltas, growth, decay ([RelationshipDynamics]) ────────────────────────

  /// See [RelationshipDynamics.applyScoreDelta].
  void applyScoreDelta(int delta, {bool recordMilestone = true}) =>
      _dynamics.applyScoreDelta(delta, recordMilestone: recordMilestone);

  /// See [RelationshipDynamics.applyTrustDelta].
  void applyTrustDelta(int delta, {bool recordMilestone = true}) =>
      _dynamics.applyTrustDelta(delta, recordMilestone: recordMilestone);

  /// See [RelationshipDynamics.applyShortTermDecay].
  void applyShortTermDecay() => _dynamics.applyShortTermDecay();

  // ── Fixation / spatial / with-user ([RelationshipScalars]) ────────────────

  void decayFixationOneTurn() => _s.decayFixationOneTurn();

  void updateFixationFromEvalResult(
    String rawTopic, {
    bool isOneShot = false,
  }) => _s.updateFixationFromEvalResult(rawTopic, isOneShot: isOneShot);

  void sanitizeFixationIfTooLong() => _s.sanitizeFixationIfTooLong();

  void setSpatialStance(String v) => _s.setSpatialStance(v);

  void applyWithUserVerdict(bool? v) => _s.applyWithUserVerdict(v);

  /// Restore / reset path — null is allowed (unknown).
  void setWithUser(bool? v) => _s.withUser = v;

  /// Consume the one-shot repair window (called on next user turn after armed severe drop).
  void consumePendingTrustRepair() => _s.pendingTrustRepair = false;

  void setTrustLevelForRevert(int v) => _s.setTrustLevelForRevert(v);

  // ── Capture / restore + inter-character ([RelationshipRewinder]) ──────────

  /// See [RelationshipRewinder.captureCadenceAndFeelings].
  Map<String, dynamic> captureCadenceAndFeelings() =>
      _rewinder.captureCadenceAndFeelings();

  void updateInterCharacterRelationship(
    String fromCharId,
    String toCharId,
    int delta,
  ) => _rewinder.updateInterCharacterRelationship(fromCharId, toCharId, delta);

  void ensureInterCharacterRelationshipsSeeded(String charId) =>
      _rewinder.ensureInterCharacterRelationshipsSeeded(charId);

  void updateInterCharacterFeelingsFromRecentExchange(String speakerId) =>
      _rewinder.updateInterCharacterFeelingsFromRecentExchange(speakerId);

  /// See [RelationshipRewinder.restoreFromMessageState].
  void restoreFromMessageState(
    Map<dynamic, dynamic> state, {
    String? groupSpeakerId,
  }) =>
      _rewinder.restoreFromMessageState(state, groupSpeakerId: groupSpeakerId);
}
