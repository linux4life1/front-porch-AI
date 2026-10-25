// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The chat sidebar has no Needs switch (2026-10-25); the character editor's
// switch is the one place to turn Needs on or off for a 1:1 chat. A save that
// moves the card's choice carries it into the open chat live and into the
// stored flag of every other 1:1 chat with that character. A save that leaves
// the choice alone touches no chat, and group chats keep their own switch.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
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
  late CharacterCard card;

  Future<void> addSession(String id, {String? groupId, bool needs = false}) =>
      db.insertSession(
        SessionsCompanion.insert(
          id: id,
          characterId: const Value('char-a'),
          groupId: Value(groupId),
          needsSimEnabled: Value(needs),
        ),
      );

  Future<bool> storedNeeds(String id) async =>
      (await db.getSessionById(id))!.needsSimEnabled;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting();
    final storage = StorageService();
    chat = ChatService(
      KoboldService(storage),
      UserPersonaService(db),
      storage,
      WorldRepository(storage, db),
    )..setDatabase(db);
    await addSession('open');
    await addSession('closed');
    await addSession('group', groupId: 'g1');
    card = CharacterCard(
      name: 'Misty',
      frontPorchExtensions: FrontPorchExtensions(needsSimEnabled: false),
    )..dbId = 'char-a';
    await chat.setActiveCharacter(card);
    await chat.loadSession('open');
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test('turning Needs on in the editor turns it on in the open chat and '
      'in the closed 1:1 chats, not the group', () async {
    expect(chat.needsSimEnabled, isFalse, reason: 'baseline');

    card.frontPorchExtensions!.needsSimEnabled = true;
    await chat.followCardNeedsChoice(card, before: false);

    expect(chat.needsSimEnabled, isTrue);
    expect(chat.needsSimulation.vector, isNotEmpty, reason: 'bars seeded');
    expect(await storedNeeds('open'), isTrue);
    expect(await storedNeeds('closed'), isTrue);
    expect(await storedNeeds('group'), isFalse);

    await chat.loadSession('closed');
    expect(chat.needsSimEnabled, isTrue, reason: 'the closed chat opens on');
  });

  test('turning Needs off in the editor turns it off again', () async {
    card.frontPorchExtensions!.needsSimEnabled = true;
    await chat.followCardNeedsChoice(card, before: false);

    card.frontPorchExtensions!.needsSimEnabled = false;
    await chat.followCardNeedsChoice(card, before: true);

    expect(chat.needsSimEnabled, isFalse);
    expect(await storedNeeds('open'), isFalse);
    expect(await storedNeeds('closed'), isFalse);
  });

  test('a save that leaves the Needs choice alone touches no chat', () async {
    // This chat runs Needs although the card says off (set before the
    // sidebar switch was removed). Fixing a typo must not stop it.
    await chat.setNeedsSimEnabled(true);
    card.description = 'A neighbor.';
    await chat.followCardNeedsChoice(card, before: false);

    expect(chat.needsSimEnabled, isTrue);
    expect(await storedNeeds('closed'), isFalse);
  });

  test('editing another character leaves the open chat alone', () async {
    final other = CharacterCard(
      name: 'Rook',
      frontPorchExtensions: FrontPorchExtensions(needsSimEnabled: true),
    )..dbId = 'char-b';
    await chat.followCardNeedsChoice(other, before: false);

    expect(chat.needsSimEnabled, isFalse);
  });
}
