// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// WorldRepository tests: rename-safety (Phase 4). The broader CRUD behavior
// remains covered by world_facade_test + integration/manual, per the earlier
// 0-fail reduction; rename gets real DB-backed coverage because it used to
// silently duplicate rows and orphan every attachment.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart' as model;
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          final tmp = Directory.systemTemp.createTempSync('fpai_world_test_');
          return tmp.path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WorldRepository.renameWorld', () {
    late AppDatabase db;
    late WorldRepository repo;

    setUp(() async {
      _setupPathProviderMock();
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.initialized;
      db = AppDatabase.forTesting();
      repo = WorldRepository(storage, db);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    tearDown(() async {
      await db.close();
    });

    test('renames the existing row in place — no duplicate', () async {
      final world = model.World(
        name: 'Old Vale',
        description: 'd',
        lorebook: Lorebook(
          entries: [LorebookEntry(key: 'vale', content: 'x')],
        ),
      );
      await repo.saveWorld(world);

      await repo.renameWorld(world, 'New Vale');

      final rows = await db.getAllWorlds();
      expect(rows.length, 1); // the old save path used to leave two rows
      expect(rows.single.name, 'New Vale');
      expect(world.name, 'New Vale');
    });

    test('character attachments follow the rename', () async {
      final storage = StorageService();
      await storage.initialized;
      final charRepo = CharacterRepository(db, storage);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      repo.setCharacterRepository(charRepo);

      final world = model.World(
        name: 'Old Vale',
        lorebook: Lorebook(entries: []),
      );
      await repo.saveWorld(world);

      final card = CharacterCard(name: 'Aria', worldNames: ['Old Vale']);
      await charRepo.addCharacter(card);

      await repo.renameWorld(world, 'New Vale');

      final updated = charRepo.characters.firstWhere((c) => c.name == 'Aria');
      expect(updated.worldNames, ['New Vale']);
    });

    test('collision with an existing world name throws', () async {
      final a = model.World(name: 'A', lorebook: Lorebook(entries: []));
      final b = model.World(name: 'B', lorebook: Lorebook(entries: []));
      await repo.saveWorld(a);
      await repo.saveWorld(b);

      expect(() => repo.renameWorld(a, 'B'), throwsStateError);
    });

    test('empty and unchanged names are no-ops', () async {
      final world = model.World(name: 'Keep', lorebook: Lorebook(entries: []));
      await repo.saveWorld(world);
      await repo.renameWorld(world, '  ');
      await repo.renameWorld(world, 'Keep');
      final rows = await db.getAllWorlds();
      expect(rows.single.name, 'Keep');
    });
  });
}
