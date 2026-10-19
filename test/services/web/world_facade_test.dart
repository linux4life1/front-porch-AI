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
      expect(
        await facade.save({
          'name': 'Solaria',
          'originalName': 'Solaria',
          'biomeId': 'custom',
          'biome': template,
        }),
        isFalse,
      );
      expect(
        facade.climateErrors(template).join(' '),
        contains('cannot overlap'),
      );
    });
  });
}
