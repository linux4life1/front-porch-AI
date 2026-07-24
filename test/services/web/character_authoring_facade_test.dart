// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Backend E2E for the web Avatar Gallery: drives CharacterAuthoringFacade over a
// real in-memory repo + temp storage (no HTTP server / auth needed) to prove the
// NEW look plumbing: addLook writes to looks/ (isLook), addAvatar stays an
// expression (avatars/), avatarFile serves a LOOK from looks/ (was avatars-only),
// and the ★ favorite round-trips through avatars().isFavorite.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/facade/character_authoring_facade.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_facade_test_').path;
        }
        return null;
      });
}

final _png = Uint8List.fromList([1, 2, 3, 4]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CharacterAuthoringFacade — web Avatar Gallery backend', () {
    late AppDatabase db;
    late StorageService storage;
    late CharacterRepository repo;
    late CharacterAuthoringFacade facade;
    late String charId;

    Future<void> waitSettled() async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (repo.isLoading) {
        if (DateTime.now().isAfter(deadline)) fail('repo did not settle');
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    setUp(() async {
      _setupPathProviderMock();
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting();
      try {
        await db.customStatement(
          'CREATE TABLE IF NOT EXISTS avatar_images ('
          'id TEXT NOT NULL, character_id TEXT NOT NULL, filename TEXT NOT NULL, '
          'label TEXT, display_order INTEGER NOT NULL DEFAULT 0, '
          'created_at INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (id))',
        );
      } catch (_) {}
      charId = await db.insertCharacterReturningId(
        const CharactersCompanion(
          name: Value('Gallery Test'),
          description: Value('web avatar gallery target'),
        ),
      );
      storage = StorageService();
      await storage.initialized;
      repo = CharacterRepository(db, storage);
      await Future<void>.delayed(Duration.zero);
      await waitSettled();
      facade = CharacterAuthoringFacade(repo, storage);
    });

    tearDown(() async => db.close());

    test('addLook → looks/ (isLook); addAvatar → an expression (label, !isLook)',
        () async {
      expect(await facade.addLook(charId, _png), isTrue);
      expect(await facade.addAvatar(charId, _png, 'happy'), isTrue);

      final avatars = await facade.avatars(charId);
      expect(avatars, hasLength(2));
      final look = avatars.firstWhere((a) => a['isLook'] == true);
      final expr = avatars.firstWhere((a) => a['isLook'] == false);
      expect(expr['label'], 'happy');
      expect(look['label'], ''); // looks carry no user label in the payload
    });

    test('avatarFile serves a LOOK from looks/ (was avatars/-only)', () async {
      await facade.addLook(charId, _png);
      final lookId =
          (await facade.avatars(charId)).firstWhere((a) => a['isLook'] == true)['id']
              as String;
      final file = await facade.avatarFile(charId, lookId);
      expect(file, isNotNull, reason: 'a look must resolve + serve');
      expect(file!.path.contains('${Platform.pathSeparator}looks${Platform.pathSeparator}'),
          isTrue,
          reason: 'served from looks/, not avatars/: ${file.path}');
      expect(file.existsSync(), isTrue);
    });

    test('an EXPRESSION still serves from avatars/', () async {
      await facade.addAvatar(charId, _png, 'sad');
      final id =
          (await facade.avatars(charId)).first['id'] as String;
      final file = await facade.avatarFile(charId, id);
      expect(file, isNotNull);
      expect(
        file!.path.contains('${Platform.pathSeparator}avatars${Platform.pathSeparator}'),
        isTrue,
        reason: file.path,
      );
    });

    test('★ favorite round-trips through avatars().isFavorite (set + clear)',
        () async {
      await facade.addLook(charId, _png);
      final lookId =
          (await facade.avatars(charId)).first['id'] as String;

      expect(await facade.setFavorite(charId, lookId), isTrue);
      var avatars = await facade.avatars(charId);
      expect(avatars.firstWhere((a) => a['id'] == lookId)['isFavorite'], isTrue);

      expect(await facade.setFavorite(charId, ''), isTrue); // clear → portrait
      avatars = await facade.avatars(charId);
      expect(avatars.firstWhere((a) => a['id'] == lookId)['isFavorite'], isFalse);
    });
  });
}
