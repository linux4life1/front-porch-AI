// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/facade/character_facade.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
    if (call.method == 'getApplicationDocumentsDirectory') {
      return Directory.systemTemp.createTempSync('fpai_test_').path;
    }
    return null;
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();
  SharedPreferences.setMockInitialValues({});

  group('CharacterFacade', () {
    late AppDatabase db;
    late CharacterFacade facade;

    setUp(() async {
      db = AppDatabase.forTesting();
      await db.select(db.characters).get(); // warm up / create schema
      // No folders/chat/repo: list+detail must not depend on them.
      facade = CharacterFacade(db, StorageService(), null, null, null);
      await db.insertCharacter(
        CharactersCompanion(
          id: const Value('c1'),
          name: const Value('Alice'),
          description: const Value('A friendly guide'),
          tags: Value(jsonEncode(['mentor', 'kind'])),
          imagePath: const Value('alice.png'),
        ),
      );
      await db.insertCharacter(
        CharactersCompanion(
          id: const Value('c2'),
          name: const Value('Bob'),
          tags: Value(jsonEncode(['gruff'])),
        ),
      );
    });

    tearDown(() => db.close());

    test('list returns characters sorted by name with parsed tags', () async {
      final list = await facade.list();
      expect(list.map((c) => c['name']), ['Alice', 'Bob']);
      expect(list.first['tags'], ['mentor', 'kind']);
      expect(list.first['hasAvatar'], isTrue);
      expect(list[1]['hasAvatar'], isFalse);
    });

    test('list search filters by name and tags', () async {
      expect((await facade.list(search: 'alice')).length, 1);
      expect((await facade.list(search: 'gruff')).single['name'], 'Bob');
      expect((await facade.list(search: 'nomatch')), isEmpty);
    });

    test('detail returns the full card payload', () async {
      final d = await facade.detail('c1');
      expect(d, isNotNull);
      expect(d!['name'], 'Alice');
      expect(d['description'], 'A friendly guide');
      expect(d['tags'], ['mentor', 'kind']);
      expect(d['evolutionCount'], 0); // no chat injected
    });

    test('detail returns null for an unknown id', () async {
      expect(await facade.detail('missing'), isNull);
    });
  });
}
