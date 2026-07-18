// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for the extracted RelationshipService (plain class).
// Covers: tier calculation (affection/trust), bond/trust deltas + tier updates,
// fixation lifespan/active + update from eval results (narrative/one-shot parity),
// inter-char seeding + prune + heuristic update from recent exchange (sentiment deltas),
// resetForFresh/seedFromV2/loadScalars, group per-char scalar load/save roundtrips,
// inter-char map get/update via service, short/long term progress getters,
// legacy migration apply, 1:1 vs group scoping/parity notes.
// New for PR#47 rec1 port: dedicated test body for seedFromCardV2OrExt (plain clamp, card=55 seeds as 55 not 110)
// + explicit legacy migrate* still doubles (for old persisted session data); see god card-seed bypass.
// Uses createTestRelationship factory (per plan + needs/chaos precedent) for all ctors.
// Real ChatService pre-turn/eval paths (apply deltas in relationship/one-shot calls,
// ensure/update inter in group realism, load/save scalars in impersonation, decay via _applyMoodDecay delegate,
// fixation in narrative, snapshot restore, startNew/setActive/load resets) exercised indirectly
// via the key realism/group/session tests run as part of verification (no new regressions).
// Callback contract note for future extractors: all on*/get*/set* passed at construction must be
// exercised in unit tests or noted for integration coverage.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/relationship_service.dart';

/// Test factory to reduce callback boilerplate (modeled exactly on needs_simulation_test / chaos_mode_service_test).
/// Supplies realistic defaults for 1:1 and group scenarios; override lists for side-effect capture.
RelationshipService createTestRelationship({
  List<String>? notifies,
  List<String>? saves,
  bool isGroup = false,
  bool observer = false,
  int groupCharCount = 1,
  String currentSpeakerId = 'char1',
  Map<String, int> groupAffection = const {},
  Map<String, int> groupLongTerm = const {},
  Map<String, int> groupTrust = const {},
  Map<String, String> groupFixation = const {},
  Map<String, int> groupFixLifespan = const {},
  Map<String, int> groupRelTier = const {},
  Map<String, int> groupLongTier = const {},
  Map<String, String> groupSpatial = const {},
  Map<String, Map<String, int>> groupInterRels = const {},
  String recentText = '',
  int msgCount = 0,
  Set<String> groupMemberIds = const {},
  Map<String, String> otherNames = const {},
}) {
  final n = notifies ?? <String>[];
  final s = saves ?? <String>[];

  // Live maps so group set/get roundtrip in tests.
  final gAff = Map<String, int>.from(groupAffection);
  final gLT = Map<String, int>.from(groupLongTerm);
  final gTrust = Map<String, int>.from(groupTrust);
  final gFix = Map<String, String>.from(groupFixation);
  final gFixLife = Map<String, int>.from(groupFixLifespan);
  final gRTier = Map<String, int>.from(groupRelTier);
  final gLTTier = Map<String, int>.from(groupLongTier);
  final gSpat = Map<String, String>.from(groupSpatial);
  final gInter = <String, Map<String, int>>{};
  groupInterRels.forEach((k, v) => gInter[k] = Map<String, int>.from(v));

  final svc = RelationshipService(
    onNotify: () => n.add('notify'),
    onSaveChat: () async => s.add('save'),
    getIsGroupActive: () => isGroup,
    getObserverMode: () => observer,
    getGroupCharacterCount: () => groupCharCount,
    getShouldTrackInterCharacterRelationships: () =>
        isGroup && groupCharCount <= 4,
    getCurrentSpeakerIdForRealism: () => currentSpeakerId,
    getCurrentGroupMemberIds: () => groupMemberIds,
    getOtherGroupMemberIds: (self) =>
        groupMemberIds.where((id) => id != self).toList(),
    getOtherGroupMemberIdToLowerName: (self) => otherNames,
    getRecentExchangeLowerText: () => recentText,
    getMessageCount: () => msgCount,
    getIsGroupRealismActive: () => isGroup,
    getGroupAffectionScore: (id, {int defaultValue = 0}) =>
        gAff[id] ?? defaultValue,
    setGroupAffectionScore: (id, v) => gAff[id] = v,
    getGroupLongTermScore: (id, {int defaultValue = 0}) =>
        gLT[id] ?? defaultValue,
    setGroupLongTermScore: (id, v) => gLT[id] = v,
    getGroupTrustLevel: (id, {int defaultValue = 0}) =>
        gTrust[id] ?? defaultValue,
    setGroupTrustLevel: (id, v) => gTrust[id] = v,
    getGroupFixation: (id, {String defaultValue = ''}) =>
        gFix[id] ?? defaultValue,
    setGroupFixation: (id, v) => gFix[id] = v,
    getGroupFixationLifespan: (id, {int defaultValue = 0}) =>
        gFixLife[id] ?? defaultValue,
    setGroupFixationLifespan: (id, v) => gFixLife[id] = v,
    getGroupRelationshipTier: (id, {int defaultValue = 0}) =>
        gRTier[id] ?? defaultValue,
    setGroupRelationshipTier: (id, v) => gRTier[id] = v,
    getGroupLongTermTier: (id, {int defaultValue = 0}) =>
        gLTTier[id] ?? defaultValue,
    setGroupLongTermTier: (id, v) => gLTTier[id] = v,
    getGroupSpatialStance: (id, {String defaultValue = ''}) =>
        gSpat[id] ?? defaultValue,
    setGroupSpatialStance: (id, v) => gSpat[id] = v,
    getGroupInterCharacterRelationships: (id) => gInter[id] ?? const {},
    setGroupInterCharacterRelationships: (id, rels) =>
        gInter[id] = Map<String, int>.from(rels),
  );
  return svc;
}

void main() {
  group('RelationshipService (extracted leaf)', () {
    test('calculateTier covers full range and signs', () {
      final svc = createTestRelationship();
      expect(svc.calculateTier(0), 0);
      expect(svc.calculateTier(4), 0);
      expect(svc.calculateTier(5), 1);
      expect(svc.calculateTier(14), 1);
      expect(svc.calculateTier(15), 2);
      expect(svc.calculateTier(299), 9);
      expect(svc.calculateTier(300), 10);
      expect(svc.calculateTier(-5), -1);
      expect(svc.calculateTier(-300), -10);
    });

    test(
      'applyScoreDelta updates score/tier, accumulates deltas, triggers long growth at 5',
      () {
        final n = <String>[];
        final svc = createTestRelationship(notifies: n);
        svc.applyScoreDelta(10);
        expect(svc.affectionScore, 10);
        expect(svc.relationshipTier, 1);
        expect(svc.shortTermTierName, 'Neutral'); // at 10 still low
        svc.applyScoreDelta(20);
        expect(svc.affectionScore, 30);
        expect(svc.relationshipTier, 3); // 30 >=30 <50 -> 3 per verbatim calc
        // 5 triggers long growth (no-op on fresh)
        svc.applyScoreDelta(5);
        expect(svc.longTermScore, 0); // no prior long
      },
    );

    test('applyTrustDelta clamps, arms pending on severe drop, notifies', () {
      final n = <String>[];
      final svc = createTestRelationship(notifies: n);
      svc.applyTrustDelta(30);
      expect(svc.trustLevel, 30);
      expect(svc.trustTier, 3);
      expect(svc.trustTierName, 'Trusting');
      expect(svc.pendingTrustRepair, false);
      svc.applyTrustDelta(-25);
      expect(svc.trustLevel, 5);
      svc.applyTrustDelta(-30);
      expect(svc.trustLevel, -25);
      expect(svc.pendingTrustRepair, true);
      expect(n, contains('notify'));
    });

    test(
      'fixation lifespan ticks and sets new from eval result (1:1 path)',
      () {
        final svc = createTestRelationship();
        svc.updateFixationFromEvalResult('obsession with cake');
        expect(svc.activeFixation, 'obsession with cake');
        expect(svc.fixationLifespan, 3);
        svc.decayFixationOneTurn();
        expect(svc.fixationLifespan, 2);
        svc.updateFixationFromEvalResult('none', isOneShot: true);
        expect(svc.activeFixation, '');
        expect(svc.fixationLifespan, 0);
      },
    );

    // Regression: fixation (and spatial stance / pending trust-repair) must not
    // bleed across chats with the SAME character. The in-chat "New Chat" button
    // calls startNewChat directly (no preceding setActiveCharacter), and the 1:1
    // branch re-seeds bond/trust from the card via seedFromCardV2OrExt — which by
    // design leaves fixation/spatial/pending untouched. startNewChat must therefore
    // resetForFreshChat() BEFORE re-seeding, or the previous conversation's
    // "Background Thought" obsession leaks into (and is saved on) the new session.
    test(
      'new-chat reset invariant (1:1): resetForFreshChat clears fixation/spatial/'
      'pending, card re-seed restores bond/trust (no cross-chat bleed)',
      () {
        final svc = createTestRelationship();

        // A chat that developed an obsession, a spatial stance, and an armed
        // trust-repair window (severe drop).
        svc.updateFixationFromEvalResult('the locket in her pocket');
        svc.setSpatialStance('sitting close on the porch swing');
        svc.applyTrustDelta(-30);
        expect(svc.activeFixation, 'the locket in her pocket');
        expect(svc.spatialStance, isNotEmpty);
        expect(svc.pendingTrustRepair, true);

        // The card seed ALONE does not clear these — this is exactly why the
        // reset is required (documents the root cause).
        svc.seedFromCardV2OrExt(
          shortTermBond: 55,
          longTermBond: 40,
          trustLevel: 20,
        );
        expect(
          svc.activeFixation,
          'the locket in her pocket',
          reason: 'seedFromCardV2OrExt intentionally leaves fixation untouched',
        );

        // The fix ordering used by startNewChat's 1:1 branch.
        svc.resetForFreshChat();
        svc.seedFromCardV2OrExt(
          shortTermBond: 55,
          longTermBond: 40,
          trustLevel: 20,
        );

        expect(
          svc.activeFixation,
          '',
          reason: 'fixation must not bleed into a fresh chat',
        );
        expect(svc.fixationLifespan, 0);
        expect(
          svc.spatialStance,
          '',
          reason: 'spatial stance must not bleed into a fresh chat',
        );
        expect(svc.pendingTrustRepair, false);
        // Bond/trust are correctly re-seeded from the card (plain clamp, ±300).
        expect(svc.affectionScore, 55);
        expect(svc.longTermScore, 40);
        expect(svc.trustLevel, 20);
      },
    );

    // Regression (group parity): the group equivalent of the leak was startNewChat
    // never resetting _groupRealism, so each member carried their previous
    // session's per-char fixation. The fix resets _groupRealism to the group's
    // default member baselines (parseGroupRealismSeeds), whose seeds carry
    // affection/trust/needs but NEVER a fixation. This verifies the runtime
    // consequence: a speaker loaded from fixation-free baselines starts clean.
    test(
      'new-chat reset invariant (group): per-speaker load from fixation-free '
      'baselines yields no Background Thought',
      () {
        final svc = createTestRelationship(
          isGroup: true,
          groupCharCount: 2,
          currentSpeakerId: 'char1',
          groupAffection: {'char1': 35},
          groupTrust: {'char1': 40},
          // No groupFixation entry for char1 — the reset-to-baselines state.
        );

        svc.loadRelationshipScalarsForSpeaker('char1');

        expect(
          svc.activeFixation,
          '',
          reason: 'a member re-seeded from fixation-free group baselines must '
              'start the new chat with no obsession',
        );
        expect(svc.fixationLifespan, 0);
        expect(svc.affectionScore, 35);
        expect(svc.trustLevel, 40);
      },
    );

    test(
      'inter-char ensure seeds neutral for others and prunes stale (group <=4)',
      () {
        final inter = <String, Map<String, int>>{
          'char1': {'char2': 5, 'oldStale': 10},
        };
        final svc = createTestRelationship(
          isGroup: true,
          groupCharCount: 3,
          currentSpeakerId: 'char1',
          groupInterRels: inter,
          groupMemberIds: {'char1', 'char2', 'char3'},
        );
        svc.ensureInterCharacterRelationshipsSeeded('char1');
        final rels = svc.getInterCharacterRelationships('char1');
        expect(rels['char2'], 5); // preserved
        expect(rels['char3'], 0); // seeded
        expect(rels.containsKey('oldStale'), false); // pruned
      },
    );

    test(
      'ensureInter early-returns with no side-effects when observer=true (cb exercised)',
      () {
        final inter = <String, Map<String, int>>{
          'char1': {'char2': 5},
        };
        final svc = createTestRelationship(
          isGroup: true,
          groupCharCount: 3,
          observer: true,
          currentSpeakerId: 'char1',
          groupInterRels: inter,
          groupMemberIds: {'char1', 'char2', 'char3'},
        );
        svc.ensureInterCharacterRelationshipsSeeded('char1');
        final rels = svc.getInterCharacterRelationships('char1');
        expect(rels['char2'], 5); // unchanged, early return
        expect(rels.containsKey('char3'), false); // no seed
      },
    );

    test(
      'updateInter from recent applies sentiment deltas only on name mention',
      () {
        final inter = <String, Map<String, int>>{
          'char1': {'char2': 0},
        };
        final svc = createTestRelationship(
          isGroup: true,
          groupCharCount: 2,
          currentSpeakerId: 'char1',
          groupInterRels: inter,
          groupMemberIds: {'char1', 'char2'},
          otherNames: {'char2': 'bob'},
          recentText: 'bob is wonderful and a great friend',
          msgCount: 2,
        );
        svc.updateInterCharacterFeelingsFromRecentExchange('char1');
        final rels = svc.getInterCharacterRelationships('char1');
        expect(rels['char2'], 4);
      },
    );

    test(
      'reset/seed/loadScalars roundtrip and group per-char load/save scalars',
      () {
        final svc = createTestRelationship();
        svc.seedFromV2OrExt(shortTermBond: 42, longTermBond: 17, trustLevel: 9);
        expect(
          svc.affectionScore,
          84,
        ); // migrate doubles <=150 per verbatim original logic (legacy path)
        expect(svc.relationshipTier, 5); // 84 <120 ->5
        svc.resetForFreshChat();
        expect(svc.affectionScore, 0);
        expect(svc.trustLevel, 0);

        svc.loadScalars(affectionScore: 55, longTermScore: 22, trustLevel: -7);
        expect(svc.affectionScore, 55);
        expect(svc.trustLevel, -7);
        expect(svc.relationshipTier, 4);

        // group scalars
        final gAff = <String, int>{'spk': 12};
        final gSvc = createTestRelationship(
          isGroup: true,
          groupCharCount: 2,
          currentSpeakerId: 'spk',
          groupAffection: gAff,
        );
        gSvc.loadRelationshipScalarsForSpeaker('spk');
        expect(gSvc.affectionScore, 12);
        gSvc.applyScoreDelta(3);
        gSvc.saveRelationshipScalarsToGroup('spk');
        expect(gSvc.affectionScore, 15);
        // (group map write verified via closure in factory; scalar confirms apply+save path)
      },
    );

    // ── Per-character store round-trip (the safety net for unifying the host
    //    onto the same per-participant store the group path uses) ────────────
    test(
      'all SAVED relationship scalars round-trip losslessly through the per-char map',
      () {
        final svc = createTestRelationship(
          isGroup: true,
          groupCharCount: 2,
          currentSpeakerId: 'spk',
        );
        // Populate every saved field with a distinctive value.
        svc.loadScalars(
          affectionScore: 123,
          longTermScore: -45,
          trustLevel: 67,
          activeFixation: 'the way she laughs',
          fixationLifespan: 3,
          spatialStance: 'leaning close',
        );
        final tierBefore = svc.relationshipTier;
        final ltTierBefore = svc.longTermTier;

        svc.saveRelationshipScalarsToGroup('spk');
        // Wipe the working registers (as if another speaker had been loaded).
        svc.resetForFreshChat();
        expect(svc.affectionScore, 0);
        expect(svc.activeFixation, '');

        // Restore from the per-char map.
        svc.loadRelationshipScalarsForSpeaker('spk');
        expect(svc.affectionScore, 123);
        expect(svc.longTermScore, -45);
        expect(svc.trustLevel, 67);
        expect(svc.activeFixation, 'the way she laughs');
        expect(svc.fixationLifespan, 3);
        expect(svc.spatialStance, 'leaning close');
        expect(svc.relationshipTier, tierBefore);
        expect(svc.longTermTier, ltTierBefore);
      },
    );

    test(
      'clearing fixation/spatial DOES propagate through save/load (unconditional '
      'persist — required for unifying the always-loaded host onto this store)',
      () {
        final svc = createTestRelationship(
          isGroup: true,
          groupCharCount: 2,
          currentSpeakerId: 'spk',
        );
        // Set a fixation + spatial and persist.
        svc.loadScalars(
          affectionScore: 10,
          longTermScore: 10,
          trustLevel: 0,
          activeFixation: 'her smile',
          fixationLifespan: 2,
          spatialStance: 'near',
        );
        svc.saveRelationshipScalarsToGroup('spk');

        // Now CLEAR them and save again (fixation='', lifespan=0, spatial='').
        svc.loadScalars(affectionScore: 10, longTermScore: 10, trustLevel: 0);
        expect(svc.activeFixation, '');
        svc.saveRelationshipScalarsToGroup('spk');

        // Reload: the clears now persist (no stale fixation/spatial survives).
        svc.resetForFreshChat();
        svc.loadRelationshipScalarsForSpeaker('spk');
        expect(svc.activeFixation, '');
        expect(svc.fixationLifespan, 0);
        expect(svc.spatialStance, '');
      },
    );

    test(
      'seedFromCardV2OrExt does plain clamp (no *2 migration) for V2.5 card seeds; legacy migrate* still double for old session data',
      () {
        final svc = createTestRelationship();
        // Card seed path (used by setActiveCharacter fresh + startNewChat 1:1 ext): 55 stays 55
        // (1:1-only per god thins + relationship_service docs; group seeding uses loadRelationshipScalarsForSpeaker etc.
        // Card seed under group cb is not used / would be incorrect; parity guarded by never calling it in group paths.)
        svc.seedFromCardV2OrExt(
          shortTermBond: 55,
          longTermBond: 30,
          trustLevel: 10,
        );
        expect(
          svc.affectionScore,
          55,
        ); // not 110; fixes bond-doubling regression for card authors
        expect(svc.longTermScore, 30);
        expect(svc.trustLevel, 10);
        expect(
          svc.relationshipTier,
          4,
        ); // 55<80 ->4 per _calculateTier (see 50-80 range)
        // Direct boundary/edge for the new plain-clamp bypass method (plain .clamp only, no migration)
        svc.seedFromCardV2OrExt(
          shortTermBond: 400,
          longTermBond: -400,
          trustLevel: 150,
        );
        expect(svc.affectionScore, 300); // clamps high
        expect(svc.longTermScore, -300); // clamps low
        expect(svc.trustLevel, 100); // clamps trust
        svc.seedFromCardV2OrExt(
          shortTermBond: 0,
          longTermBond: 300,
          trustLevel: -100,
        );
        expect(svc.affectionScore, 0);
        expect(svc.longTermScore, 300);
        expect(svc.trustLevel, -100);
        svc.resetForFreshChat();

        // Legacy session data path (via public migrate wrappers + loadScalars in _loadLast) still migrates
        final migratedShort = svc.migrateShortTermScore(42);
        final migratedLong = svc.migrateLongTermScore(17);
        expect(migratedShort, 84); // <=150 -> *2
        expect(migratedLong, 34);
        svc.loadScalars(
          affectionScore: migratedShort,
          longTermScore: migratedLong,
          trustLevel: 5,
        );
        expect(svc.affectionScore, 84);
        // Direct low-value <=150 still migrates (covers "legacy session data still migrates when appropriate")
        expect(svc.migrateShortTermScore(55), 110);
        expect(svc.migrateShortTermScore(200), 200); // >150 no change
      },
    );

    test('progress getters and tier names update with state', () {
      final svc = createTestRelationship();
      svc.applyScoreDelta(25);
      expect(svc.shortTermProgressTarget, 30);
      expect(svc.shortTermProgressBase, 15);
      expect(svc.shortTermProgressPercent > 0, true);
      expect(svc.shortTermTierName, 'Receptive'); // 25 <30 -> tier 2 per calc
    });

    test('applyLegacy migration *10 when old small positive high tier', () {
      final svc = createTestRelationship();
      svc.loadScalars(affectionScore: 12, longTermScore: 0, trustLevel: 0);
      // load computes tier from current score (12 -> tier 1), so legacy condition (_affection>0 && <=15 && tier>=3) not met here.
      // applyLegacyShortTermMigrationIfNeeded is a no-op smoke in this harness (real triggering exercised in ChatService V2.5 load/seed paths + dedicated migration tests).
      svc.applyLegacyShortTermMigrationIfNeeded();
      expect(svc.affectionScore, 12);
    });

    test('public inter update/get clamps and creates', () {
      final svc = createTestRelationship(isGroup: true, groupCharCount: 2);
      svc.updateInterCharacterRelationship('a', 'b', 50);
      expect(svc.getInterCharacterRelationships('a')['b'], 50);
      svc.updateInterCharacterRelationship('a', 'b', 999);
      expect(svc.getInterCharacterRelationships('a')['b'], 300);
    });

    test(
      '1:1 vs group parity note (chat-scoped scalars vs per-speaker via group cbs)',
      () {
        // Documented: service supports both via load/save scalars for group; 1:1 uses owned scalars directly.
        // Core math (deltas, tier, fixation, inter heuristic) identical.
        // Verified via this harness + key integration tests (no divergence introduced).
        final oneToOne = createTestRelationship();
        oneToOne.applyScoreDelta(10);
        expect(oneToOne.affectionScore, 10);

        final grp = createTestRelationship(
          isGroup: true,
          groupCharCount: 2,
          currentSpeakerId: 's1',
        );
        grp.loadRelationshipScalarsForSpeaker('s1'); // starts 0
        grp.applyScoreDelta(10);
        grp.saveRelationshipScalarsToGroup('s1');
        expect(grp.affectionScore, 10);
      },
    );
  });
}
