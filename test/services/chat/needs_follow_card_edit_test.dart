// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Three layers (Needs): a character's card says how its NEW chats start, and
// editing it never reaches a chat that already exists, open or closed. Each
// chat keeps its own Needs switch, on the sidebar's Needs line and in the
// phone's chat tools. (Until this change a moved card switch was carried into
// every 1:1 chat with that character, because the sidebar had no switch.)

import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/web/facade/character_facade.dart';
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
  late CharacterFacade chars;
  late String id;

  // Lived-in chats switched off: each holds the Needs it had. (A row that
  // never saved a vector is a chat Needs never seeded, which follows its card
  // and Porch Life when it opens; needsSimAfterHydrate.)
  Future<void> addSession(String sid) => db.insertSession(
    SessionsCompanion.insert(
      id: sid,
      characterId: Value(id),
      needsSimEnabled: const Value(false),
      needsVector: const Value('{"hunger":70,"energy":60}'),
    ),
  );

  Future<bool> storedNeeds(String sid) async =>
      (await db.getSessionById(sid))!.needsSimEnabled;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting();
    final storage = StorageService();
    await storage.setRootPath(
      Directory.systemTemp.createTempSync('fpai_needs_card_').path,
    );
    final repo = CharacterRepository(db, storage);
    chat = ChatService(
      KoboldService(storage),
      UserPersonaService(db),
      storage,
      WorldRepository(storage, db),
    )..setDatabase(db);
    chars = CharacterFacade(db, storage, null, chat, repo);
    final made = await chars.create({
      'name': 'Misty',
      'needsSimEnabled': false,
    });
    id = made!['id'] as String;
    await addSession('open');
    await addSession('closed');
    await chat.setActiveCharacter(
      repo.characters.firstWhere((c) => c.dbId == id),
    );
    await chat.loadSession('open');
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test("turning a card's Needs on in its editor leaves the chats it already "
      'has as they are, open and closed', () async {
    expect(chat.needsSimEnabled, isFalse, reason: 'baseline');

    expect(await chars.update(id, {'needsSimEnabled': true}), isTrue);

    expect(chat.needsSimEnabled, isFalse, reason: 'the open chat');
    expect(await storedNeeds('open'), isFalse);
    expect(await storedNeeds('closed'), isFalse);
    await chat.loadSession('closed');
    expect(chat.needsSimEnabled, isFalse, reason: 'the closed chat opens off');
  });

  test(
    'a chat started from a card with Needs off keeps it off after the '
    'card is switched on, and turning that chat on later seeds its bars',
    () async {
      final made = await chars.create({
        'name': 'Wren',
        'firstMessage': 'The porch light hums.',
        'needsSimEnabled': false,
      });
      final wren = made!['id'] as String;
      final card = chars.cardByDbId(wren)!;
      await chat.setActiveCharacter(card);
      final started = chat.currentSessionId!;
      expect(chat.needsSimEnabled, isFalse, reason: 'the card starts it off');
      await chat.flushPendingSaves();
      // Another of Wren's chats, to leave and come back to this one.
      await db.insertSession(
        SessionsCompanion.insert(id: 'wren-other', characterId: Value(wren)),
      );
      Future<void> reopen() async {
        await chat.loadSession('wren-other');
        await chat.loadSession(started);
      }

      expect(await chars.update(wren, {'needsSimEnabled': true}), isTrue);
      await reopen();
      expect(chat.needsSimEnabled, isFalse, reason: 'it kept its own choice');

      // Switched on while closed, as the existing-chats question does.
      await chat.loadSession('wren-other');
      await db.customUpdate(
        'UPDATE sessions SET needs_sim_enabled = 1 WHERE id = ?',
        variables: [Variable(started)],
      );
      await chat.loadSession(started);
      expect(chat.needsSimEnabled, isTrue);
      expect(
        chat.needsSimulation.vector,
        isNotEmpty,
        reason: 'bars, not blank',
      );
    },
  );
}
