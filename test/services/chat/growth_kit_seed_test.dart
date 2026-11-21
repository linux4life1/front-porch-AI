// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Kit seeding tests (docs/design/boons-and-bogies.md §4, ruling 13, §9):
// the pure decision table the first Growth touch runs on, the per-owner
// ring plan (tier math, the 3-bogey cap, once-per-chat skip), and the
// DB half — advance_count persistence, the kit's separate budget against
// the 12 story rings, and the settle flag on growth_state.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/character/trait_kit.dart';
import 'package:front_porch_ai/services/chat/growth_boons_bogies.dart';
import 'package:front_porch_ai/services/chat/growth_kit_seed.dart';
import 'package:front_porch_ai/services/chat/growth_physics.dart';
import 'package:front_porch_ai/services/chat/growth_store.dart';

GrowthRingData _ring({
  String category = 'trait',
  String? metadata,
  double strength = 0.5,
  bool pinned = false,
}) => GrowthRingData(
  id: 'r${DateTime.now().microsecondsSinceEpoch}',
  sessionId: 's1',
  characterId: 'c1',
  content: 'a ring',
  category: category,
  strength: strength,
  pinned: pinned,
  retired: false,
  createdAt: DateTime(2026),
  lastReinforcedAt: DateTime(2026),
  updatedAt: DateTime(2026),
  metadata: metadata,
  advanceCount: 0,
  bogeyPressure: 0,
  bogeyCooldown: 0,
  bogeyDelivered: false,
  masterDeclined: false,
);

TraitKitEntry _entry(
  String text, {
  bool bogey = false,
  String tier = TraitKitEntry.tierEmerging,
  bool? pinned,
}) => TraitKitEntry(
  kind: bogey ? TraitKitEntry.kindBogey : TraitKitEntry.kindBoon,
  text: text,
  tier: tier,
  pinned: pinned ?? bogey,
);

void main() {
  group('decide — the unit is the chat (ruling 13)', () {
    test('an unsettled chat with a kit takes it silently when no rings', () {
      expect(
        GrowthKitSeed.decide(
          state: GrowthKitSeed.kStateUnsettled,
          castHasKit: true,
          sessionHasRings: false,
        ),
        KitAction.autoSeed,
        reason: 'no story to preserve — §4 seeds the new chat at first touch',
      );
    });

    test('a chat with earned rings is offered, never seeded over', () {
      expect(
        GrowthKitSeed.decide(
          state: GrowthKitSeed.kStateUnsettled,
          castHasKit: true,
          sessionHasRings: true,
        ),
        KitAction.offer,
      );
    });

    test('settled and declined never re-nag; no kit never fires', () {
      for (final state in [
        GrowthKitSeed.kStateSettled,
        GrowthKitSeed.kStateDeclined,
      ]) {
        for (final rings in [true, false]) {
          expect(
            GrowthKitSeed.decide(
              state: state,
              castHasKit: true,
              sessionHasRings: rings,
            ),
            KitAction.none,
          );
        }
      }
      expect(
        GrowthKitSeed.decide(
          state: GrowthKitSeed.kStateUnsettled,
          castHasKit: false,
          sessionHasRings: false,
        ),
        KitAction.none,
      );
    });
  });

  group('planOwner — the ring plan per owner', () {
    test('tier decides strength and advance floor, both kinds', () {
      final plan = GrowthKitSeed.planOwner(
        kit: [
          _entry('reads a room', tier: TraitKitEntry.tierEstablished),
          _entry('bad temper', bogey: true, tier: TraitKitEntry.tierDeveloping),
        ],
        activeRings: const [],
      );
      expect(plan, hasLength(2));
      expect(plan[0].category, 'skill');
      expect(plan[0].strength, closeTo(0.80, 1e-9));
      expect(
        plan[0].advanceCount,
        BoonsBogies.kitSeedAdvance(TraitKitEntry.tierEstablished, bogey: false),
      );
      expect(plan[1].category, BoonsBogies.kCategoryBogey);
      expect(plan[1].strength, closeTo(0.60, 1e-9));
      expect(plan[0].pinned, isFalse);
      expect(plan[1].pinned, isTrue, reason: 'a bogey arrives pinned (§4)');
      expect(
        BoonsBogies.isKitSeeded(
          _ring(metadata: plan[0].metadata, category: 'skill'),
        ),
        isTrue,
      );
      expect(
        BoonsBogies.isBoon(
          _ring(metadata: plan[0].metadata, category: 'skill'),
        ),
        isTrue,
      );
      expect(
        BoonsBogies.isBogey(
          _ring(metadata: plan[1].metadata, category: 'bogey'),
        ),
        isTrue,
      );
    });

    test('bogies past the shared cap are dropped, boons never', () {
      final already = [
        for (var i = 0; i < BoonsBogies.kMaxActiveBogies; i++)
          _ring(metadata: BoonsBogies.bogeyMetadata(), category: 'bogey'),
      ];
      final plan = GrowthKitSeed.planOwner(
        kit: [_entry('one too many', bogey: true), _entry('reads a room')],
        activeRings: already,
      );
      expect(
        plan,
        hasLength(1),
        reason:
            'the cap is full — the bogey is '
            'dropped whole (§5), and the boon does not compete for its slot',
      );
      expect(plan.single.category, 'skill');
    });

    test('an owner already seeded is skipped — the kit seeds once', () {
      final seeded = _ring(
        category: 'bogey',
        metadata: BoonsBogies.bogeyMetadata(seeded: true),
      );
      expect(
        GrowthKitSeed.planOwner(
          kit: [_entry('bad temper')],
          activeRings: [seeded],
        ),
        isEmpty,
        reason:
            'deleting the seeded rings is the user\'s story, not a '
            're-seed trigger (the panel\'s re-run button covers do-overs)',
      );
    });

    test('linkedTo rides the bogey metadata untouched', () {
      final plan = GrowthKitSeed.planOwner(
        kit: [
          _entry(
            'bad temper',
            bogey: true,
            pinned: false,
          ).copyWithLinked('reads a room'),
        ],
        activeRings: const [],
      );
      expect(plan.single.metadata, contains('reads a room'));
    });
  });

  group('the DB half (real in-memory AppDatabase)', () {
    late AppDatabase db;
    late GrowthStore store;

    setUp(() {
      db = AppDatabase.forTesting(sameIsolate: true);
      store = GrowthStore(getDb: () => db);
    });
    tearDown(() async => db.close());

    Future<void> seedSession(String id) =>
        db.insertSession(SessionsCompanion.insert(id: id));

    test('a seeded ring keeps the advance floor the plan asked for', () async {
      await seedSession('s1');
      await store.addRing(
        sessionId: 's1',
        characterId: 'c1',
        content: 'bad temper',
        category: 'bogey',
        strength: BoonsBogies.kitSeedStrength('established'),
        advanceCount: BoonsBogies.kitSeedAdvance('established', bogey: true),
        pinned: true,
        metadata: BoonsBogies.bogeyMetadata(seeded: true),
      );
      await store.refresh('s1', charIds: ['c1'], activeCharId: 'c1');
      final ring = store.activeRingsFor('s1', 'c1').single;
      expect(ring.advanceCount, 10);
      expect(ring.pinned, isTrue);
      expect(BoonsBogies.isKitSeeded(ring), isTrue);
    });

    test('the kit does not spend the 12 story rings (§4)', () async {
      await seedSession('s1');
      for (var i = 0; i < 4; i++) {
        await store.addRing(
          sessionId: 's1',
          characterId: 'c1',
          content: 'kit ring $i',
          category: 'skill',
          strength: 0.3,
          metadata: BoonsBogies.boonMetadata(seeded: true),
        );
      }
      for (var i = 0; i < GrowthPhysics.kMaxActiveRings; i++) {
        await store.addRing(
          sessionId: 's1',
          characterId: 'c1',
          content: 'story ring $i',
          category: 'trait',
          strength: 0.4 + i * 0.01,
        );
      }
      await store.refresh('s1', charIds: ['c1'], activeCharId: 'c1');
      final active = store.activeRingsFor('s1', 'c1');
      expect(
        active.where((r) => BoonsBogies.isKitSeeded(r)),
        hasLength(4),
        reason:
            'capVictim only ever sees story rings — four seeded kits do '
            'not squeeze out four earned rings',
      );
      expect(
        active.where((r) => !BoonsBogies.isKitSeeded(r)),
        hasLength(GrowthPhysics.kMaxActiveRings),
      );
    });

    test('the settle flag persists and defaults to unsettled', () async {
      await seedSession('s1');
      expect(await db.getKitSeedState('s1'), GrowthKitSeed.kStateUnsettled);
      await store.setKitSeedState('s1', GrowthKitSeed.kStateDeclined);
      expect(await db.getKitSeedState('s1'), GrowthKitSeed.kStateDeclined);
      await store.setKitSeedState('s1', GrowthKitSeed.kStateSettled);
      expect(await db.getKitSeedState('s1'), GrowthKitSeed.kStateSettled);
    });
  });

  group('budget mirror', () {
    test('the service cap is the model cap', () {
      expect(BoonsBogies.kMaxKitEntries, TraitKitEntry.maxEntries);
    });
  });
}

extension on TraitKitEntry {
  TraitKitEntry copyWithLinked(String linked) => TraitKitEntry(
    kind: kind,
    text: text,
    tier: tier,
    pinned: pinned,
    linkedTo: linked,
  );
}
