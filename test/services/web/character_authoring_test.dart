// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/facade/character_authoring_facade.dart';
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

  group('CharacterAuthoringFacade', () {
    late AppDatabase db;
    late StorageService storage;
    late CharacterFacade chars;
    late CharacterAuthoringFacade auth;
    late CharacterRepository repo;
    late String id;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting();
      await db.select(db.characters).get();
      storage = StorageService();
      await storage.setRootPath(
        Directory.systemTemp.createTempSync('fpai_root_').path,
      );
      repo = CharacterRepository(db, storage);
      chars = CharacterFacade(db, storage, null, null, repo);
      auth = CharacterAuthoringFacade(repo, storage);
      final created = await chars.create({'name': 'Edith'});
      id = created!['id'] as String;
    });

    tearDown(() => db.close());

    test('avatar add / list / prime / remove round-trip', () async {
      expect(await auth.avatars(id), isEmpty);

      expect(await auth.addAvatar(id, [1, 2, 3, 4], 'happy'), isTrue);
      var list = await auth.avatars(id);
      expect(list.length, 1);
      expect(list.first['label'], 'happy');
      expect(list.first['isPrime'], isTrue); // first avatar is prime by default

      expect(await auth.addAvatar(id, [5, 6, 7, 8], 'sad'), isTrue);
      list = await auth.avatars(id);
      expect(list.length, 2);
      final second = list.firstWhere((a) => a['label'] == 'sad');
      expect(second['isPrime'], isFalse);

      expect(await auth.setPrime(id, second['id'] as String), isTrue);
      list = await auth.avatars(id);
      expect(list.firstWhere((a) => a['label'] == 'sad')['isPrime'], isTrue);

      // The image file is resolvable for serving.
      expect(await auth.avatarFile(id, second['id'] as String), isNotNull);

      expect(await auth.removeAvatar(id, second['id'] as String), isTrue);
      expect((await auth.avatars(id)).length, 1);
    });

    test('delete removes the character from the library', () async {
      expect(await auth.delete(id), isTrue);
      final listed = await chars.list();
      expect(listed.any((m) => m['id'] == id), isFalse);
    });

    test(
      'attachPortrait writes a new portrait and re-embeds the card',
      () async {
        final png = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
          'z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==',
        );
        expect(await auth.attachPortrait(id, png), isTrue);
        final card = await repo.getCharacterCardById(id);
        expect(card?.imagePath, isNotNull);
        expect(File(card!.imagePath!).existsSync(), isTrue);
        // The card still round-trips through its PNG after the re-embed.
        expect((await repo.getCharacterCardById(id))?.name, 'Edith');
      },
    );

    test('attachPortrait on an unknown character is false', () async {
      expect(await auth.attachPortrait('nope', [1]), isFalse);
    });

    test(
      'setAvatarLabel re-tags an expression, refuses a look and junk',
      () async {
        final png = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
          'z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==',
        );
        await auth.attachPortrait(id, png);
        await auth.addAvatar(id, [1, 2, 3, 4], 'joy');
        await auth.addLook(id, png);
        final list = await auth.avatars(id);
        final expression = list.firstWhere((a) => a['isLook'] == false);
        final look = list.firstWhere((a) => a['isLook'] == true);
        expect(
          await auth.setAvatarLabel(id, expression['id'] as String, 'anger'),
          isTrue,
        );
        expect(
          (await auth.avatars(
            id,
          )).firstWhere((a) => a['id'] == expression['id'])['label'],
          'anger',
        );
        expect(
          await auth.setAvatarLabel(
            id,
            expression['id'] as String,
            'not-a-label',
          ),
          isFalse,
        );
        expect(
          await auth.setAvatarLabel(id, look['id'] as String, 'joy'),
          isFalse,
        );
        expect(await auth.setAvatarLabel(id, 'nope', 'joy'), isFalse);
      },
    );

    test(
      'importExpressionZip adds tagged images, counts the rest, flips the engine',
      () async {
        expect(storage.expressionSettings.expressionEnabled, isFalse);
        final archive = Archive()
          ..addFile(ArchiveFile('joy.png', 4, [1, 2, 3, 4]))
          ..addFile(ArchiveFile('sadness-1.png', 4, [5, 6, 7, 8]))
          ..addFile(ArchiveFile('sunset.png', 4, [9, 9, 9, 9]))
          ..addFile(ArchiveFile.string('readme.txt', 'not an image'));
        final zip = ZipEncoder().encode(archive);
        final result = await auth.importExpressionZip(id, zip);
        expect(result.added, 2);
        expect(result.unrecognized, 1);
        final list = await auth.avatars(id);
        expect(
          list.map((a) => a['label']),
          containsAll(<String>['joy', 'sadness']),
        );
        expect(storage.expressionSettings.expressionEnabled, isTrue);
      },
    );

    test('importExpressionZip on an unknown character adds nothing', () async {
      final zip = ZipEncoder().encode(
        Archive()..addFile(ArchiveFile('joy.png', 4, [1, 2, 3, 4])),
      );
      final result = await auth.importExpressionZip('nope', zip);
      expect(result.added, 0);
      expect(result.unrecognized, 0);
    });

    test('avatar ops on an unknown character return false', () async {
      expect(await auth.addAvatar('nope', [1], null), isFalse);
      expect(await auth.removeAvatar('nope', 'x'), isFalse);
      expect(await auth.setPrime('nope', 'x'), isFalse);
    });
  });
}
