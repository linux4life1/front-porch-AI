// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Phase-5 milestones (docs/design/boons-and-bogies.md §7, rulings 1, 8, 9,
// 15): the moment queue, the decisions, and the popup budget, on a real
// in-memory database.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/doors/realism/milestone_surface.dart';
import 'package:front_porch_ai/services/chat/growth_boons_bogies.dart';
import 'package:front_porch_ai/services/chat/growth_milestones.dart';
import 'package:front_porch_ai/services/chat/growth_ops.dart';
import 'package:front_porch_ai/services/chat/growth_review.dart';
import 'package:front_porch_ai/services/chat/growth_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../integration_test/support/fake_backend.dart';

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
    test('Moments list newest first, even within one second; a decided '
        'row reads Accepted, never the wire word', () async {
      await proposeAdd('first');
      await proposeAdd('second');
      await proposeAdd('third');
      final texts = [
        for (final m in await milestones.momentsFor('s1'))
          MilestoneProposal.decode(m.payload)!.text,
      ];
      expect(texts, ['third', 'second', 'first']);
      final m = (await milestones.momentsFor('s1')).last;
      await milestones.decide(m.id, accept: true);
      final decided = (await milestones.momentsFor('s1')).last;
      final view = MilestoneView.of(decided, ownerName: 'Mira', inGroup: false);
      expect(view.statusLabel, 'Accepted');
      expect(view.toJson()['statusLabel'], 'Accepted');
    });

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

  group('producers through the one applier', () {
    late GrowthReview review;

    setUp(() {
      review = GrowthReview(
        store: store,
        getSessionId: () => 's1',
        getIsGroup: () => false,
        getBoonsBogiesEnabled: () => true,
        getMilestones: () => milestones,
        onApplied: () async {},
        onNotify: () {},
      );
    });

    Future<void> apply(List<GrowthProposedOp> ops) =>
        review.applyOwnerProposals(
          's1',
          GrowthOwnerProposals(ownerId: 'mira', ownerName: 'Mira', ops: ops),
        );

    Future<List<String>> kinds() async => [
      for (final m in await milestones.momentsFor('s1')) m.kind,
    ];

    test('a new boon or bogey becomes a moment; a plain trait still lands '
        '(ruling 1)', () async {
      await apply([
        GrowthProposedOp(
          action: GrowthOpAction.add,
          text: 'Hums when nervous',
          category: 'bogey',
          sourcePositions: const [3],
        ),
        GrowthProposedOp(
          action: GrowthOpAction.add,
          text: 'Reads a room in one breath',
          category: 'skill',
        ),
      ]);
      // A proposal is still one of the pass's two new things (the add cap);
      // the plain trait comes in a pass of its own.
      await apply([
        GrowthProposedOp(
          action: GrowthOpAction.add,
          text: 'Trusts slowly',
          category: 'trait',
        ),
      ]);
      final rings = await store.ringsFor('s1', 'mira');
      expect([for (final r in rings) r.content], ['Trusts slowly']);
      expect(await kinds(), containsAll(['new_bogey', 'new_boon']));
      final bogey = (await milestones.momentsFor(
        's1',
      )).firstWhere((m) => m.kind == 'new_bogey');
      expect(
        MilestoneProposal.decode(bogey.payload)?.text,
        'Hums when nervous',
      );
      expect(MilestoneProposal.decode(bogey.payload)?.sourcePositions, [3]);
    });

    test('a boon already on the card does not ask again; a plain trait with '
        'the same words still lands', () async {
      await seed(
        'Pours a perfect glass of lemonade every time.',
        category: 'skill',
        metadata: BoonsBogies.boonMetadata(),
      );
      await apply([
        GrowthProposedOp(
          action: GrowthOpAction.add,
          text: 'pours a perfect glass of lemonade  every time',
          category: 'skill',
        ),
      ]);
      expect(await kinds(), isEmpty, reason: 'nothing new to ask about');
      await apply([
        GrowthProposedOp(
          action: GrowthOpAction.add,
          text: 'Pours a perfect glass of lemonade every time.',
          category: 'trait',
        ),
      ]);
      expect((await store.ringsFor('s1', 'mira')).length, 2);
    });

    test('crossing into Master asks and the silent step stays one short; a '
        'declined ring never asks', () async {
      final boon = await seed(
        'Steady hands',
        category: 'skill',
        metadata: BoonsBogies.boonMetadata(),
        strength: 0.75,
        advance: 7,
      );
      final bogey = await seed(
        'Bad temper',
        category: 'bogey',
        metadata: BoonsBogies.bogeyMetadata(),
        strength: 0.85,
        advance: 11,
      );
      final declined = await seed(
        'Picks any lock',
        category: 'skill',
        metadata: BoonsBogies.boonMetadata(),
        strength: 0.85,
        advance: 7,
      );
      await store.bb.setMasterDeclined(declined, true);
      await apply([
        for (final r in [boon, bogey, declined])
          GrowthProposedOp(
            action: GrowthOpAction.reinforce,
            ringId: r.id,
            sourcePositions: const [9],
          ),
      ]);
      final moments = await milestones.momentsFor('s1');
      expect(
        {for (final m in moments) m.ringId: m.kind},
        {boon.id: 'master_boon', bogey.id: 'master_bogey'},
      );
      expect((await ring('Steady hands')).advanceCount, 7);
      expect((await ring('Bad temper')).advanceCount, 11);
      expect(
        BoonsBogies.tierOf(await ring('Steady hands')),
        'skilled',
        reason: 'Master shows only once accepted',
      );
    });

    test('a model retiring a bogey proposes the overcome instead', () async {
      final b = await seed(
        'Freezes on ladders',
        category: 'bogey',
        metadata: BoonsBogies.bogeyMetadata(),
      );
      await apply([
        GrowthProposedOp(action: GrowthOpAction.retire, ringId: b.id),
      ]);
      expect((await ring('Freezes on ladders')).retired, isFalse);
      expect(await kinds(), ['overcome']);
    });

    test('coping a declined bogey below 4 fires re-arms its Master', () async {
      final b = await seed(
        'Bad temper',
        category: 'bogey',
        metadata: BoonsBogies.bogeyMetadata(),
        advance: 4,
      );
      await store.bb.setMasterDeclined(b, true);
      await store.bogeys.cope('s1', 'mira', {b.id});
      final after = await ring('Bad temper');
      expect(after.advanceCount, 3);
      expect(after.masterDeclined, isFalse);
    });
  });

  group('the card on screen (MilestoneSurface)', () {
    late MilestoneSurface surface;
    var session = 's1';
    var owed = false;
    var popups = true;
    var users = 1;
    var notified = 0;

    setUp(() {
      session = 's1';
      owed = false;
      popups = true;
      users = 1;
      notified = 0;
      surface = MilestoneSurface(
        milestones: milestones,
        sessionId: () => session,
        userMessageCount: () => users,
        popupsOn: () => popups,
        replyOwed: () => owed,
        onDecided: () async {},
        notify: () => notified++,
      );
    });

    test('never opens while a reply is owed — except from the end of the '
        'reply itself', () async {
      final id = await proposeAdd('Catches what falls');
      owed = true;
      await surface.check();
      expect(surface.showing, isNull, reason: 'a reply is still to come');
      await surface.check(afterReply: true);
      expect(surface.showing?.id, id);
      expect((await moment(id)).shownAt, 1);
      expect(notified, 1);
    });

    test('popups off: nothing opens, the moment waits unread', () async {
      final id = await proposeAdd('Catches what falls');
      popups = false;
      await surface.check(afterReply: true);
      expect(surface.showing, isNull);
      expect((await moment(id)).seen, isFalse);
    });

    test('Accept closes the card; a full bogey cap keeps it up', () async {
      for (final t in ['one', 'two', 'three']) {
        await seed(t, category: 'bogey', metadata: BoonsBogies.bogeyMetadata());
      }
      final id = await proposeAdd('four', bogey: true);
      await surface.check(afterReply: true);
      expect(
        await surface.answer(id, accept: true),
        MilestoneOutcome.bogeyCapFull,
      );
      expect(surface.showing?.id, id, reason: 'the user is told why');
      expect(await surface.answer(id, accept: false), MilestoneOutcome.done);
      expect(surface.showing, isNull);
    });

    test('a decided moment replays without asking; another chat never sees '
        'the card', () async {
      final id = await proposeAdd('Catches what falls');
      await milestones.decide(id, accept: true);
      await surface.replay(id);
      expect(surface.showing?.id, id);
      expect(surface.replaying, isTrue);
      session = 's2';
      expect(surface.showing, isNull);
      expect(surface.replaying, isFalse);
    });
  });

  group('a real Growth pass raises the card (ChatService, fake backend)', () {
    late AppDatabase chatDb;
    late StorageService storage;
    late ChatService chat;
    late FakeBackendServer backend;

    setUp(() async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({'update_auto_check': false});
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            return Directory.systemTemp.createTempSync('fpai_ms_').path;
          });
      chatDb = AppDatabase.forTesting();
      backend = await FakeBackendServer.start(replyPieces: ['Evening.']);
      storage = StorageService();
      chat =
          ChatService(
              KoboldService(storage),
              UserPersonaService(chatDb),
              storage,
              WorldRepository(storage, chatDb),
            )
            ..setDatabase(chatDb)
            ..setCharacterRepository(CharacterRepository(chatDb, storage))
            ..testLlmServiceOverride = OpenRouterService(
              apiUrl: '${backend.baseUrl}/v1',
              modelName: 'smoke-model',
            );
      await storage.initialized;
      await storage.memorySettings.setCharacterEvolutionEnabled(true);
      await storage.memorySettings.setBoonsBogiesEnabled(true);
      await storage.memorySettings.setMilestonePopupsEnabled(true);
    });

    tearDown(() async {
      chat.dispose();
      await backend.close();
      await chatDb.close();
    });

    // One reply, then the Growth pass the background job would run; waits
    // for the card it queues.
    Future<void> raiseCard(CharacterCard card) async {
      await chat.setActiveCharacter(card);
      await chat.sendMessage('I pour us both a glass of lemonade.');
      for (
        var i = 0;
        i < 400 && (chat.isGenerating || chat.isSettlingTurn);
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await chat.forceGrowthPass();
      for (var i = 0; i < 100 && chat.milestoneShowing == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    test(
      'a pass after the reply queues a new boon and the card is up',
      () async {
        final card = CharacterCard(
          name: 'Mira Vale',
          description: 'Keeps the porch bar.',
          firstMessage: 'Evening.',
          frontPorchExtensions: FrontPorchExtensions(
            realismEnabled: false,
            needsSimEnabled: false,
          ),
        )..dbId = 'mira-pass';
        await raiseCard(card);
        expect(
          chat.milestoneShowing?.kind,
          'new_boon',
          reason: 'a normal (not review-first) pass must raise the card',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'deleting the message a pending boon cites drops it and its card',
      () async {
        await raiseCard(
          CharacterCard(
            name: 'Mira Vale',
            description: 'Keeps the porch bar.',
            firstMessage: 'Evening.',
            frontPorchExtensions: FrontPorchExtensions(
              realismEnabled: false,
              needsSimEnabled: false,
            ),
          )..dbId = 'mira-rewrite',
        );
        expect(chat.milestoneShowing?.kind, 'new_boon');
        final session = chat.currentSessionId!;
        final shown = chat.milestoneShowing!;
        expect(MilestoneProposal.decode(shown.payload)?.sourcePositions, [
          1,
        ], reason: 'the boon cites the user message (#2)');
        // Deleting message #2 rewrites the timeline from there.
        await chat.deleteMessage(1);
        Future<List<GrowthMomentData>> moments() =>
            chat.realism.growthMilestones.momentsFor(session);
        for (var i = 0; i < 100 && (await moments()).isNotEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(await moments(), isEmpty, reason: 'it asked about lost plot');
        expect(chat.milestoneShowing, isNull, reason: 'its card came down');
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

  group('a timeline rewrite drops pending moments citing it', () {
    test('cites at or after the rewrite: dropped; earlier, decided, or a '
        'live ring: kept; a Master whose ring went: dropped', () async {
      Future<String> add(String text, List<int> at) async =>
          (await milestones.propose(
            sessionId: 's1',
            characterId: 'mira',
            kind: MilestoneKind.newBoon,
            proposal: MilestoneProposal(
              text: text,
              category: 'skill',
              sourcePositions: at,
            ),
          ))!;
      final early = await add('Hums when nervous', [2]);
      final late = await add('Reads a room', [3, 6]);
      final decided = await add('Pours lemonade', [7]);
      await milestones.decide(decided, accept: false);
      final boon = await seed(
        'Steady hands',
        category: 'skill',
        metadata: BoonsBogies.boonMetadata(),
      );
      final master = (await milestones.propose(
        sessionId: 's1',
        characterId: 'mira',
        kind: MilestoneKind.masterBoon,
        ringId: boon.id,
      ))!;
      final liveMaster = await seed(
        'Bad temper',
        category: 'bogey',
        metadata: BoonsBogies.bogeyMetadata(),
      );
      final kept = (await milestones.propose(
        sessionId: 's1',
        characterId: 'mira',
        kind: MilestoneKind.masterBogey,
        ringId: liveMaster.id,
      ))!;
      await store.deleteRing(boon.id); // the ring sweep removed it

      final dropped = await milestones.invalidatePendingFrom('s1', 6);
      expect(dropped.toSet(), {late, master});
      final left = {for (final m in await milestones.momentsFor('s1')) m.id};
      expect(left, {early, decided, kept});
    });
  });
}
