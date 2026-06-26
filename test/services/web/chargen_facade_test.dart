// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/character_card.dart';
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

  // The AI chargen engine itself (CharacterGenService) needs a live LLM, so the
  // unit-testable seam is the shared persist path the chargen facade reuses:
  // CharacterFacade.persistNewCard. This guarantees a generated card lands in
  // the library through the same single save path as manual creation.
  group('CharacterFacade.persistNewCard (shared chargen save path)', () {
    late AppDatabase db;
    late CharacterFacade facade;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting();
      await db.select(db.characters).get();
      final storage = StorageService();
      await storage.setRootPath(
        Directory.systemTemp.createTempSync('fpai_root_').path,
      );
      final repo = CharacterRepository(db, storage);
      facade = CharacterFacade(db, storage, null, null, repo);
    });

    tearDown(() => db.close());

    test('persists a generated card and assigns an id + image path', () async {
      final card = CharacterCard(
        name: 'Aria Vale',
        description: 'A wandering bard.',
        personality: 'witty, guarded',
      );
      final saved = await facade.persistNewCard(card);

      expect(saved, isNotNull);
      expect(saved!['name'], 'Aria Vale');
      expect(saved['id'], isNotNull);
      expect(card.imagePath, isNotNull);
      expect(File(card.imagePath!).existsSync(), isTrue);
    });

    test('falls back to a safe filename for a symbol-only name', () async {
      final card = CharacterCard(name: '***');
      final saved = await facade.persistNewCard(card);
      expect(saved, isNotNull);
      // No degenerate "_<epoch>.png"; the fallback prefix is used.
      expect(card.imagePath, isNotNull);
      expect(card.imagePath!.contains('character_'), isTrue);
      expect(File(card.imagePath!).existsSync(), isTrue);
    });
  });
}
