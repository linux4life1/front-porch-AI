// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/web/facade/chat_facade.dart';

import '../../golden/support/fakes.dart';

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

  group('ChatFacade persona CRUD', () {
    late AppDatabase db;
    late ChatFacade facade;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting();
      await db.select(db.characters).get(); // create schema
      final storage = StorageService();
      final personas = UserPersonaService(db);
      facade = ChatFacade(
        FakeChatService(),
        CharacterRepository(db, storage),
        personas,
        null,
        null,
      );
    });

    tearDown(() => db.close());

    test('create, edit, list, delete', () async {
      expect(await facade.createPersona({'name': 'Hero', 'persona': 'brave'}), isTrue);
      var list = facade.personas();
      final hero = list.firstWhere((p) => p['name'] == 'Hero');
      expect(hero['active'], isTrue); // created persona becomes active

      final detail = facade.personaDetail(hero['id'] as String);
      expect(detail!['persona'], 'brave');

      expect(await facade.updatePersona(hero['id'] as String, {'persona': 'braver'}), isTrue);
      expect(facade.personaDetail(hero['id'] as String)!['persona'], 'braver');

      // Add a second so deleting the first is allowed (service refuses last one).
      expect(await facade.createPersona({'name': 'Sidekick'}), isTrue);
      expect(await facade.deletePersona(hero['id'] as String), isTrue);
      list = facade.personas();
      expect(list.any((p) => p['name'] == 'Hero'), isFalse);
    });

    test('unknown persona detail/update return null/false', () async {
      expect(facade.personaDetail('missing'), isNull);
      expect(await facade.updatePersona('missing', {'name': 'x'}), isFalse);
    });
  });
}
