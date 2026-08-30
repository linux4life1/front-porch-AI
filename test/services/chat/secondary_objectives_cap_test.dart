// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Side-quest cap is 4 so a character birthday outing and a {{user}}
// outing can sit beside two user-typed quests.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

final Directory _root = Directory.systemTemp.createTempSync(
  'fpai_secondary_cap_',
);

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return _root.path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
    });
    db = AppDatabase.forTesting(sameIsolate: true);
    storage = StorageService();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage));
    await storage.initialized;
  });

  tearDown(() async {
    chat.dispose();
    await db.close();
  });

  CharacterCard who() =>
      CharacterCard(name: 'Ada', firstMessage: 'Hi.')
        ..dbId = 'char-secondary-cap';

  test('four side quests stick; a fifth retires the oldest', () async {
    expect(kMaxSecondaryObjectives, 4);
    await chat.setActiveCharacter(who());
    for (var i = 1; i <= 4; i++) {
      await chat.setObjective('Side $i', isPrimary: false);
    }
    expect(chat.secondaryObjectives.map((o) => o.objective).toList(), [
      'Side 1',
      'Side 2',
      'Side 3',
      'Side 4',
    ]);

    await chat.setObjective('Side 5', isPrimary: false);
    final left = chat.secondaryObjectives.map((o) => o.objective).toList();
    expect(left, hasLength(4));
    expect(left, isNot(contains('Side 1')));
    expect(left, contains('Side 5'));
    expect(left, contains('Side 4'));
  });

  test('birthday plant and setObjective share the cap constant', () {
    final plant = File(
      'lib/services/chat/chat_service_birthday.dart',
    ).readAsStringSync();
    final set = File(
      'lib/services/chat/chat_service_objectives.dart',
    ).readAsStringSync();
    expect(plant, contains('kMaxSecondaryObjectives'));
    expect(set, contains('kMaxSecondaryObjectives'));
    expect(set, isNot(contains('length >= 2')));
  });
}
