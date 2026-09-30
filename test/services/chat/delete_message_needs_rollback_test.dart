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

// Deleting a message must give back whatever needs it spent. Reported bug: a
// reply that cost 20 hunger left the character 20 hunger poorer forever once
// the message was deleted — the chips (needs_deltas) stayed on the timeline as
// a record of a change that could no longer be undone.
//
// The rule (maintainer): the deltas are kept on the message, so ANY deletion,
// however far back, subtracts that message's deltas from the CURRENT scores.
// Deleting a mid-history message is exactly as valid as deleting the last one.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_docs_').path;
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

  /// Seeds one stored message. [deltas] non-null records it the way the
  /// Realism engine does — chips under `needs_deltas` as {delta, reason}.
  Future<void> seedMessage(
    String text, {
    bool isUser = false,
    Map<String, int>? deltas,
  }) async {
    final meta = deltas == null
        ? null
        : jsonEncode({
            'needs_deltas': {
              for (final e in deltas.entries)
                e.key: {'delta': e.value, 'reason': 'test'},
            },
          });
    await db.insertMessage(
      MessagesCompanion.insert(
        id: 'm${position}_${DateTime.now().microsecondsSinceEpoch}',
        sessionId: 'sess-a',
        position: position++,
        sender: isUser ? 'You' : 'Misty',
        isUser: isUser,
        swipes: Value(jsonEncode([text])),
        metadata: Value(meta),
        swipeMetadata: Value(
          meta == null ? null : jsonEncode([jsonDecode(meta)]),
        ),
      ),
    );
  }

  /// Loads the seeded session and puts the live vector where the engine would
  /// have left it after those messages applied their deltas.
  Future<void> enterChatWithNeeds(Map<String, int> live) async {
    await chat.loadSession('sess-a');
    await chat.setNeedsSimEnabled(true);
    chat.needsSimulation.restoreFromSnapshot({'vector': live});
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
        id: 'sess-a',
        characterId: const Value('char-a'),
        needsSimEnabled: const Value(true),
      ),
    );
    await chat.setActiveCharacter(
      CharacterCard(name: 'Misty')..dbId = 'char-a',
    );
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test('deleting the last message refunds its needs deltas', () async {
    await seedMessage('Feed me.', isUser: true);
    await seedMessage('She wolfed it down.', deltas: {'hunger': -20});
    // 60 hunger, minus the 20 that message spent.
    await enterChatWithNeeds({'hunger': 40, 'energy': 70});

    chat.deleteMessage(chat.messages.length - 1);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(chat.needsSimulation.vector['hunger'], 60);
    expect(chat.needsSimulation.vector['energy'], 70);
  });

  test('deleting a message from deep in the past refunds it too', () async {
    await seedMessage('Long ago she ate.', deltas: {'hunger': -20});
    // Several turns happen afterwards, burying it.
    for (var i = 0; i < 3; i++) {
      await seedMessage('later $i', isUser: i.isEven);
    }
    await enterChatWithNeeds({'hunger': 40, 'energy': 70});

    chat.deleteMessage(0); // the old, buried message
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(
      chat.needsSimulation.vector['hunger'],
      60,
      reason: 'a buried deletion refunds exactly as a recent one does',
    );
  });

  test('a positive delta is taken back, not given again', () async {
    await seedMessage('A long nap.', deltas: {'energy': 25});
    await enterChatWithNeeds({'hunger': 60, 'energy': 95});

    chat.deleteMessage(chat.messages.length - 1);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(chat.needsSimulation.vector['energy'], 70);
  });

  test('deleting a message that spent nothing changes nothing', () async {
    await seedMessage('Just talk.');
    await enterChatWithNeeds({'hunger': 60, 'energy': 70});

    chat.deleteMessage(chat.messages.length - 1);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(chat.needsSimulation.vector['hunger'], 60);
    expect(chat.needsSimulation.vector['energy'], 70);
  });

  // Group parity note: the refund shares this exact code path — the only
  // difference is that the deleted SPEAKER'S own _groupRealism entry is the
  // baseline read and the target written (and a group speaker whose name is
  // ambiguous is skipped rather than refunding the wrong member). A real
  // group harness (repository + members + session) is not established in this
  // suite, so that branch is covered by review, not by a test here.
}
