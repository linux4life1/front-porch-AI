// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Web facade parity for per-world climateEnabled (lorebook-only worlds).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/facade/world_facade.dart';
import 'package:front_porch_ai/services/world_repository.dart';

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

  test(
    'save/detail/list expose climateEnabled; off skips biome requirement',
    () async {
      expect(
        await facade.save({
          'name': 'Soul Society',
          'description': 'The afterlife realm of departed souls...',
          'climateEnabled': false,
          'entries': [
            {
              'name': 'Gotei 13',
              'key': 'Gotei 13',
              'content': 'Thirteen court guard divisions.',
            },
          ],
        }),
        isTrue,
      );

      final listed = facade.list().firstWhere(
        (m) => m['name'] == 'Soul Society',
      );
      expect(listed['climateEnabled'], isFalse);
      expect(listed['biomeId'], isNull);

      final detail = facade.detail('Soul Society')!;
      expect(detail['climateEnabled'], isFalse);
      expect(detail['biomeId'], isNull);
      expect(detail['description'], contains('afterlife'));
      expect((detail['entries'] as List), hasLength(1));
    },
  );

  test(
    'save with climate off ignores leftover atmosphere/gravity payload',
    () async {
      expect(
        await facade.save({
          'name': 'Soul Society',
          'climateEnabled': false,
          'atmosphere': 'unbreathable',
          'gravity': 'low',
        }),
        isTrue,
      );
      final detail = facade.detail('Soul Society')!;
      expect(detail['climateEnabled'], isFalse);
      expect(detail['atmosphere'], 'breathable');
      expect(detail['gravity'], 'earth');
    },
  );

  test(
    'importWorld of climate-off .fpworld with no biome keeps the flag',
    () async {
      expect(
        await facade.importWorld({
          'formatVersion': 1,
          'id': 'ss-pkg',
          'name': 'Soul Society',
          'description': 'Bookshelf world.',
          'climate_enabled': false,
          'lorebook': {
            'entries': [
              {
                'keys': ['Seireitei'],
                'content': 'The walled city of souls.',
              },
            ],
          },
        }),
        isTrue,
      );
      final imported = facade.detail(
        facade.list().firstWhere((m) => m['name'] == 'Soul Society')['id']
            as String,
      )!;
      expect(imported['climateEnabled'], isFalse);
    },
  );

  test(
    'exportWorld carries climate_enabled false and no climate biome',
    () async {
      await facade.save({
        'name': 'Soul Society',
        'climateEnabled': false,
        'entries': [
          {'name': 'Squad 4', 'key': 'Squad 4', 'content': 'Medical relief.'},
        ],
      });
      final exported = facade.exportWorld('Soul Society')!;
      expect(exported['climate_enabled'], isFalse);
      expect(exported.containsKey('biome'), isFalse);
      expect(exported.containsKey('place_traits'), isFalse);
    },
  );
}
