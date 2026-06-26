// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/facade/character_facade.dart';

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

  group('CharacterFacade.create', () {
    late AppDatabase db;
    late StorageService storage;
    late CharacterFacade facade;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting();
      await db.select(db.characters).get(); // create schema
      storage = StorageService();
      // Pin the data root to a temp dir so charactersDir is deterministic and
      // the synthesized V2 PNG has somewhere to land.
      await storage.setRootPath(
        Directory.systemTemp.createTempSync('fpai_root_').path,
      );
      facade = CharacterFacade(
        db,
        storage,
        null,
        null,
        CharacterRepository(db, storage),
      );
    });

    tearDown(() => db.close());

    test('creates a character with lorebook + realism seeds and a PNG', () async {
      final res = await facade.create({
        'name': 'Nova',
        'tags': ['scifi', 'ai'],
        'description': 'A starship AI',
        'personality': 'Calm and precise',
        'firstMessage': 'Systems online.',
        'realismEnabled': true,
        'shortTermBond': 50,
        'trustLevel': 10,
        'needsSimEnabled': true,
        'lorebook': [
          {'name': 'Ship', 'key': 'ship, vessel', 'content': 'The Aurora', 'constant': true},
          {'name': 'Empty', 'key': '', 'content': ''}, // dropped (no key/content)
        ],
      });

      expect(res, isNotNull);
      expect(res!['name'], 'Nova');

      final all = await db.getAllCharacters();
      final created = all.firstWhere((c) => c.name == 'Nova');
      expect(created.description, 'A starship AI');

      // Lorebook persisted, the empty entry filtered out.
      final detail = await facade.detail(created.id);
      final entries = (detail!['lorebook'] as Map)['entries'] as List;
      expect(entries.length, 1);
      expect((entries.first as Map)['name'], 'Ship');

      // A V2 PNG was written, so the library shows an avatar.
      final listed = await facade.list();
      final row = listed.firstWhere((m) => m['name'] == 'Nova');
      expect(row['hasAvatar'], isTrue);
      expect(File(created.imagePath != null ? created.imagePath! : '—'), isNotNull);
    });

    test('rejects a blank name', () async {
      expect(await facade.create({'name': '   '}), isNull);
      expect(await facade.create(const {}), isNull);
    });
  });
}
