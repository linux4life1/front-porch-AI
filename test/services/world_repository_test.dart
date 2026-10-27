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
import 'package:front_porch_ai/services/world_envelopes.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';
import 'package:front_porch_ai/services/world_store/world_store.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_mint.dart';

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

  group('WorldRepository locations (v61 parent chain)', () {
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

    model.World place(String name, {String? parent, bool climate = true}) =>
        model.World(
          name: name,
          lorebook: Lorebook(entries: []),
          parentWorldId: parent,
          climateEnabled: climate,
        );

    test(
      'chainFor walks leaf-first to the root; a root is itself alone',
      () async {
        final town = place('Bletchfield');
        await repo.saveWorld(town);
        final academy = place('Bletchmore Academy', parent: town.id);
        await repo.saveWorld(academy);
        final room = place('Library', parent: academy.id);
        await repo.saveWorld(room);

        expect(repo.chainFor(room.id).map((w) => w.id).toList(), [
          room.id,
          academy.id,
          town.id,
        ]);
        expect(repo.chainFor(town.id).map((w) => w.id).toList(), [town.id]);
        expect(repo.chainFor('no-such-world'), isEmpty);
      },
    );

    test(
      'a ring in the library terminates the walk and dedupes by id',
      () async {
        // The save check refuses new rings; this pins that a ring from a direct
        // DB write (dual-version library, repair tool) never spins the walker.
        final a = place('Root A');
        await repo.saveWorld(a);
        final b = place('Room B', parent: a.id);
        await repo.saveWorld(b);
        // Raw SQL on purpose: this is exactly the write the save check
        // refuses, done behind the repository's back (dual-version library).
        await db.customStatement(
          'UPDATE worlds SET parent_world_id = ? WHERE id = ?',
          [b.id, a.id],
        );
        await repo.loadWorlds();

        final chain = repo.chainFor(b.id).map((w) => w.id).toList();
        expect(chain, [b.id, a.id]); // stops at the repeat visit, no hang
        expect(chain.toSet().length, chain.length);
      },
    );

    test('climateAuthorFor is the nearest climate-on ancestor', () async {
      final town = place('Bletchfield');
      await repo.saveWorld(town);
      final cafe = place('Tea Rooms', parent: town.id, climate: false);
      await repo.saveWorld(cafe);
      final table = place('Back corner table', parent: cafe.id, climate: false);
      await repo.saveWorld(table);

      expect(repo.climateAuthorFor(table.id)?.id, town.id);
      expect(repo.climateAuthorFor(cafe.id)?.id, town.id);

      // A location that owns its climate is the author for itself and
      // everything inside it.
      final cavern = place('Cavern', parent: town.id);
      await repo.saveWorld(cavern);
      final pool = place('Hot pool', parent: cavern.id, climate: false);
      await repo.saveWorld(pool);
      expect(repo.climateAuthorFor(pool.id)?.id, cavern.id);
    });

    test(
      'an all-climate-off chain has no author (weather stays off)',
      () async {
        final root = place('Earth', climate: false);
        await repo.saveWorld(root);
        final city = place('City', parent: root.id, climate: false);
        await repo.saveWorld(city);
        expect(repo.climateAuthorFor(city.id), isNull);
      },
    );

    test(
      'save refuses a parent that is the world itself or a descendant',
      () async {
        final town = place('Bletchfield');
        await repo.saveWorld(town);
        final academy = place('Bletchmore Academy', parent: town.id);
        await repo.saveWorld(academy);
        final room = place('Library', parent: academy.id);
        await repo.saveWorld(room);

        await expectLater(
          () => repo.saveWorld(
            place('Bletchfield', parent: 'self')
              ..id = town.id
              ..parentWorldId = town.id,
          ),
          throwsStateError,
        );
        // Grandchild as parent of the town: a ring through existing links.
        town.parentWorldId = room.id;
        await expectLater(() => repo.saveWorld(town), throwsStateError);

        // Refused means not written: the DB keeps the pre-edit chain.
        await repo.loadWorlds();
        final rows = {for (final r in await db.getAllWorlds()) r.id: r};
        expect(rows[town.id]!.parentWorldId, isNull);
        expect(rows[academy.id]!.parentWorldId, town.id);
        expect(rows[room.id]!.parentWorldId, academy.id);
      },
    );

    test(
      'save refuses an unknown parent; plain saves are unaffected',
      () async {
        final ghost = place('Nowhere Kid', parent: 'no-such-parent');
        await expectLater(() => repo.saveWorld(ghost), throwsStateError);
        expect(repo.worldByName('Nowhere Kid'), isNull);

        final root = place('Root');
        await repo.saveWorld(root); // null parent — no extra rules apply
        expect(repo.chainFor(root.id).single.id, root.id);
      },
    );

    test(
      'deleting a world deletes its whole place tree and reports how many',
      () async {
        final town = place('Bletchfield');
        await repo.saveWorld(town);
        final academy = place('Bletchmore Academy', parent: town.id);
        await repo.saveWorld(academy);
        final room = place('Library', parent: academy.id, climate: false);
        await repo.saveWorld(room);
        final cafe = place('Tea Rooms', parent: town.id, climate: false);
        await repo.saveWorld(cafe);
        final other = place('Red Dust Station');
        await repo.saveWorld(other);
        await repo.setChatWorlds('chat-in-the-library', [room.id]);

        expect(await repo.deleteWorld(town), 3);

        // Nothing of the tree is left behind as a stray top-level world.
        final rows = {for (final r in await db.getAllWorlds()) r.id: r};
        expect(rows.keys, [other.id]);
        expect(repo.worlds.map((w) => w.id), [other.id]);
        expect(
          (await db.getChatWorldAttachments('chat-in-the-library')).allIds,
          isEmpty,
        );
        // A world with nothing inside reports zero, not an error.
        expect(await repo.deleteWorld(other), 0);
      },
    );

    test('deleting a place takes only its own subtree', () async {
      final town = place('Bletchfield');
      await repo.saveWorld(town);
      final academy = place('Bletchmore Academy', parent: town.id);
      await repo.saveWorld(academy);
      final room = place('Library', parent: academy.id);
      await repo.saveWorld(room);
      final cafe = place('Tea Rooms', parent: town.id);
      await repo.saveWorld(cafe);

      expect(await repo.deleteWorld(academy), 1);

      final ids = {for (final r in await db.getAllWorlds()) r.id};
      expect(ids, {town.id, cafe.id});
      expect(repo.worldById(cafe.id)!.parentWorldId, town.id);
    });

    test('import drops a parent id from the sender library', () async {
      // Until locations ride the envelope (slice 5), an imported place
      // arrives as a root: the sender's parent id is meaningless here.
      final json = <String, dynamic>{
        'name': 'Imported Room',
        'parent_world_id': 'sender-side-parent',
        'entries': [],
      };
      final imported = await repo.importWorldJson(json);
      expect(imported.parentWorldId, isNull);
      final row = await db.getWorldById(imported.id);
      expect(row!.parentWorldId, isNull);
    });
  });

  // Slice 5: locations ride the envelope. Guard per design §6: round-trip
  // keeps children; the old envelope still imports. Each red until the
  // codec carries `locations`.
  group('WorldRepository locations envelope (slice 5)', () {
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

    Future<model.World> seed(String name, {String? parent}) async {
      final w = model.World(
        name: name,
        description: '$name prose.',
        lorebook: Lorebook(entries: []),
        climateEnabled: parent == null,
        parentWorldId: parent,
      );
      await repo.saveWorld(w);
      return w;
    }

    test('root export carries the subtree; import recreates it with fresh '
        'ids and sourceId provenance', () async {
      final root = await seed('Bletchport');
      final town = await seed('Town Quarter', parent: root.id);
      final room = await seed('Back Room', parent: town.id);

      final envelope = repo.fpWorldJson(root);
      final locs = (envelope['locations'] as List).cast<Map>();
      expect(locs, hasLength(1));
      expect(locs.first['name'], 'Town Quarter');
      // Each item is a full world envelope with its own climate flag.
      expect(locs.first['climate_enabled'], false);
      final nested = (locs.first['locations'] as List).cast<Map>();
      expect(nested.single['name'], 'Back Room');

      // Import into the same library: fresh ids, structure preserved.
      // Name collision re-homes the copies ("Town Quarter (2)"), so
      // find them by the provenance law itself, not by name.
      final imported = await repo.importWorldJson(envelope);
      expect(imported.id, isNot(root.id));
      final rows = repo.worlds;
      final newTown = rows.firstWhere((w) => w.sourceId == town.id);
      final newRoom = rows.firstWhere((w) => w.sourceId == room.id);
      expect(newTown.parentWorldId, imported.id);
      expect(newRoom.parentWorldId, newTown.id);
      expect(newTown.id, isNot(town.id));
      expect(newRoom.id, isNot(room.id));
      expect(newTown.sourceId, town.id, reason: 'provenance per child');
      expect(newRoom.sourceId, room.id);
      expect(newTown.climateEnabled, isFalse, reason: 'inherit survives');
    });

    test(
      'an old envelope without locations imports exactly as before',
      () async {
        final old = <String, dynamic>{
          'formatVersion': 1,
          'id': 'legacy-1',
          'name': 'Old Hat',
          'description': 'No locations key.',
          'lorebook': {'entries': []},
          'climate_enabled': true,
          'meta': {'createdAt': '2025-01-01T00:00:00.000Z'},
        };
        final imported = await repo.importWorldJson(old);
        expect(imported.parentWorldId, isNull);
        expect(
          repo.worlds.where((w) => w.parentWorldId != null),
          isEmpty,
          reason: 'no phantom children',
        );
      },
    );

    test(
      'exporting a location exports its whole world, siblings included',
      () async {
        final root = await seed('Earth');
        final asia = await seed('Asia', parent: root.id);
        await seed('Europe', parent: root.id); // sibling — rides too
        final room = await seed('Tea House', parent: asia.id);

        final envelope = repo.fpWorldJson(room);
        expect(
          envelope['name'],
          'Earth',
          reason: 'root envelope, not the leaf',
        );
        final locs = (envelope['locations'] as List).cast<Map>();
        expect(locs.map((l) => l['name']).toSet(), {
          'Asia',
          'Europe',
        }, reason: 'a pruned branch read as the world but dropped places');
        final asiaEnv = locs.firstWhere((l) => l['name'] == 'Asia');
        final nested = (asiaEnv['locations'] as List).cast<Map>();
        expect(nested.map((l) => l['name']), ['Tea House']);
      },
    );

    test('nesting past town > building > room imports to the cap, not '
        'past it', () async {
      model.World deepAt(int level) => model.World(
        name: 'Deep $level',
        lorebook: Lorebook(entries: []),
        climateEnabled: false,
      );

      // Levels below the imported root: 2 is the cap (building > room).
      // Deep 4 sits at level 3 — a hand-edited or future file; the
      // importer must skip it, not throw saveWorld's law at the caller.
      final room = deepAt(2);
      final tooDeep = deepAt(3);
      final roomEnv = {
        ...encodeFpWorld(world: room),
        'locations': [encodeFpWorld(world: tooDeep)],
      };
      final building = deepAt(1);
      final buildingEnv = {
        ...encodeFpWorld(world: building),
        'locations': [roomEnv],
      };
      final town = deepAt(0);
      final env = {
        ...encodeFpWorld(world: town),
        'locations': [buildingEnv],
      };

      final imported = await repo.importWorldJson(env);
      expect(imported.name, 'Deep 0');
      final names = repo.worlds.map((w) => w.name).toList();
      expect(names, containsAll(['Deep 0', 'Deep 1', 'Deep 2']));
      expect(names, isNot(contains('Deep 3')), reason: 'cap, not crash');
    });

    // Review #599 guards: sibling collisions inside one envelope,
    // malformed locations values, and the runaway-tree budget.
    test(
      'duplicate child names inside one envelope both land, renamed',
      () async {
        final root = await seed('Harbor');
        model.World dock(String prose) => model.World(
          name: 'Dock',
          description: prose,
          lorebook: Lorebook(entries: []),
          climateEnabled: false,
        );
        final env = {
          ...encodeFpWorld(world: root),
          'locations': [
            encodeFpWorld(world: dock('East side.')),
            encodeFpWorld(world: dock('West side.')),
          ],
        };
        final imported = await repo.importWorldJson(env);
        final kids = repo.worlds
            .where((w) => w.parentWorldId == imported.id)
            .toList();
        expect(kids, hasLength(2));
        expect(kids.map((w) => w.name).toSet(), {
          'Dock',
          'Dock (2)',
        }, reason: 'uniqueWorldName runs against the live list per child');
      },
    );

    test(
      'a malformed locations value imports the root and nothing else',
      () async {
        final root = await seed('Paperweight');
        for (final bad in [
          {},
          'nope',
          ['a string', 42],
        ]) {
          final env = {...encodeFpWorld(world: root), 'locations': bad};
          final imported = await repo.importWorldJson(env);
          expect(
            repo.worlds.where((w) => w.parentWorldId == imported.id),
            isEmpty,
            reason: 'junk locations must not fabricate or throw',
          );
        }
      },
    );

    test(
      'the total import budget stops a runaway tree without throwing',
      () async {
        final codec = WorldEnvelopeCodec(repo, totalCap: 3);
        final root = await seed('Metropolis');
        model.World kid(String name) => model.World(
          name: name,
          lorebook: Lorebook(entries: []),
          climateEnabled: false,
        );
        List<Map<String, dynamic>> branch(int n) => [
          for (var i = 0; i < n; i++)
            encodeFpWorld(
              world: kid('Satellite ${root.id.substring(0, 4)}-$i'),
            ),
        ];
        final envs = [
          {...encodeFpWorld(world: kid('Alpha')), 'locations': branch(3)},
          {...encodeFpWorld(world: kid('Beta')), 'locations': branch(3)},
        ];
        await codec.importLocations(envs, root.id, 1);
        // Budget of 3: Alpha, Alpha/0, Alpha/1 land and the budget is spent —
        // even the second top-level child is skipped, with a log, not thrown.
        final names = repo.worlds.map((w) => w.name).toList();
        expect(names, contains('Alpha'));
        expect(names.where((n) => n.startsWith('Satellite')).length, 2);
        expect(names, isNot(contains('Beta')), reason: 'budget dies honestly');
      },
    );
  });

  group('WorldRepository starting place (the star)', () {
    late AppDatabase db;
    late StorageService storage;
    late WorldRepository repo;

    setUp(() async {
      _setupPathProviderMock();
      SharedPreferences.setMockInitialValues({});
      storage = StorageService();
      await storage.initialized;
      db = AppDatabase.forTesting();
      repo = WorldRepository(storage, db);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    tearDown(() async {
      await db.close();
    });

    Future<model.World> seed(
      String name, {
      String? parent,
      bool climate = false,
    }) async {
      final w = model.World(
        name: name,
        lorebook: Lorebook(entries: []),
        climateEnabled: climate,
        parentWorldId: parent,
      );
      await repo.saveWorld(w);
      return w;
    }

    test('a new chat attached to a starred world starts at the place, with '
        'the world still in its chain', () async {
      final town = await seed('Bletchfield', climate: true);
      final tea = await seed('Tea Rooms', parent: town.id);
      await seed('Town Hall', parent: town.id);
      await repo.setDefaultPlace(town, tea.id);

      await repo.applyTemplateWorldsToChat('chat-star', ['Bletchfield']);

      final slots = await repo.getChatWorldAttachments('chat-star');
      // The Tea Rooms inherit their climate (climate off on the row), yet
      // take the Setting: the author starred them as where scenes begin.
      expect(slots.primaryId, tea.id);
      expect(slots.loreIds, isEmpty);
      expect(repo.climateAuthorFor(slots.primaryId!)?.id, town.id);
    });

    test(
      'a lore-only world with a star still gives the chat a Setting',
      () async {
        final realm = await seed('Neokosmos');
        final court = await seed('Hrive Court', parent: realm.id);

        await repo.applyTemplateWorldsToChat('chat-before', [realm.id]);
        expect(
          (await repo.getChatWorldAttachments('chat-before')).primaryId,
          isNull,
          reason: 'no star: a lore-only world stays lore, as before',
        );

        await repo.setDefaultPlace(realm, court.id);
        await repo.applyTemplateWorldsToChat('chat-after', [realm.id]);
        expect(
          (await repo.getChatWorldAttachments('chat-after')).primaryId,
          court.id,
        );
      },
    );

    test(
      'a fork (startAtStar false) keeps the world itself as Setting',
      () async {
        final town = await seed('Bletchfield', climate: true);
        final tea = await seed('Tea Rooms', parent: town.id);
        await repo.setDefaultPlace(town, tea.id);

        await repo.applyTemplateWorldsToChat('chat-fork', [
          town.id,
        ], startAtStar: false);

        expect(
          (await repo.getChatWorldAttachments('chat-fork')).primaryId,
          town.id,
        );
      },
    );

    test(
      'a star whose place moved out of the world resolves to the world',
      () async {
        final town = await seed('Bletchfield', climate: true);
        final elsewhere = await seed('Elsewhere', climate: true);
        final tea = await seed('Tea Rooms', parent: town.id);
        await repo.setDefaultPlace(town, tea.id);

        tea.parentWorldId = elsewhere.id;
        await repo.saveWorld(tea);

        expect(repo.startingPlaceFor(town.id)?.id, town.id);
        await repo.applyTemplateWorldsToChat('chat-stale', [town.id]);
        expect(
          (await repo.getChatWorldAttachments('chat-stale')).primaryId,
          town.id,
        );
      },
    );

    test('starring refuses a place outside the world and keeps the old star; '
        'the star survives a reload of a lore-only world', () async {
      final realm = await seed('Neokosmos');
      final court = await seed('Hrive Court', parent: realm.id);
      final stranger = await seed('Atlantis');
      await repo.setDefaultPlace(realm, court.id);

      await expectLater(
        repo.setDefaultPlace(realm, stranger.id),
        throwsA(isA<StateError>()),
      );
      expect(realm.defaultPlaceId, court.id);

      final reloaded = WorldRepository(storage, db);
      await reloaded.ready;
      expect(reloaded.startingPlaceFor('Neokosmos')?.id, court.id);

      await repo.setDefaultPlace(realm, null);
      expect(repo.startingPlaceFor(realm.id)?.id, realm.id);
    });

    test('export then import keeps the star on the imported copy of the '
        'place', () async {
      final town = await seed('Bletchport');
      final quarter = await seed('Town Quarter', parent: town.id);
      final room = await seed('Back Room', parent: quarter.id);
      await repo.setDefaultPlace(town, room.id);

      final imported = await repo.importWorldJson(repo.fpWorldJson(town));

      final start = repo.startingPlaceFor(imported.id)!;
      expect(start.id, isNot(room.id), reason: 'the copy, not the original');
      expect(start.sourceId, room.id);
      expect(repo.chainFor(start.id).last.id, imported.id);
    });
  });

  group('World from Wiki mint: where chats start', () {
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

    model.World root(String name) => model.World(
      name: name,
      lorebook: Lorebook(entries: []),
    );
    model.World placeWorld(WorldPlaceWrite p, String parentId) => model.World(
      name: p.name,
      description: p.description,
      lorebook: Lorebook(entries: []),
      climateEnabled: false,
      parentWorldId: parentId,
    );
    WorldPlaceWrite write(String name, {String parent = ''}) => WorldPlaceWrite(
      name: name,
      parentName: parent,
      description: '$name prose.',
      entries: const [],
    );

    test('a tree mint stars the written place the author picked', () async {
      final start = WorldStartPick()..placeName = 'The Quay';
      addTearDown(start.dispose);
      final why = await mintWorldFromWiki(
        repo,
        root: root('Harborside'),
        tree: WorldWriteTree(
          root: write('Harborside'),
          places: [write('Lantern Market'), write('The Quay')],
        ),
        start: start,
        placeWorld: placeWorld,
      );

      expect(why, isNull);
      final world = repo.worldByName('Harborside')!;
      expect(repo.startingPlaceFor(world.id)?.name, 'The Quay');
      expect(repo.chainFor('The Quay').last.id, world.id);
    });

    test(
      'a flat mint creates the named starting place inside the world',
      () async {
        final start = WorldStartPick();
        addTearDown(start.dispose);
        start.nameController.text = 'The Green';
        start.descController.text = 'Sheep and a well.';
        expect(start.problem(const []), isNull);

        final why = await mintWorldFromWiki(
          repo,
          root: root('Maple Run'),
          tree: null,
          start: start,
          placeWorld: placeWorld,
        );

        expect(why, isNull);
        final world = repo.worldByName('Maple Run')!;
        final green = repo.startingPlaceFor(world.id)!;
        expect(green.name, 'The Green');
        expect(green.description, 'Sheep and a well.');
        expect(green.parentWorldId, world.id);
        expect(green.climateEnabled, isFalse, reason: 'inherits the weather');
      },
    );

    test('with no starting place the pick refuses', () {
      final start = WorldStartPick();
      addTearDown(start.dispose);
      expect(start.problem(const []), kWorldStartingPlaceRequired);
      expect(start.problem(const ['The Quay']), kWorldStartingPlacePick);
    });
  });

  group('saveWorldWithStartingPlace', () {
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

    test('a new world is saved with its new starting place inside it, '
        'starred', () async {
      final world = model.World(
        name: 'Bletchfield',
        lorebook: Lorebook(entries: []),
      );
      final place = await saveWorldWithStartingPlace(
        repo,
        world,
        const StartAtNewPlace('Tea Rooms', description: 'Steam.'),
        isNew: true,
      );

      expect(place!.parentWorldId, world.id);
      expect(repo.startingPlaceFor(world.id)?.id, place.id);
      final rows = await db.getAllWorlds();
      expect(
        rows.map((r) => r.name),
        containsAll(['Bletchfield', 'Tea Rooms']),
      );
    });

    test(
      'a starting place outside the world is refused and nothing moves',
      () async {
        final town = model.World(
          name: 'Town',
          lorebook: Lorebook(entries: []),
        );
        await repo.saveWorld(town);
        final stranger = model.World(
          name: 'Elsewhere',
          lorebook: Lorebook(entries: []),
        );
        await repo.saveWorld(stranger);

        await expectLater(
          saveWorldWithStartingPlace(
            repo,
            town,
            StartAtExistingPlace(stranger.id),
            isNew: false,
          ),
          throwsA(isA<StateError>()),
        );
        expect(town.defaultPlaceId, isNull);
      },
    );

    test('the rule: new worlds name one, worlds with places pick one, older '
        'worlds with none may stay', () {
      expect(
        startingPlaceRejection(null, isNew: true, hasPlaces: false),
        kWorldStartingPlaceRequired,
      );
      expect(
        startingPlaceRejection(
          const StartAtNewPlace('  '),
          isNew: true,
          hasPlaces: false,
        ),
        kWorldStartingPlaceRequired,
      );
      expect(
        startingPlaceRejection(null, isNew: false, hasPlaces: true),
        kWorldStartingPlacePick,
      );
      expect(
        startingPlaceRejection(null, isNew: false, hasPlaces: false),
        isNull,
      );
      expect(
        startingPlaceRejection(
          const StartAtExistingPlace('p'),
          isNew: false,
          hasPlaces: true,
        ),
        isNull,
      );
    });
  });
}
