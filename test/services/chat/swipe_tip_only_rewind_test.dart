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

// RE-READING AN OLD ALTERNATIVE IS NAVIGATION, NOT TIME TRAVEL.
//
// Every character message carries a `realism_state` snapshot of the moment it
// was written. `swipeMessage` restored that snapshot for whatever message you
// swiped — including one buried twenty turns back. Flicking through an old
// reply's alternatives therefore rewound the WHOLE chat's bond, trust,
// emotion, arousal, needs, story clock and pockets to that old turn while
// every later message stayed on screen, and the `_saveChat()` at the end of
// the same method wrote the rewind onto the session row permanently.
//
// The delete door already states the rule out loud ("restore from the NEW LAST
// message"); swipe now agrees: rewind only at the tip.
//
// Red-proved: with the gate back at `!isGuestMsg`, the first test reads back
// the buried variant's bond (99) instead of the tip's (200).

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_swipe_tip_').path;
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

  /// One stored message. [stamps] is one `realism_state` map per swipe.
  Future<void> seedMessage(
    List<String> swipes, {
    bool isUser = false,
    int swipeIndex = 0,
    List<Map<String, dynamic>>? stamps,
  }) async {
    final swipeMeta = stamps
        ?.map((s) => {'realism_state': s})
        .toList(growable: false);
    await db.insertMessage(
      MessagesCompanion.insert(
        id: 'm${position}_${DateTime.now().microsecondsSinceEpoch}',
        sessionId: 'sess-swipe',
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

  /// Buried reply (two alternatives, wildly different bond), two later
  /// messages on top of it, and a tip that also has two alternatives.
  Future<void> seedChat() async {
    await seedMessage(['hi'], isUser: true);
    await seedMessage(
      ['old A', 'old B'],
      stamps: [
        {'affectionScore': 10, 'trustLevel': 5},
        {'affectionScore': 99, 'trustLevel': 44},
      ],
    );
    await seedMessage(['later'], isUser: true);
    await seedMessage(
      ['tip A', 'tip B'],
      swipeIndex: 1,
      stamps: [
        {'affectionScore': 150, 'trustLevel': 30},
        {'affectionScore': 200, 'trustLevel': 60},
      ],
    );
    await chat.loadSession('sess-swipe');
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    position = 0;
    db = AppDatabase.forTesting();
    final storage = StorageService();
    final personas = UserPersonaService(db);
    final worlds = WorldRepository(storage, db);
    chat = ChatService(KoboldService(storage), personas, storage, worlds)
      ..setDatabase(db);
    await db.insertSession(
      SessionsCompanion.insert(
        id: 'sess-swipe',
        characterId: const Value('char-swipe'),
        realismEnabled: const Value(true),
        affectionScore: const Value(200),
        trustLevel: const Value(60),
      ),
    );
    await chat.setActiveCharacter(
      CharacterCard(name: 'Misty')..dbId = 'char-swipe',
    );
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test(
    'swiping a buried reply does not rewind the chat to that turn',
    () async {
      await seedChat();
      expect(chat.relationshipService.affectionScore, 200);

      await chat.swipeMessage(1, 1); // the buried reply, not the tip

      expect(chat.messages[1].text, 'old B', reason: 'the swipe itself works');
      expect(
        chat.relationshipService.affectionScore,
        200,
        reason:
            'reading an old alternative must not drag bond back twenty '
            'turns while every later message stays on screen',
      );
      expect(chat.relationshipService.trustLevel, 60);

      final row = await db.getSessionById('sess-swipe');
      expect(
        row?.affectionScore,
        200,
        reason:
            'and the save at the end of swipeMessage must not bake the '
            'rewind onto the session row',
      );
    },
  );

  test('swiping the tip still rewinds, exactly as before', () async {
    await seedChat();

    await chat.swipeMessage(3, -1); // tip: variant B → variant A

    expect(chat.messages[3].text, 'tip A');
    expect(
      chat.relationshipService.affectionScore,
      150,
      reason:
          'the tip IS the live state — its alternatives must still carry '
          'their own bond/trust, or regenerate-and-swipe-back is broken',
    );
    expect(chat.relationshipService.trustLevel, 30);
  });
}
