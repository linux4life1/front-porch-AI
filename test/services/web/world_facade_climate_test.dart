// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Web facade parity for per-world climateEnabled (lorebook-only worlds).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
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
      expect(detail.containsKey('biomeId'), isFalse);
      expect(detail.containsKey('biome'), isFalse);
      expect(detail.containsKey('atmosphere'), isFalse);
      expect(detail.containsKey('gravity'), isFalse);
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
      expect(detail.containsKey('biome'), isFalse);
      expect(detail.containsKey('biomeId'), isFalse);
      expect(detail.containsKey('atmosphere'), isFalse);
      expect(detail.containsKey('gravity'), isFalse);

      // Payload was ignored: leftover defaults still sit at rest, visible
      // again only after climate is re-enabled without atmosphere/gravity.
      expect(
        await facade.save({'name': 'Soul Society', 'climateEnabled': true}),
        isTrue,
      );
      final on = facade.detail('Soul Society')!;
      expect(on['atmosphere'], 'breathable');
      expect(on['gravity'], 'earth');
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

  test(
    'chatPlaces omits biomeId for climate-off worlds (no temperate)',
    () async {
      late ChatService chat;
      final storage = StorageService();
      await storage.setRootPath(
        Directory.systemTemp.createTempSync('fpai_chatplaces_').path,
      );
      final repo = WorldRepository(storage, db);
      await repo.loadWorlds();
      chat = ChatService(
        KoboldService(storage),
        UserPersonaService(db),
        storage,
        repo,
      )..setDatabase(db);
      addTearDown(() {
        chat.dispose();
      });
      final wired = WorldFacade(repo, null, chat);

      final template = Map<String, dynamic>.from(
        wired.climates().firstWhere((c) => c['id'] == 'temperate')['template']
            as Map,
      );
      template['id'] = 'custom';
      template['seasonLabels'] = {'summer': 'High Sun'};

      expect(
        await wired.save({
          'name': 'Soul Society',
          'climateEnabled': true,
          'biomeId': 'custom',
          'biome': template,
          'entries': [
            {
              'name': 'Seireitei',
              'key': 'Seireitei',
              'content': 'Walled city.',
            },
          ],
        }),
        isTrue,
      );
      // Toggle off; leftover biomeJson stays at rest (do not wipe).
      expect(
        await wired.save({'name': 'Soul Society', 'climateEnabled': false}),
        isTrue,
      );
      expect(
        await wired.save({
          'name': 'Karakura',
          'climateEnabled': true,
          'biomeId': 'temperate',
        }),
        isTrue,
      );
      expect(
        await wired.save({
          'name': 'Hueco Mundo',
          'climateEnabled': true,
          'biomeId': 'custom',
          'biome': template,
        }),
        isTrue,
      );

      await chat.setActiveCharacter(
        CharacterCard(
          name: 'Alice',
          description: 'Climate-off chatPlaces pin.',
          firstMessage: 'The porch light hums.',
        )..dbId = 'char-climate-alice',
      );
      expect(chat.currentSessionId, isNotNull);

      final offId =
          wired.list().firstWhere((m) => m['name'] == 'Soul Society')['id']
              as String;
      final onId =
          wired.list().firstWhere((m) => m['name'] == 'Karakura')['id']
              as String;
      final customOnId =
          wired.list().firstWhere((m) => m['name'] == 'Hueco Mundo')['id']
              as String;

      final result = await wired.setChatPlaces([offId, onId, customOnId]);
      expect(result['ok'], isTrue);
      final places = (result['places'] as List).cast<Map<String, dynamic>>();
      expect(places, hasLength(3));

      final off = places.firstWhere((p) => p['id'] == offId);
      expect(off.containsKey('biomeId'), isFalse);
      expect(off['biomeId'], isNot('temperate'));
      expect(off['hasCustomClimate'], isFalse);

      final on = places.firstWhere((p) => p['id'] == onId);
      expect(on['biomeId'], 'temperate');
      expect(on['hasCustomClimate'], isFalse);

      final customOn = places.firstWhere((p) => p['id'] == customOnId);
      expect(customOn['biomeId'], 'custom');
      expect(customOn['hasCustomClimate'], isTrue);

      final optionIds = (result['climateOptions'] as List)
          .map((e) => (e as Map)['id'])
          .toList();
      expect(optionIds, isNot(contains('world:$offId')));
      expect(optionIds, contains('world:$customOnId'));
      expect(optionIds, isNot(contains('world:$onId')));
    },
  );
}
