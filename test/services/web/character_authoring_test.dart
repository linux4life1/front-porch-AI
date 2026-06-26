// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

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
    late String id;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting();
      await db.select(db.characters).get();
      storage = StorageService();
      await storage.setRootPath(
        Directory.systemTemp.createTempSync('fpai_root_').path,
      );
      final repo = CharacterRepository(db, storage);
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

    test('avatar ops on an unknown character return false', () async {
      expect(await auth.addAvatar('nope', [1], null), isFalse);
      expect(await auth.removeAvatar('nope', 'x'), isFalse);
      expect(await auth.setPrime('nope', 'x'), isFalse);
    });
  });
}
