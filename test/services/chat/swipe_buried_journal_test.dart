// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Swiping a buried (not-last) reply is navigation, not a suffix rewrite.
// Pockets and bond already stay put. Journal / Growth / RAG used to treat
// it as "everything from this position forward never happened" and
// hard-delete receipt-backed memories of later messages that were still
// on screen. Item cards planted by that swipe were not replanted unless
// it was the tip.
//
// Proven red: with the isTip gate removed around _invalidateJournalFrom
// in _commitSwipeIndex, the later diary/ring/embedding assertions fail.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/chat.dart' show JournalPhysics;

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_swipe_jrnl_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late ChatService chat;
  var position = 0;

  Future<void> seedMessage(
    List<String> swipes, {
    bool isUser = false,
    int swipeIndex = 0,
    List<Map<String, dynamic>?>? swipeMeta,
  }) async {
    await db.insertMessage(
      MessagesCompanion.insert(
        id: 'm${position}_${DateTime.now().microsecondsSinceEpoch}',
        sessionId: 'sess-swipe-j',
        position: position++,
        sender: isUser ? 'You' : 'Misty',
        isUser: isUser,
        swipes: Value(jsonEncode(swipes)),
        swipeIndex: Value(swipeIndex),
        metadata: Value(
          swipeMeta == null ? null : jsonEncode(swipeMeta[swipeIndex]),
        ),
        swipeMetadata: Value(swipeMeta == null ? null : jsonEncode(swipeMeta)),
      ),
    );
  }

  Future<void> seedChat({List<Map<String, dynamic>?>? buriedMeta}) async {
    await seedMessage(['hi'], isUser: true);
    await seedMessage(['old A', 'old B'], swipeMeta: buriedMeta);
    await seedMessage(['later'], isUser: true);
    await seedMessage(['tip A', 'tip B'], swipeIndex: 1);
    await chat.loadSession('sess-swipe-j');
  }

  Future<void> drain() async {
    for (var i = 0; i < 80; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    position = 0;
    db = AppDatabase.forTesting();
    final storage = StorageService();
    chat = ChatService(
      KoboldService(storage),
      UserPersonaService(db),
      storage,
      WorldRepository(storage, db),
    )..setDatabase(db);
    await db.insertSession(
      SessionsCompanion.insert(
        id: 'sess-swipe-j',
        characterId: const Value('char-swipe-j'),
      ),
    );
    await chat.setActiveCharacter(
      CharacterCard(name: 'Misty')..dbId = 'char-swipe-j',
    );
  });

  tearDown(() async {
    chat.dispose();
    await db.close();
  });

  test(
    'swiping a buried reply keeps later Journal, Growth, and RAG rows',
    () async {
      await seedChat();
      const sid = 'sess-swipe-j';
      await db
          .into(db.journalMemories)
          .insert(
            JournalMemoriesCompanion.insert(
              id: 'jrnl-late',
              sessionId: sid,
              characterId: 'Misty',
              content: 'We talked about the porch light later.',
              sourceMessageIds: Value(jsonEncode([3])),
            ),
          );
      await db
          .into(db.growthRings)
          .insert(
            GrowthRingsCompanion.insert(
              id: 'ring-late',
              sessionId: sid,
              characterId: 'Misty',
              content: 'She started leaving the light on.',
              sourceMessageIds: Value(jsonEncode([3])),
            ),
          );
      await db
          .into(db.messageEmbeddings)
          .insert(
            MessageEmbeddingsCompanion.insert(
              id: 'emb-late',
              sessionId: sid,
              characterId: const Value('Misty'),
              positionStart: 3,
              positionEnd: 3,
              content: 'the later reply, verbatim',
              embedding: Uint8List.fromList(const [1, 2, 3, 4]),
              dimensions: 1,
            ),
          );

      await chat.swipeMessage(1, 1);
      await drain();

      expect(chat.messages[1].text, 'old B');
      expect((await db.getJournalCardsForSession(sid)).map((c) => c.content), [
        'We talked about the porch light later.',
      ], reason: 'later diary lines must survive a buried swipe');
      expect((await db.getGrowthRingsForSession(sid)).map((r) => r.content), [
        'She started leaving the light on.',
      ]);
      expect(
        (await db.select(db.messageEmbeddings).get()).map((e) => e.content),
        ['the later reply, verbatim'],
      );
    },
  );

  test('buried swipe still replants that variant\'s item cards', () async {
    await seedChat(
      buriedMeta: [
        <String, dynamic>{},
        {
          'item_cards_planted': [
            {
              'char': 'Misty',
              'item': 'keys',
              'content': 'I set my keys on the hallway table.',
              'positions': [1],
            },
          ],
        },
      ],
    );

    await chat.swipeMessage(1, 1);
    await drain();

    final cards = await db.getJournalCardsForSession('sess-swipe-j');
    expect(cards.where(JournalPhysics.isItemCard).map((c) => c.content), [
      'I set my keys on the hallway table.',
    ], reason: 'the selected buried variant must re-sow its kit cards');
  });

  test(
    'swiping the tip still purges cards that cite the rewritten line',
    () async {
      await seedChat();
      const sid = 'sess-swipe-j';
      await db
          .into(db.journalMemories)
          .insert(
            JournalMemoriesCompanion.insert(
              id: 'jrnl-tip',
              sessionId: sid,
              characterId: 'Misty',
              content: 'She said tip B.',
              sourceMessageIds: Value(jsonEncode([3])),
            ),
          );

      await chat.swipeMessage(3, -1);
      await drain();

      expect(chat.messages[3].text, 'tip A');
      expect(
        await db.getJournalCardsForSession(sid),
        isEmpty,
        reason: 'the tip IS a suffix rewrite — its receipts must die',
      );
    },
  );
}
