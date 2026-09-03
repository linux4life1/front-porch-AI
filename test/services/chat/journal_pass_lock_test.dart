// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Item-memory and ledger cards are written deterministically (pockets /
// promises / milestones). The periodic journal pass listed them as editable
// and would apply LLM retire/revise. Only birthday was locked. After the
// next interval, pockets still held the item while the diary no longer
// knew where it was.
//
// Proven red: with applyOwnerProposals checking only isBirthdayCard, the
// item-card retire assertion fails (keys card gone).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/chat.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_jlock_').path;
        }
        return null;
      });

  late AppDatabase db;
  late JournalStore store;
  late JournalReview review;

  setUp(() async {
    db = AppDatabase.forTesting(sameIsolate: true);
    store = JournalStore(getDb: () => db);
    review = JournalReview(
      store: store,
      getSessionId: () => 's1',
      setRecap: (_) {},
      setCursor: (_) {},
      onSaveChat: () async {},
      onNotify: () {},
      getMaxCards: () => 200,
    );
    await db.insertSession(SessionsCompanion.insert(id: 's1'));
  });

  tearDown(() async {
    await db.close();
  });

  Future<String> plant({
    required String content,
    required String kind,
    String category = 'moment',
  }) async {
    await store.addCard(
      sessionId: 's1',
      characterId: 'mira',
      content: content,
      category: category,
      kind: kind,
      extraMetadata: kind == 'item' ? {'item': 'keys'} : null,
      maxCards: 200,
    );
    return (await store.cardsFor(
      's1',
      'mira',
    )).firstWhere((c) => c.content == content).id;
  }

  test('the pass applier refuses to retire item and ledger cards', () async {
    final itemId = await plant(
      content: 'I set my keys on the hallway table.',
      kind: 'item',
    );
    final ledgerId = await plant(
      content: 'I promised to bring lemonade.',
      kind: 'promise',
      category: 'promise',
    );
    final momentId = await plant(
      content: 'We sat out past midnight.',
      kind: 'moment',
    );

    await review.applyOwnerProposals(
      's1',
      JournalOwnerProposals(
        ownerId: 'mira',
        ownerName: 'Mira',
        ops: [
          JournalProposedOp(action: JournalOpAction.retire, cardId: itemId),
          JournalProposedOp(action: JournalOpAction.retire, cardId: ledgerId),
          JournalProposedOp(action: JournalOpAction.retire, cardId: momentId),
        ],
      ),
    );

    final left = (await store.cardsFor('s1', 'mira')).map((c) => c.content);
    expect(
      left,
      contains('I set my keys on the hallway table.'),
      reason: 'pockets still hold the keys; the diary must too',
    );
    expect(left, contains('I promised to bring lemonade.'));
    expect(
      left,
      isNot(contains('We sat out past midnight.')),
      reason: 'ordinary moments are still retireable',
    );
  });

  test('cap trim cannot evict an item card to make room', () async {
    await plant(content: 'I set my keys on the hallway table.', kind: 'item');
    await store.addCard(
      sessionId: 's1',
      characterId: 'mira',
      content: 'A new moment that would steal the slot.',
      category: 'moment',
      maxCards: 1,
    );
    final left = (await store.cardsFor('s1', 'mira')).map((c) => c.content);
    expect(
      left,
      contains('I set my keys on the hallway table.'),
      reason: 'item cards are locked from cap trim like birthday',
    );
  });

  test('_resolveOps skips locked cards the same way birthday is skipped', () {
    final src = File(
      'lib/services/chat/journal_maintenance.dart',
    ).readAsStringSync();
    expect(
      src,
      contains('JournalPhysics.isPassLockedCard(card)'),
      reason: 'the pass must not even propose retire/revise of item/ledger',
    );
    expect(src, isNot(contains('JournalPhysics.isBirthdayCard(card) &&')));
  });
}
