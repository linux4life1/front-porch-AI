// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/services/web/facade/world_facade.dart';
import 'package:front_porch_ai/utils/world_cover.dart';
import 'package:image/image.dart' as img;

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

  group('WorldFacade', () {
    late AppDatabase db;
    late WorldFacade facade;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting();
      await db.select(db.characters).get(); // create schema
      final storage = StorageService();
      await storage.setRootPath(
        Directory.systemTemp.createTempSync('fpai_root_').path,
      );
      final repo = WorldRepository(storage, db);
      await repo.loadWorlds(); // settle the constructor's async load first
      facade = WorldFacade(repo);
    });

    tearDown(() => db.close());

    test('create / detail / rename / delete', () async {
      expect(
        await facade.save({
          'name': 'Aetheria',
          'description': 'A sky realm',
          'entries': [
            {'name': 'Sky', 'key': 'sky, clouds', 'content': 'Endless blue'},
            {'name': 'Empty', 'key': '', 'content': ''}, // dropped
          ],
        }),
        isTrue,
      );

      var list = facade.list();
      final w = list.firstWhere((m) => m['name'] == 'Aetheria');
      expect(w['entryCount'], 1);

      final detail = facade.detail('Aetheria');
      expect(detail!['description'], 'A sky realm');
      expect((detail['entries'] as List).length, 1);

      // Rename via originalName.
      expect(
        await facade.save({
          'name': 'Aetheria Prime',
          'originalName': 'Aetheria',
          'entries': [
            {'name': 'Sky', 'key': 'sky', 'content': 'Endless blue'},
          ],
        }),
        isTrue,
      );
      list = facade.list();
      expect(list.any((m) => m['name'] == 'Aetheria'), isFalse);
      expect(list.any((m) => m['name'] == 'Aetheria Prime'), isTrue);

      expect(await facade.delete('Aetheria Prime'), isTrue);
      expect(facade.list().any((m) => m['name'] == 'Aetheria Prime'), isFalse);
    });

    test('create with a taken name adds "(2)"; the original is kept', () async {
      expect(
        await facade.save({'name': 'Maple Run', 'description': 'Original'}),
        isTrue,
      );
      expect(
        await facade.save({
          'name': 'Maple Run',
          'description': 'Newcomer',
          'create': true,
        }),
        isTrue,
      );
      final names = facade.list().map((m) => m['name']).toList();
      expect(names, containsAll(['Maple Run', 'Maple Run (2)']));
      expect(facade.detail('Maple Run')!['description'], 'Original');
      expect(facade.detail('Maple Run (2)')!['description'], 'Newcomer');
    });

    test('blank name rejected; unknown delete returns false', () async {
      expect(await facade.save({'name': '  '}), isFalse);
      expect(await facade.delete('nope'), isFalse);
      expect(facade.detail('nope'), isNull);
    });

    test(
      'importWorld keeps place traits and custom climate (shared core)',
      () async {
        // A minimal .fpworld envelope with hostile air and a custom biome —
        // the web import must preserve both, exactly like desktop file import.
        expect(
          await facade.importWorld({
            'formatVersion': 1,
            'id': 'pkg-123',
            'name': 'The Cindermaw',
            'description': 'Black glass and live lava.',
            'lorebook': {
              'entries': [
                {
                  'keys': ['White Peak'],
                  'content': 'The frozen mountain.',
                },
              ],
            },
            'place_traits': {'atmosphere': 'hostile', 'gravity': 'low'},
            'biome': {
              'id': 'custom',
              'displayName': 'Cindermaw climate',
              'description': 'Furnace seasons.',
              'weights': {
                'winter': [50, 20, 12, 8, 4, 6, 0],
                'spring': [50, 20, 12, 8, 4, 6, 0],
                'summer': [50, 20, 12, 8, 4, 6, 0],
                'autumn': [50, 20, 12, 8, 4, 6, 0],
              },
              'baseTemp': {'winter': 4, 'spring': 6, 'summer': 7, 'autumn': 6},
              'bandRange': [3, 6],
              'displayAnchorsC': {
                'winter': 62,
                'spring': 240,
                'summer': 540,
                'autumn': 205,
              },
              'diurnalAmplitude': 2.6,
            },
          }),
          isTrue,
        );
        final detail = facade.list().firstWhere(
          (m) => m['name'] == 'The Cindermaw',
        );
        final imported = facade.detail(detail['id'] as String)!;
        expect(imported['atmosphere'], 'hostile');
        expect(imported['gravity'], 'low');
        expect(
          imported['biomeId'],
          'custom',
          reason: 'custom climate must survive web import',
        );
      },
    );

    test('save custom climate and reject overlapping starts', () async {
      final template = Map<String, dynamic>.from(
        facade.climates().firstWhere((c) => c['id'] == 'temperate')['template']
            as Map,
      );
      template['id'] = 'custom';
      template['seasonLabels'] = {'summer': 'High Sun'};
      expect(
        await facade.save({
          'name': 'Solaria',
          'biomeId': 'custom',
          'biome': template,
        }),
        isTrue,
      );
      final d = facade.detail('Solaria')!;
      expect(d['biomeId'], 'custom');
      expect((d['biome'] as Map)['seasonLabels'], {'summer': 'High Sun'});

      template['seasonStarts'] = {
        'winter': 1,
        'spring': 1,
        'summer': 152,
        'autumn': 244,
      };
      // Review #596: a climate refusal must arrive as its own sentence,
      // not the route's 'name is required' lie. Behavior change this PR
      // intends: save now THROWS where it returned false; the message is
      // what the author must read.
      await expectLater(
        facade.save({
          'name': 'Solaria',
          'originalName': 'Solaria',
          'biomeId': 'custom',
          'biome': template,
        }),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('climate'),
          ),
        ),
      );
      expect(
        facade.climateErrors(template).join(' '),
        contains('cannot overlap'),
      );
    });
  });

  // Slice 4 (web + relay twins): the PWA groups the library, preselects
  // "Part of", and moves places through these payloads. Each guard is
  // red until the relay carries the field the desktop already renders.
  group('locations relay fields (slice 4)', () {
    late AppDatabase db;
    late WorldFacade facade;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting();
      await db.select(db.characters).get();
      final storage = StorageService();
      await storage.setRootPath(
        Directory.systemTemp.createTempSync('fpai_root_').path,
      );
      final repo = WorldRepository(storage, db);
      await repo.loadWorlds();
      facade = WorldFacade(repo);
    });

    tearDown(() => db.close());

    Future<String> createWorld(Map<String, dynamic> form) async {
      expect(await facade.save(form), isTrue);
      final name = form['name'] as String;
      return facade.list().firstWhere((m) => m['name'] == name)['id'] as String;
    }

    test('list counts switched-on entries apart from all entries', () async {
      await createWorld({
        'name': 'Cindermaw',
        'entries': [
          {'name': 'Lava', 'key': 'lava', 'content': 'Rivers of it'},
          {
            'name': 'Old law',
            'key': 'law',
            'content': 'Repealed',
            'enabled': false,
          },
        ],
      });
      final w = facade.list().firstWhere((m) => m['name'] == 'Cindermaw');
      expect(w['entryCount'], 2);
      expect(w['enabledEntryCount'], 1);
    });

    test('list and detail carry parentWorldId; roots are null', () async {
      final rootId = await createWorld({
        'name': 'Bletchport',
        'description': 'A town',
      });
      final list = facade.list();
      final root = list.firstWhere((m) => m['id'] == rootId);
      expect(root.containsKey('parentWorldId'), isTrue);
      expect(root['parentWorldId'], isNull);
      expect(root['isModelMade'], isFalse);
      expect(facade.detail('Bletchport')!['parentWorldId'], isNull);
    });

    test('save sets a parent; the child lists and details under it', () async {
      final rootId = await createWorld({'name': 'Bletchport'});
      final childId = await createWorld({
        'name': 'The Lighthouse',
        'parentWorldId': rootId,
        'climateEnabled': false,
      });
      final child = facade.list().firstWhere((m) => m['id'] == childId);
      expect(child['parentWorldId'], rootId);
      expect(facade.detail('The Lighthouse')!['parentWorldId'], rootId);
    });

    test(
      'an unknown parent is refused and does not stick in the cache',
      () async {
        final id = await createWorld({'name': 'Orphan'});
        await expectLater(
          facade.save({
            'name': 'Orphan',
            'id': id,
            'parentWorldId': 'no-such-world',
          }),
          throwsA(isA<StateError>()),
        );
        // The cache object must have rolled its parent back (review #592's
        // honesty rule, enforced on the relay side too).
        expect(facade.detail('Orphan')!['parentWorldId'], isNull);
      },
    );

    test(
      'parentCandidates is the one law: depth cap and cycle excluded',
      () async {
        final earthId = await createWorld({'name': 'Earth'});
        final townId = await createWorld({
          'name': 'Bletchfield',
          'parentWorldId': earthId,
        });
        final roomId = await createWorld({
          'name': 'Back Room',
          'parentWorldId': townId,
        });
        // Editing the depth-2 room: Earth and the town are candidates, but
        // never its own descendant, and a root stays offered.
        final ids = facade.parentCandidates(roomId).map((c) => c['id']).toSet();
        expect(ids, containsAll(<String>[earthId, townId]));
        expect(ids.contains(roomId), isFalse);
        // A depth-1 place proposing itself under its own child would ring:
        // the room is not offered the child it parents deeper than the cap.
        final townCands = facade
            .parentCandidates(townId)
            .map((c) => c['id'])
            .toSet();
        expect(townCands.contains(roomId), isFalse, reason: 'cycle');
        expect(townCands, contains(earthId));
      },
    );

    // Review #596 BLOCKERS/MAJOR: the shared cache World must roll back
    // EVERY field a refused write touched, and refusals must speak.
    test('a refused save rolls back every field it touched', () async {
      final id = await createWorld({
        'name': 'Aurora',
        'description': 'Original prose.',
        'coverImage': 'data:old',
      });
      await expectLater(
        facade.save({
          'id': id,
          'name': 'Aurora',
          'description': 'Ghost edit.',
          'coverImage': 'data:new',
          'parentWorldId': 'no-such-world',
        }),
        throwsA(isA<StateError>()),
      );
      final d = facade.detail('Aurora')!;
      expect(d['description'], 'Original prose.', reason: 'no ghost edit');
      expect(d['coverImage'], 'data:old');
      expect(d['parentWorldId'], isNull);
    });

    test('rename onto a taken name reports the collision sentence', () async {
      final alphaId = await createWorld({'name': 'Alpha'});
      await createWorld({'name': 'Beta'});
      await expectLater(
        facade.save({'id': alphaId, 'name': 'Beta', 'originalName': 'Alpha'}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('already exists'),
          ),
        ),
      );
      // Alpha survives under its own name, untouched.
      expect(facade.detail('Alpha'), isNotNull);
    });

    test('a lorebook rebuild is rolled back with the rest', () async {
      final id = await createWorld({
        'name': 'Keeper',
        'entries': [
          {'name': 'Old', 'key': 'old', 'content': 'kept'},
        ],
      });
      await expectLater(
        facade.save({
          'id': id,
          'name': 'Keeper',
          'parentWorldId': 'nope',
          'entries': [
            {'name': 'New', 'key': 'new', 'content': 'ghost'},
          ],
        }),
        throwsA(isA<StateError>()),
      );
      final d = facade.detail('Keeper')!;
      final entries = (d['entries'] as List).cast<Map>();
      expect(entries.single['name'], 'Old', reason: 'lore rolled back too');
    });

    // Slice 5 (envelope ride-along): the Stoop card shows "N places"
    // and the chat panel names the weather's author. Additive keys —
    // red until the DTOs carry them.
    test('list and detail carry locationCount and climateAuthorId', () async {
      final rootId = await createWorld({
        'name': 'Calderis',
        'climateEnabled': true,
        'biomeId': 'temperate',
      });
      await createWorld({
        'name': 'Salt Docks',
        'climateEnabled': false,
        'parentWorldId': rootId,
      });
      await createWorld({
        'name': 'Gull Cage',
        'climateEnabled': false,
        'parentWorldId': rootId,
      });
      await createWorld({'name': 'Quiet Attic', 'climateEnabled': false});

      final rows = {for (final m in facade.list()) m['name'] as String: m};
      expect(rows['Calderis']!['locationCount'], 2);
      expect(
        rows['Calderis']!['climateAuthorId'],
        rootId,
        reason: 'a climate root authors its own weather',
      );
      expect(rows['Salt Docks']!['locationCount'], 0);
      expect(
        rows['Quiet Attic']!['climateAuthorId'],
        isNull,
        reason: 'a lore-only chain has no climate author',
      );

      final d = facade.detail('Salt Docks')!;
      expect(d['climateAuthorId'], rootId, reason: 'inherited upstream');
      expect(d['locationCount'], 0);
    });

    test(
      'coverFor serves a saved place picture by id, nothing otherwise',
      () async {
        final cover = encodeWorldCoverDataUrl(
          img.encodePng(img.Image(width: 4, height: 4)),
        )!;
        expect(
          await facade.save({'name': 'Tea Rooms', 'coverImage': cover}),
          isTrue,
        );
        expect(await facade.save({'name': 'Bare'}), isTrue);
        final tea = facade.list().firstWhere((m) => m['name'] == 'Tea Rooms');
        final bare = facade.list().firstWhere((m) => m['name'] == 'Bare');
        final served = facade.coverFor(tea['id'] as String);
        expect(served?.contentType, 'image/jpeg');
        expect(served?.bytes, decodeWorldCoverBytes(cover));
        expect(facade.coverFor(bare['id'] as String), isNull);
        expect(facade.coverFor('no-such-place'), isNull);
      },
    );
  });
}
