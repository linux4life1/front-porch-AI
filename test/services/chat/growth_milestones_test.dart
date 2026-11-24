// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Phase-5 milestones (docs/design/boons-and-bogies.md §7, rulings 1, 8, 9,
// 15): the moment queue, the decisions, and the popup budget, on a real
// in-memory database.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/growth_boons_bogies.dart';
import 'package:front_porch_ai/services/chat/growth_milestones.dart';
import 'package:front_porch_ai/services/chat/growth_store.dart';

void main() {
  late AppDatabase db;
  late GrowthStore store;
  late GrowthMilestones milestones;

  setUp(() async {
    db = AppDatabase.forTesting(sameIsolate: true);
    store = GrowthStore(getDb: () => db);
    milestones = GrowthMilestones(store: store, getDb: () => db);
    await db.insertSession(SessionsCompanion.insert(id: 's1'));
  });

  tearDown(() async => db.close());

  Future<GrowthRingData> ring(String content) async => (await store.ringsFor(
    's1',
    'mira',
  )).firstWhere((r) => r.content == content);

  Future<GrowthRingData> seed(
    String content, {
    required String category,
    String? metadata,
    double strength = 0.5,
    int advance = 0,
    bool pinned = false,
  }) async {
    await store.addRing(
      sessionId: 's1',
      characterId: 'mira',
      content: content,
      category: category,
      strength: strength,
      pinned: pinned,
      metadata: metadata,
      advanceCount: advance,
    );
    return ring(content);
  }

  Future<GrowthMomentData> moment(String id) async =>
      (await milestones.momentsFor('s1')).firstWhere((m) => m.id == id);

  Future<String> proposeAdd(String text, {bool bogey = false}) async =>
      (await milestones.propose(
        sessionId: 's1',
        characterId: 'mira',
        kind: bogey ? MilestoneKind.newBogey : MilestoneKind.newBoon,
        proposal: MilestoneProposal(
          text: text,
          category: bogey ? 'bogey' : 'skill',
          sourcePositions: const [4],
        ),
      ))!;

  group('decide (ruling 1: new ones and Master always ask)', () {
    test('Accept on a new boon adds it as a boon; a second tap writes '
        'nothing', () async {
      final id = await proposeAdd('Catches what falls');
      final results = await Future.wait([
        milestones.decide(id, accept: true),
        milestones.decide(id, accept: true),
      ]);
      expect(results, contains(MilestoneOutcome.done));
      final rings = await store.ringsFor('s1', 'mira');
      expect(
        rings.where((r) => r.content == 'Catches what falls'),
        hasLength(1),
      );
      expect(BoonsBogies.isBoon(rings.single), isTrue);
      expect((await moment(id)).status, 'accepted');
      expect(
        await milestones.decide(id, accept: false),
        MilestoneOutcome.alreadyDecided,
      );
    });

    test('Reject on an add drops it (ruling 15: no Redo)', () async {
      final id = await proposeAdd('Knocks things over', bogey: true);
      expect(await milestones.decide(id, accept: false), MilestoneOutcome.done);
      expect(await store.ringsFor('s1', 'mira'), isEmpty);
      expect((await moment(id)).status, 'rejected');
    });

    test('a fourth bogey waits instead of passing the cap', () async {
      for (final t in ['one', 'two', 'three']) {
        await seed(t, category: 'bogey', metadata: BoonsBogies.bogeyMetadata());
      }
      final id = await proposeAdd('four', bogey: true);
      expect(
        await milestones.decide(id, accept: true),
        MilestoneOutcome.bogeyCapFull,
      );
      expect((await moment(id)).status, 'pending');
      expect((await store.ringsFor('s1', 'mira')), hasLength(3));
    });

    test('Master accepted: the trait is crowned; rejected: the latch is '
        'set and the ring stays below Master', () async {
      final boon = await seed(
        'Steady hands',
        category: 'skill',
        metadata: BoonsBogies.boonMetadata(),
        strength: 0.86,
        advance: 7,
      );
      final bogey = await seed(
        'Bad temper',
        category: 'bogey',
        metadata: BoonsBogies.bogeyMetadata(),
        strength: 0.85,
        advance: 11,
      );
      final yes = (await milestones.propose(
        sessionId: 's1',
        characterId: 'mira',
        kind: MilestoneKind.masterBoon,
        ringId: boon.id,
      ))!;
      final no = (await milestones.propose(
        sessionId: 's1',
        characterId: 'mira',
        kind: MilestoneKind.masterBogey,
        ringId: bogey.id,
      ))!;
      await milestones.decide(yes, accept: true);
      await milestones.decide(no, accept: false);

      final crowned = await ring('Steady hands');
      expect(crowned.advanceCount, BoonsBogies.kBoonMasterPasses);
      expect(crowned.strength, greaterThanOrEqualTo(0.90));
      final declined = await ring('Bad temper');
      expect(declined.masterDeclined, isTrue);
      expect(declined.advanceCount, 11);
    });

    test('an accepted overcome retires the bogey even when pinned — the one '
        'exception', () async {
      final b = await seed(
        'Freezes on ladders',
        category: 'bogey',
        metadata: BoonsBogies.bogeyMetadata(),
        pinned: true,
      );
      final id = (await milestones.propose(
        sessionId: 's1',
        characterId: 'mira',
        kind: MilestoneKind.overcome,
        ringId: b.id,
      ))!;
      await milestones.decide(id, accept: true);
      expect((await ring('Freezes on ladders')).retired, isTrue);
    });

    test('a moment about a ring that is gone closes as rejected', () async {
      final b = await seed('Gone soon', category: 'bogey');
      final id = (await milestones.propose(
        sessionId: 's1',
        characterId: 'mira',
        kind: MilestoneKind.overcome,
        ringId: b.id,
      ))!;
      await store.deleteRing(b.id);
      expect(
        await milestones.decide(id, accept: true),
        MilestoneOutcome.ringGone,
      );
      expect((await moment(id)).status, 'rejected');
    });
  });

  group('the queue and the budget (ruling 9)', () {
    test('the same crossing is never queued twice', () async {
      final b = await seed('Bad temper', category: 'bogey');
      final a = await milestones.propose(
        sessionId: 's1',
        characterId: 'mira',
        kind: MilestoneKind.masterBogey,
        ringId: b.id,
      );
      final again = await milestones.propose(
        sessionId: 's1',
        characterId: 'mira',
        kind: MilestoneKind.masterBogey,
        ringId: b.id,
      );
      expect(again, a);
      final add1 = await proposeAdd('Hums when nervous');
      expect(await proposeAdd('Hums when nervous'), add1);
      expect(await milestones.momentsFor('s1'), hasLength(2));
    });

    test('one popup per 8 user messages, oldest first; popups off shows '
        'nothing', () async {
      final first = await proposeAdd('first');
      await db
          .update(db.growthMoments)
          .write(GrowthMomentsCompanion(createdAt: Value(DateTime(2026))));
      final second = await proposeAdd('second');

      expect(
        await milestones.nextToShow('s1', userMessages: 3, popupsOn: false),
        isNull,
      );
      final shown = await milestones.nextToShow(
        's1',
        userMessages: 3,
        popupsOn: true,
      );
      expect(shown?.id, first);
      await milestones.markShown(first, 3);

      expect(
        await milestones.nextToShow('s1', userMessages: 10, popupsOn: true),
        isNull,
        reason: '7 user messages since the last popup',
      );
      expect(
        (await milestones.nextToShow(
          's1',
          userMessages: 11,
          popupsOn: true,
        ))?.id,
        second,
      );
      expect((await moment(second)).seen, isFalse, reason: 'still unread');
    });
  });
}
