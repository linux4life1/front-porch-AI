// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// WorldRepository tests: rename-safety (Phase 4). The broader CRUD behavior
// remains covered by world_facade_test + integration/manual, per the earlier
// 0-fail reduction; rename gets real DB-backed coverage because it used to
// silently duplicate rows and orphan every attachment.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart' as model;
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

    test('rename keeps stable id (attachments use id, not name)', () async {
      final world = model.World(
        name: 'Old Vale',
        lorebook: Lorebook(entries: []),
      );
      await repo.saveWorld(world);
      final id = world.id;

      await repo.renameWorld(world, 'New Vale');

      final rows = await db.getAllWorlds();
      expect(rows.single.id, id);
      expect(rows.single.name, 'New Vale');
      expect(repo.worldById(id)?.name, 'New Vale');
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

  group('WorldRepository purge safety (character-linked clones)', () {
    late AppDatabase db;
    late StorageService storage;

    setUp(() async {
      _setupPathProviderMock();
      SharedPreferences.setMockInitialValues({});
      storage = StorageService();
      await storage.initialized;
      db = AppDatabase.forTesting();
      await db.insertWorld(
        WorldsCompanion.insert(
          id: 'clone-1',
          name: "Aerin's Lorebook",
          description: const Value('Auto-imported from character card'),
          linkedCharacterName: const Value('Aerin'),
        ),
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('failed recovery export keeps the world; a later launch retries and '
        'completes the purge', () async {
      // Block the recovery path: a regular FILE where the directory should be
      // makes the dir create AND every export write fail on all platforms —
      // portable stand-in for disk-full/permission failures.
      final blocker = File(
        p.join(storage.worldsDir.path, 'recovered_character_lore_clones'),
      );
      await blocker.parent.create(recursive: true);
      await blocker.writeAsString('not a directory');

      final repo = WorldRepository(storage, db);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await repo.loadWorlds(); // runs the one-shot purge attempt

      // Export failed → the world SURVIVES and the one-shot pref must not
      // lock, so a later launch retries instead of stranding the clone.
      expect(
        (await db.getAllWorlds()).map((w) => w.name),
        contains("Aerin's Lorebook"),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('purged_character_linked_worlds_v1'), isNot(true));

      // Unblock → the retry exports the .fpworld, then deletes the clone and
      // locks the one-shot.
      await blocker.delete();
      await repo.loadWorlds();
      expect(
        (await db.getAllWorlds()).where((w) => w.name == "Aerin's Lorebook"),
        isEmpty,
      );
      expect(prefs.getBool('purged_character_linked_worlds_v1'), isTrue);
      final recovered = Directory(blocker.path)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.fpworld'));
      expect(recovered, hasLength(1),
          reason: 'the deleted clone must exist as a recovery .fpworld');
    });
  });
}
