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

    test('blank name rejected; unknown delete returns false', () async {
      expect(await facade.save({'name': '  '}), isFalse);
      expect(await facade.delete('nope'), isFalse);
      expect(facade.detail('nope'), isNull);
    });
  });
}
