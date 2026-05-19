// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
    if (methodCall.method == 'getApplicationDocumentsDirectory') {
      return Directory.systemTemp.path;
    }
    return null;
  });

  SharedPreferences.setMockInitialValues({});

  group('Database — avatar schema', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting();
      // Warm up: trigger database initialization
      await db.select(db.characters).get();
      // Ensure avatar_images table exists (may not be created by in-memory DB migrations)
      try {
        await db.customStatement(
          'CREATE TABLE IF NOT EXISTS avatar_images ('
          'id TEXT NOT NULL, '
          'character_id TEXT NOT NULL, '
          'filename TEXT NOT NULL, '
          'label TEXT, '
          'display_order INTEGER NOT NULL DEFAULT 0, '
          'created_at INTEGER NOT NULL DEFAULT 0, '
          'PRIMARY KEY (id))',
        );
      } catch (_) {}
    });

    tearDown(() async {
      await db.close();
    });

    test('schema version is 25', () {
      expect(db.schemaVersion, 25);
    });

    test('characters table has prime_avatar_index column', () async {
      final charId = 'prime-test-${DateTime.now().millisecondsSinceEpoch}';
      await db.insertCharacter(
        CharactersCompanion(
          id: Value(charId),
          name: Value('Prime Test'),
          imagePath: Value('test.png'),
        ),
      );

      final character = await db.getCharacterById(charId);
      expect(character.primeAvatarIndex, 1);

      await db.updatePrimeAvatarIndex(charId, 3);
      final updated = await db.getCharacterById(charId);
      expect(updated.primeAvatarIndex, 3);
    });

    test('CRUD operations on avatars', () async {
      final charId = 'crud-test-${DateTime.now().millisecondsSinceEpoch}';
      await db.insertCharacter(
        CharactersCompanion(
          id: Value(charId),
          name: Value('CRUD Test'),
          imagePath: Value('test.png'),
        ),
      );

      final avatarId = 'crud-aid-${DateTime.now().millisecondsSinceEpoch}';

      await db.insertAvatar(
        AvatarImagesCompanion(
          id: Value(avatarId),
          characterId: Value(charId),
          filename: Value('avatar_1.png'),
          label: Value('casual'),
          displayOrder: Value(0),
        ),
      );

      var avatars = await db.getAvatarImagesByCharacterId(charId);
      expect(avatars.length, 1);
      expect(avatars[0].id, avatarId);
      expect(avatars[0].label, 'casual');

      await db.updateAvatarLabel(avatarId, 'formal');
      avatars = await db.getAvatarImagesByCharacterId(charId);
      expect(avatars[0].label, 'formal');

      await db.deleteAvatar(avatarId);
      avatars = await db.getAvatarImagesByCharacterId(charId);
      expect(avatars, isEmpty);
    });

    test('avatars ordered by displayOrder', () async {
      final charId = 'order-test-${DateTime.now().millisecondsSinceEpoch}';
      await db.insertCharacter(
        CharactersCompanion(
          id: Value(charId),
          name: Value('Order Test'),
          imagePath: Value('test.png'),
        ),
      );

      final base = 'ord-${DateTime.now().millisecondsSinceEpoch}';
      await db.insertAvatar(
        AvatarImagesCompanion(
          id: Value('$base-a'),
          characterId: Value(charId),
          filename: Value('avatar_z.png'),
          displayOrder: Value(2),
        ),
      );
      await db.insertAvatar(
        AvatarImagesCompanion(
          id: Value('$base-b'),
          characterId: Value(charId),
          filename: Value('avatar_a.png'),
          displayOrder: Value(0),
        ),
      );
      await db.insertAvatar(
        AvatarImagesCompanion(
          id: Value('$base-c'),
          characterId: Value(charId),
          filename: Value('avatar_m.png'),
          displayOrder: Value(1),
        ),
      );

      final avatars = await db.getAvatarImagesByCharacterId(charId);
      expect(avatars.length, 3);
      expect(avatars[0].filename, 'avatar_a.png');
      expect(avatars[1].filename, 'avatar_m.png');
      expect(avatars[2].filename, 'avatar_z.png');
    });
  });

  group('CharacterCard — avatar fields', () {
    test('primeAvatarIndex defaults to 1', () {
      final card = CharacterCard(name: 'Test');
      expect(card.primeAvatarIndex, 1);
    });

    test('avatarImages defaults to null', () {
      final card = CharacterCard(name: 'Test');
      expect(card.avatarImages, equals(null));
    });
  });
}
