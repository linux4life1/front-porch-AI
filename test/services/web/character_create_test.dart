// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
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

    test(
      'create compact-pairs dirty empty greet so furious does not land on Get out',
      () async {
        final res = await facade.create({
          'name': 'PairCreate',
          'firstMessage': 'Come in.',
          'alternateGreetings': ['', 'Get out.'],
          'greetingSeeds': [
            {'characterEmotion': 'furious'},
          ],
        });
        expect(res, isNotNull);
        final card = facade.cardByDbId(res!['id'] as String);
        expect(card, isNotNull);
        expect(card!.alternateGreetings, ['Get out.']);
        expect(
          card.frontPorchExtensions!.greetingSeeds,
          isEmpty,
          reason:
              "['', 'Get out.']+[furious] must not load furious onto Get out",
        );
        expect(
          greetingOverlayAt(card.frontPorchExtensions!.greetingSeeds, 1),
          isNull,
        );
      },
    );

    test(
      'create JSON-null greet slot keeps furious on Get out',
      () async {
        final res = await facade.create({
          'name': 'NullSlotCreate',
          'firstMessage': 'Come in.',
          'alternateGreetings': [null, 'Get out.'],
          'greetingSeeds': [
            null,
            {'characterEmotion': 'furious'},
          ],
        });
        expect(res, isNotNull);
        final card = facade.cardByDbId(res!['id'] as String)!;
        expect(card.alternateGreetings, ['Get out.']);
        expect(
          card.frontPorchExtensions!.greetingSeeds.single!.characterEmotion,
          'furious',
        );
      },
    );

    test(
      'update compact-pairs dirty empty greet so furious does not land on Get out',
      () async {
        final res = await facade.create({'name': 'PairUpdate'});
        final id = res!['id'] as String;
        expect(
          await facade.update(id, {
            'alternateGreetings': ['', 'Get out.'],
            'greetingSeeds': [
              {'characterEmotion': 'furious'},
            ],
          }),
          isTrue,
        );
        final card = facade.cardByDbId(id)!;
        expect(card.alternateGreetings, ['Get out.']);
        expect(
          card.frontPorchExtensions!.greetingSeeds,
          isEmpty,
          reason:
              "['', 'Get out.']+[furious] must not load furious onto Get out",
        );
        expect(
          greetingOverlayAt(card.frontPorchExtensions!.greetingSeeds, 1),
          isNull,
        );
      },
    );

    test(
      'update JSON-null greet slot keeps furious on Get out',
      () async {
        final res = await facade.create({'name': 'NullSlotUpdate'});
        final id = res!['id'] as String;
        expect(
          await facade.update(id, {
            'alternateGreetings': [null, 'Get out.'],
            'greetingSeeds': [
              null,
              {'characterEmotion': 'furious'},
            ],
          }),
          isTrue,
        );
        final card = facade.cardByDbId(id)!;
        expect(card.alternateGreetings, ['Get out.']);
        expect(
          card.frontPorchExtensions!.greetingSeeds.single!.characterEmotion,
          'furious',
        );
      },
    );

    test(
      'update dirty alts-only POST drops leftover [furious] off Get out',
      () async {
        final res = await facade.create({
          'name': 'AltsOnlyUpdate',
          'firstMessage': 'Come in.',
          'alternateGreetings': ['Stay.'],
          'greetingSeeds': [
            {'characterEmotion': 'furious'},
          ],
        });
        final id = res!['id'] as String;
        expect(
          facade
              .cardByDbId(id)!
              .frontPorchExtensions!
              .greetingSeeds
              .single!
              .characterEmotion,
          'furious',
        );
        expect(
          await facade.update(id, {
            'alternateGreetings': ['', 'Get out.'],
          }),
          isTrue,
        );
        final card = facade.cardByDbId(id)!;
        expect(card.alternateGreetings, ['Get out.']);
        expect(
          card.frontPorchExtensions!.greetingSeeds,
          isEmpty,
          reason:
              'dirty alts-only + existing [furious] must not load furious onto Get out',
        );
        expect(
          greetingOverlayAt(card.frontPorchExtensions!.greetingSeeds, 1),
          isNull,
          reason: 'Get out overlay is not leftover furious',
        );
      },
    );

    test(
      'update explicit empty greetingSeeds stays authored-empty',
      () async {
        final res = await facade.create({
          'name': 'AuthoredEmptySeeds',
          'firstMessage': 'Come in.',
          'alternateGreetings': ['Stay.'],
          'greetingSeeds': [
            {'characterEmotion': 'furious'},
          ],
        });
        final id = res!['id'] as String;
        expect(
          facade
              .cardByDbId(id)!
              .frontPorchExtensions!
              .greetingSeeds
              .single!
              .characterEmotion,
          'furious',
        );

        expect(
          await facade.update(id, {
            'alternateGreetings': ['', 'Get out.'],
            'greetingSeeds': [],
          }),
          isTrue,
        );
        final dirty = facade.cardByDbId(id)!;
        expect(dirty.alternateGreetings, ['Get out.']);
        expect(
          dirty.frontPorchExtensions!.greetingSeeds,
          isEmpty,
          reason:
              'explicit empty greetingSeeds is authored-empty, not leftover furious',
        );
        expect(
          greetingOverlayAt(dirty.frontPorchExtensions!.greetingSeeds, 1),
          isNull,
        );

        expect(
          await facade.update(id, {
            'alternateGreetings': ['Stay.'],
            'greetingSeeds': [
              {'characterEmotion': 'furious'},
            ],
          }),
          isTrue,
        );
        expect(
          facade
              .cardByDbId(id)!
              .frontPorchExtensions!
              .greetingSeeds
              .single!
              .characterEmotion,
          'furious',
        );
        expect(
          await facade.update(id, {
            'greetingSeeds': [],
          }),
          isTrue,
        );
        final emptied = facade.cardByDbId(id)!;
        expect(emptied.alternateGreetings, ['Stay.']);
        expect(
          emptied.frontPorchExtensions!.greetingSeeds,
          isEmpty,
          reason: 'explicit empty is authored-empty, not dropped as omit',
        );
      },
    );

    test(
      'update omitted alts keep base seeds',
      () async {
        final res = await facade.create({
          'name': 'KeepBaseSeeds',
          'firstMessage': 'Come in.',
          'alternateGreetings': ['Stay.'],
          'greetingSeeds': [
            {'characterEmotion': 'furious'},
          ],
        });
        final id = res!['id'] as String;
        expect(
          await facade.update(id, {
            'trustLevel': 7,
            'name': 'KeepBaseSeeds-renamed',
          }),
          isTrue,
        );
        final card = facade.cardByDbId(id)!;
        expect(card.name, 'KeepBaseSeeds-renamed');
        expect(card.alternateGreetings, ['Stay.']);
        expect(
          card.frontPorchExtensions!.greetingSeeds.single!.characterEmotion,
          'furious',
          reason: 'omitted alts must not wipe leftover base seeds',
        );
        expect(card.frontPorchExtensions!.trustLevel, 7);
      },
    );
  });
}
