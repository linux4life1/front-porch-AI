// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Home Chat History must not spawn a replacement chat when the deleted
// session is the open one and nothing remains. In-chat folder keeps the
// startNewChat last-session behaviour (startReplacement default true).

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
          return Directory.systemTemp.createTempSync('fpai_del_sess_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late ChatService chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting();
    final storage = StorageService();
    final personas = UserPersonaService(db);
    final worlds = WorldRepository(storage, db);
    chat = ChatService(KoboldService(storage), personas, storage, worlds)
      ..setDatabase(db);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  Future<CharacterCard> seedOnlySession() async {
    await db.insertCharacter(
      CharactersCompanion.insert(
        id: 'char-a',
        name: 'Misty',
        imagePath: const Value('/tmp/Misty_1.png'),
      ),
    );
    await db.insertSession(
      SessionsCompanion.insert(
        id: 'sess-only',
        characterId: const Value('char-a'),
        name: const Value('The last chat'),
      ),
    );
    await db.insertMessage(
      MessagesCompanion.insert(
        id: 'm0',
        sessionId: 'sess-only',
        position: 0,
        sender: 'Misty',
        isUser: false,
        swipes: const Value('["Evening."]'),
      ),
    );
    final card = CharacterCard(name: 'Misty', imagePath: '/tmp/Misty_1.png')
      ..dbId = 'char-a';
    await chat.setActiveCharacter(card);
    await chat.loadSession('sess-only');
    expect(chat.currentSessionId, 'sess-only');
    return card;
  }

  test('Home delete of the last chat does not spawn a replacement', () async {
    await seedOnlySession();

    await chat.deleteSession('sess-only', startReplacement: false);

    expect(chat.currentSessionId, isNull);
    expect(await db.getSessionsForCharacter('char-a'), isEmpty);
  });

  test('in-chat delete of the last chat still starts a replacement', () async {
    await seedOnlySession();

    await chat.deleteSession('sess-only');

    expect(chat.currentSessionId, isNotNull);
    expect(chat.currentSessionId, isNot('sess-only'));
  });
}
