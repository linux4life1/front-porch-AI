// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// THE PARITY GATE for the 1:1↔group unification.
//
// Background: today a 1:1 host keeps realism/needs in the working-register
// services directly, while group members are swapped in/out of those same
// services via the per-character store (`_groupRealism`) using the load→eval→save
// "dance" (chat_service.dart:_loadGroupRealismIntoScalars /
// _saveScalarsIntoGroupRealism). The unification makes the host just "the
// participant that is always loaded", so BOTH modes run the same dance over the
// same store.
//
// This test encodes the parity guarantee that makes that safe: a participant
// evolves IDENTICALLY whether it is the sole participant (1:1) or one member
// among others (group). It composes the REAL leaf services
// (RelationshipService, NsfwService, NeedsSimulation) over a single shared
// `_groupRealism`-shaped store and exercises the real delta math through the
// real dance. If the collapse ever lets another participant's turn contaminate a
// participant, or the dance stops being lossless, this fails.
//
// This is the test that REPLACES the "1:1 must stay in parity with groups"
// review rule: parity is now proven, not asserted by hand.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/needs_impact.dart';
import 'package:front_porch_ai/services/chat/needs_simulation.dart';
import 'package:front_porch_ai/services/chat/nsfw_service.dart';
import 'package:front_porch_ai/services/chat/relationship_service.dart';

void main() {
  group('Realism/Needs 1:1↔group parity (store + dance)', () {
    // One shared per-participant store, exactly like `_groupRealism`
    // (Map<charId, Map<key, dynamic>>).
    late Map<String, Map<String, dynamic>> store;
    late RelationshipService rel;
    late NsfwService nsfw;
    late NeedsSimulation needs;
    late String currentSpeaker;

    Map<String, dynamic> e(String id) => store.putIfAbsent(id, () => {});
    int gi(String id, String key, int dv) =>
        (e(id)[key] as num?)?.toInt() ?? dv;

    setUp(() {
      store = {};
      currentSpeaker = 'alice';

      rel = RelationshipService(
        onNotify: () {},
        onSaveChat: () async {},
        getIsGroupActive: () => true,
        getObserverMode: () => false,
        getGroupCharacterCount: () => store.length,
        getShouldTrackInterCharacterRelationships: () => false,
        getCurrentSpeakerIdForRealism: () => currentSpeaker,
        getCurrentGroupMemberIds: () => store.keys.toSet(),
        getOtherGroupMemberIds: (self) =>
            store.keys.where((id) => id != self).toList(),
        getOtherGroupMemberIdToLowerName: (self) => const {},
        getRecentExchangeLowerText: () => '',
        getMessageCount: () => 0,
        getIsGroupRealismActive: () => true,
        getGroupAffectionScore: (id, {int defaultValue = 0}) =>
            gi(id, 'affection', defaultValue),
        setGroupAffectionScore: (id, v) => e(id)['affection'] = v,
        getGroupLongTermScore: (id, {int defaultValue = 0}) =>
            gi(id, 'longTermScore', defaultValue),
        setGroupLongTermScore: (id, v) => e(id)['longTermScore'] = v,
        getGroupTrustLevel: (id, {int defaultValue = 0}) =>
            gi(id, 'trust', defaultValue),
        setGroupTrustLevel: (id, v) => e(id)['trust'] = v,
        getGroupFixation: (id, {String defaultValue = ''}) =>
            (e(id)['fixation'] as String?) ?? defaultValue,
        setGroupFixation: (id, v) => e(id)['fixation'] = v,
        getGroupFixationLifespan: (id, {int defaultValue = 0}) =>
            gi(id, 'fixationLifespan', defaultValue),
        setGroupFixationLifespan: (id, v) => e(id)['fixationLifespan'] = v,
        getGroupRelationshipTier: (id, {int defaultValue = 0}) =>
            gi(id, 'relationshipTier', defaultValue),
        setGroupRelationshipTier: (id, v) => e(id)['relationshipTier'] = v,
        getGroupLongTermTier: (id, {int defaultValue = 0}) =>
            gi(id, 'longTermTier', defaultValue),
        setGroupLongTermTier: (id, v) => e(id)['longTermTier'] = v,
        getGroupSpatialStance: (id, {String defaultValue = ''}) =>
            (e(id)['spatialStance'] as String?) ?? defaultValue,
        setGroupSpatialStance: (id, v) => e(id)['spatialStance'] = v,
        getGroupInterCharacterRelationships: (id) =>
            (e(id)['relationships'] as Map?)?.cast<String, int>() ?? const {},
        setGroupInterCharacterRelationships: (id, rels) =>
            e(id)['relationships'] = Map<String, int>.from(rels),
      );

      nsfw = NsfwService(
        getGroupInt: (id, key) => gi(id, key, 0),
        getGroupValue: (id, key) => e(id)[key],
        setGroupValue: (id, key, v) => e(id)[key] = v,
      );

      needs = NeedsSimulation(
        onNotify: () {},
        onSaveChat: () async {},
        getTimeOfDay: () => 'morning',
        getRealismEnabled: () => true,
        getObserverMode: () => false,
        getCurrentSpeakerIdForRealism: () => currentSpeaker,
        getIsGroupNonObserverMode: () => true,
        getGroupNeeds: (id) =>
            (e(id)['needs'] as Map?)?.cast<String, int>() ?? const {},
        setGroupNeeds: (id, nn) => e(id)['needs'] = Map<String, int>.from(nn),
        getEnjoysLowHygiene: () => false,
        getNeedsSimEnabled: () => true,
      );
    });

    // The dance: swap a participant's state in/out of the working registers.
    void load(String id) {
      currentSpeaker = id;
      rel.loadRelationshipScalarsForSpeaker(id);
      nsfw.loadNsfwScalarsForSpeaker(id);
      final n = (e(id)['needs'] as Map?)?.cast<String, int>() ?? const {};
      if (n.isNotEmpty) {
        needs.restoreFromSnapshot({'vector': n});
      } else {
        needs.initializeFresh();
      }
    }

    void save(String id) {
      rel.saveRelationshipScalarsToGroup(id);
      nsfw.saveNsfwScalarsToGroup(id);
      e(id)['needs'] = Map<String, int>.from(needs.vector);
    }

    // Seed a participant's starting state and persist it.
    void seed(String id) {
      currentSpeaker = id;
      rel.loadScalars(
        affectionScore: 40,
        longTermScore: 20,
        trustLevel: 10,
        activeFixation: 'her steady gaze',
        fixationLifespan: 3,
        spatialStance: 'beside you',
      );
      nsfw.loadNsfwScalars(
        arousalLevel: 20,
        nsfwCooldownEnabled: false,
        cooldownTurnsRemaining: 0,
        cooldownTurnsTotal: 0,
      );
      needs.restoreFromSnapshot({
        'vector': {
          'hunger': 60,
          'bladder': 70,
          'energy': 55,
          'social': 50,
          'fun': 45,
          'hygiene': 65,
          'comfort': 75,
        },
      });
      save(id);
    }

    // One realism turn for [id]: the SAME set of deltas every time.
    void applyTurn(String id) {
      load(id);
      rel.applyScoreDelta(8); // bond +8
      rel.applyTrustDelta(-4); // trust -4
      rel.setSpatialStance('leaning in');
      nsfw.setArousalLevel(nsfw.arousalLevel + 15);
      needs.applySceneImpact(
        NeedsImpact(deltas: {'social': 12, 'fun': 8}, reason: 'good chat'),
      );
      save(id);
    }

    // Read the persisted snapshot for a participant from the shared store.
    Map<String, dynamic> snap(String id) => {
      'affection': gi(id, 'affection', 0),
      'longTermScore': gi(id, 'longTermScore', 0),
      'trust': gi(id, 'trust', 0),
      'relationshipTier': gi(id, 'relationshipTier', 0),
      'longTermTier': gi(id, 'longTermTier', 0),
      'fixation': e(id)['fixation'],
      'fixationLifespan': gi(id, 'fixationLifespan', 0),
      'spatialStance': e(id)['spatialStance'],
      'arousal': gi(id, 'arousal', 0),
      'cooldownTurnsRemaining': gi(id, 'cooldownTurnsRemaining', 0),
      'needs': (e(id)['needs'] as Map?)?.cast<String, int>(),
    };

    test(
      'a participant evolves IDENTICALLY solo (1:1) vs alongside others (group)',
      () {
        // Scenario 1:1 — alice is the only participant.
        seed('alice');
        applyTurn('alice');
        final solo = snap('alice');

        // Scenario group — alice + bob; alice takes the SAME turn, then bob
        // takes a (different) turn. Bob's presence/turn must not change alice.
        store = {};
        seed('alice');
        seed('bob');
        applyTurn('alice'); // identical alice turn
        // Bob's turn: very different deltas, exercised through the same dance.
        load('bob');
        rel.applyScoreDelta(120);
        rel.applyTrustDelta(60);
        nsfw.setArousalLevel(95);
        needs.applySceneImpact(
          NeedsImpact(deltas: {'social': -30, 'fun': -25}, reason: 'argument'),
        );
        save('bob');

        final grouped = snap('alice');

        expect(
          grouped,
          equals(solo),
          reason:
              'alice must end identical whether solo or in a group — this is '
              'the 1:1↔group parity guarantee the unified path must preserve',
        );
      },
    );

    test('order independence: alice-then-bob == bob-then-alice (no bleed)', () {
      // alice first
      seed('alice');
      seed('bob');
      applyTurn('alice');
      applyTurn('bob');
      final aliceFirst = snap('alice');

      // bob first
      store = {};
      seed('alice');
      seed('bob');
      applyTurn('bob');
      applyTurn('alice');
      final bobFirst = snap('alice');

      expect(bobFirst, equals(aliceFirst));
    });
  });
}
