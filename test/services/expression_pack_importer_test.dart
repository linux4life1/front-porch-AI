// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/expression_pack_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// Mock path_provider so StorageService can resolve
/// getApplicationDocumentsDirectory() without a real platform channel.
void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_pack_test_').path;
        }
        return null;
      });
}

ExpressionSlot _doneSlot(
  String emotion, {
  bool keep = true,
  List<int> bytes = const [1, 2, 3],
}) {
  final s = ExpressionSlot(emotion);
  s.state = ExpressionSlotState.done;
  s.bytes = Uint8List.fromList(bytes);
  s.keep = keep;
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExpressionPackImporter — in-memory DB integration', () {
    late AppDatabase db;
    late StorageService storage;
    late CharacterRepository repo;
    late String charId;

    Future<void> waitUntilNotLoading(CharacterRepository r) async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (r.isLoading) {
        if (DateTime.now().isAfter(deadline)) {
          fail('loadCharacters did not settle');
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    setUp(() async {
      _setupPathProviderMock();
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting();
      // Ensure avatar_images exists (in-memory DB migrations may skip it —
      // same workaround as avatar_repository_test.dart).
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
      charId = await db.insertCharacterReturningId(
        CharactersCompanion(
          name: const Value('Pack Test'),
          description: const Value('expression pack import target'),
        ),
      );
      storage = StorageService();
      await storage.initialized;
      repo = CharacterRepository(db, storage);
      await Future<void>.delayed(Duration.zero);
      await waitUntilNotLoading(repo);
    });

    tearDown(() async {
      await db.close();
    });

    test('imports done+kept slots only, lowercase labels, flips toggle', () async {
      expect(storage.expressionEnabled, isFalse);
      final slots = [
        _doneSlot('joy'),
        _doneSlot('anger'),
        _doneSlot('fear', keep: false), // unchecked → skipped
        ExpressionSlot('sadness'), // never generated → skipped
      ];
      final imported = await ExpressionPackImporter.importPack(
        repository: repo,
        storage: storage,
        characterDbId: charId,
        characterName: 'Pack Test',
        slots: slots,
      );
      expect(imported, 2);
      final avatars = await repo.getAvatarImages(charId);
      expect(avatars, hasLength(2));
      expect(avatars.map((a) => a.label).toSet(), {'joy', 'anger'});
      expect(storage.expressionEnabled, isTrue);
    });

    test('returns 0 and leaves the toggle off when nothing is kept', () async {
      final imported = await ExpressionPackImporter.importPack(
        repository: repo,
        storage: storage,
        characterDbId: charId,
        characterName: 'Pack Test',
        slots: [_doneSlot('joy', keep: false), ExpressionSlot('anger')],
      );
      expect(imported, 0);
      expect(await repo.getAvatarImages(charId), isEmpty);
      expect(storage.expressionEnabled, isFalse);
    });

    test('replaceSameLabel removes same-label avatars case-insensitively', () async {
      await repo.addAvatar(charId, 'Pack Test', Uint8List.fromList([9]), 'Joy');
      await repo.addAvatar(
        charId,
        'Pack Test',
        Uint8List.fromList([9]),
        'anger',
      );
      final before = await repo.getAvatarImages(charId);
      expect(before, hasLength(2));
      final oldJoyId = before.firstWhere((a) => a.label == 'Joy').id;

      final imported = await ExpressionPackImporter.importPack(
        repository: repo,
        storage: storage,
        characterDbId: charId,
        characterName: 'Pack Test',
        slots: [_doneSlot('joy', bytes: const [4, 5, 6])],
      );
      expect(imported, 1);
      final after = await repo.getAvatarImages(charId);
      // Old 'Joy' replaced by the new lowercase 'joy'; 'anger' untouched.
      expect(after, hasLength(2));
      final joys = after.where((a) => a.label?.toLowerCase() == 'joy').toList();
      expect(joys, hasLength(1));
      expect(joys.single.id, isNot(oldJoyId));
      expect(joys.single.label, 'joy');
      expect(after.any((a) => a.label == 'anger'), isTrue);
    });

    test('replaceSameLabel=false keeps existing same-label avatars', () async {
      await repo.addAvatar(charId, 'Pack Test', Uint8List.fromList([9]), 'joy');
      final imported = await ExpressionPackImporter.importPack(
        repository: repo,
        storage: storage,
        characterDbId: charId,
        characterName: 'Pack Test',
        slots: [_doneSlot('joy')],
        replaceSameLabel: false,
      );
      expect(imported, 1);
      final after = await repo.getAvatarImages(charId);
      expect(after.where((a) => a.label == 'joy'), hasLength(2));
    });
  });
}
