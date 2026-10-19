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
import 'package:front_porch_ai/models/fp_world_package.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart' as model;
import 'package:front_porch_ai/services/chat/weather_biomes.dart';
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
      final a = model.World(
        name: 'A',
        lorebook: Lorebook(entries: []),
      );
      final b = model.World(
        name: 'B',
        lorebook: Lorebook(entries: []),
      );
      await repo.saveWorld(a);
      await repo.saveWorld(b);

      expect(() => repo.renameWorld(a, 'B'), throwsStateError);
    });

    test(
      'saveWorld: overlapping creates of one name each get their own name',
      () async {
        // A double-clicked Create World: both saves are in flight at once.
        model.World make() => model.World(
          name: 'The Cinder Wastes',
          lorebook: Lorebook(entries: []),
        );
        await repo.saveWorld(make());
        await Future.wait([repo.saveWorld(make()), repo.saveWorld(make())]);

        final names = (await db.getAllWorlds()).map((w) => w.name).toSet();
        expect(names, {
          'The Cinder Wastes',
          'The Cinder Wastes (2)',
          'The Cinder Wastes (3)',
        });
      },
    );

    test('empty and unchanged names are no-ops', () async {
      final world = model.World(
        name: 'Keep',
        lorebook: Lorebook(entries: []),
      );
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
      final recovered = Directory(
        blocker.path,
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.fpworld'));
      expect(
        recovered,
        hasLength(1),
        reason: 'the deleted clone must exist as a recovery .fpworld',
      );
    });
  });

  group('WorldRepository.importWorld (.fpworld full package)', () {
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

    test(
      'keeps custom climate, place traits, and lore; mints fresh id',
      () async {
        final world = model.World(
          name: 'The Cindermaw',
          description: 'Black glass and live lava.',
          lorebook: Lorebook(
            entries: [
              LorebookEntry(
                keys: ['White Peak'],
                content: 'The frozen mountain.',
              ),
            ],
          ),
        )..atmosphere = model.WorldAtmosphere.hostile;
        final packageId = world.id;
        final biome = Biome(
          id: 'custom',
          displayName: 'Cindermaw climate',
          description: 'Furnace seasons.',
          weights: {
            for (final s in kSeasons) s: [50, 20, 12, 8, 4, 6, 0],
          },
          baseTemp: {'winter': 4, 'spring': 6, 'summer': 7, 'autumn': 6},
          bandRange: (3, 6),
          displayAnchorsC: {
            'winter': 62,
            'spring': 240,
            'summer': 540,
            'autumn': 205,
          },
          diurnalAmplitude: 2.6,
          conditionSkin: {
            'storm': ConditionSkin(
              label: 'Pyroclastic Surge',
              emoji: '🌋',
              stance: WeatherStance.deadly,
            ),
          },
        );
        expect(
          biome.validate(),
          isEmpty,
          reason: 'the test climate itself must be engine-valid',
        );

        final tmpDir = Directory.systemTemp.createTempSync('fpai_import_test_');
        addTearDown(() => tmpDir.deleteSync(recursive: true));
        final file = File(p.join(tmpDir.path, 'cindermaw.fpworld'));
        await file.writeAsString(
          encodeFpWorldString(world: world, biome: biome.toJson()),
        );

        final imported = await repo.importWorld(file);

        expect(
          imported.id,
          isNot(packageId),
          reason: 'import must mint a fresh local id',
        );
        expect(
          imported.sourceId,
          packageId,
          reason: 'package id must be preserved as provenance',
        );
        expect(imported.name, 'The Cindermaw');
        expect(imported.atmosphere, model.WorldAtmosphere.hostile);
        expect(imported.lorebook.entries, hasLength(1));

        final climate = Biome.tryParse(imported.biomeJson);
        expect(
          climate,
          isNotNull,
          reason: 'custom climate must survive as biomeJson',
        );
        expect(climate!.bandRange, (3, 6));
        expect(climate.displayAnchorsC['summer'], 540);
        expect(climate.conditionSkin['storm']?.label, 'Pyroclastic Surge');
        expect(climate.conditionSkin['storm']?.stance, WeatherStance.deadly);

        // Importing the same file again keeps both (name uniquified).
        final again = await repo.importWorld(file);
        expect(again.id, isNot(imported.id));
        expect(again.name, isNot(imported.name));
      },
    );
  });

  group('WorldRepository.applyAddedCharacterWorldsToChats', () {
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

    Future<void> makeSession(String id, String characterId) => db
        .into(db.sessions)
        .insert(
          SessionsCompanion.insert(id: id, characterId: Value(characterId)),
        );

    test(
      'back-fills chats with no worlds, leaves chats that have one alone',
      () async {
        final world = model.World(
          name: 'Cindermaw',
          lorebook: Lorebook(entries: []),
        );
        final other = model.World(
          name: 'Green Vale',
          lorebook: Lorebook(entries: []),
        );
        await repo.saveWorld(world);
        await repo.saveWorld(other);

        await makeSession(
          'chat-empty',
          'char-1',
        ); // opened before the world existed
        await makeSession(
          'chat-owned',
          'char-1',
        ); // the user sent this one elsewhere
        await makeSession(
          'chat-other',
          'char-2',
        ); // a different character entirely
        await repo.setChatWorlds('chat-owned', [other.id]);

        final touched = await repo.applyAddedCharacterWorldsToChats(
          characterId: 'char-1',
          addedRefs: ['Cindermaw'], // characters store world NAMES
        );

        expect(touched, ['chat-empty']);
        expect(await repo.getChatWorldIds('chat-empty'), [world.id]);
        // A chat with its own attachment is never overridden…
        expect(await repo.getChatWorldIds('chat-owned'), [other.id]);
        // …and another character's chats are untouched.
        expect(await repo.getChatWorldIds('chat-other'), isEmpty);
      },
    );

    test('no added worlds means no writes at all', () async {
      await makeSession('chat-x', 'char-9');
      final touched = await repo.applyAddedCharacterWorldsToChats(
        characterId: 'char-9',
        addedRefs: const [],
      );
      expect(touched, isEmpty);
      expect(await repo.getChatWorldIds('chat-x'), isEmpty);
    });
  });

  group('WorldRepository.backfillChatWorldsFromCharacter', () {
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

    Future<void> makeSession(String id) => db
        .into(db.sessions)
        .insert(
          SessionsCompanion.insert(id: id, characterId: const Value('c1')),
        );

    test(
      'a chat that predates the world gets it; a deliberate detach does not',
      () async {
        final w = model.World(
          name: 'Cindermaw',
          lorebook: Lorebook(entries: []),
        );
        await repo.saveWorld(w);

        // Chat opened before the character had any world — never decided.
        await makeSession('old-chat');
        expect(
          await repo.backfillChatWorldsFromCharacter(
            chatId: 'old-chat',
            characterWorldRefs: ['Cindermaw'],
          ),
          isTrue,
        );
        expect(await repo.getChatWorldIds('old-chat'), [w.id]);

        // Now the user deliberately empties it. That IS a decision.
        await repo.setChatWorlds('old-chat', const []);
        expect(
          await repo.backfillChatWorldsFromCharacter(
            chatId: 'old-chat',
            characterWorldRefs: ['Cindermaw'],
          ),
          isFalse,
          reason: 'a deliberate detach must never be undone by a back-fill',
        );
        expect(await repo.getChatWorldIds('old-chat'), isEmpty);
      },
    );

    test('runs once — a second call is a no-op', () async {
      final w = model.World(
        name: 'Vale',
        lorebook: Lorebook(entries: []),
      );
      await repo.saveWorld(w);
      await makeSession('chat-2');
      expect(
        await repo.backfillChatWorldsFromCharacter(
          chatId: 'chat-2',
          characterWorldRefs: ['Vale'],
        ),
        isTrue,
      );
      expect(
        await repo.backfillChatWorldsFromCharacter(
          chatId: 'chat-2',
          characterWorldRefs: ['Vale'],
        ),
        isFalse,
      );
    });
  });

  group('WorldRepository.applyTemplateWorldsToChat', () {
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

    test('seeds a chat from names OR ids; unresolved refs dropped', () async {
      final byName = model.World(
        name: 'The Cindermaw',
        lorebook: Lorebook(entries: []),
      );
      final byId = model.World(
        name: 'Green Vale',
        lorebook: Lorebook(entries: []),
      );
      await repo.saveWorld(byName);
      await repo.saveWorld(byId);

      // Character worldNames are names; group templates carry ids — the
      // 1:1 new-chat seeding relies on both resolving through this one call.
      await repo.applyTemplateWorldsToChat('chat-1', [
        'The Cindermaw', // by name (character attachment)
        byId.id, // by UUID (group template)
        'No Such World', // unresolved — dropped, not an error
      ]);

      final ids = await repo.getChatWorldIds('chat-1');
      expect(ids, [byName.id, byId.id]);
    });
  });
}
