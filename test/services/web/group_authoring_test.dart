// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/facade/character_facade.dart';
import 'package:front_porch_ai/services/web/facade/group_authoring_facade.dart';

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

  group('GroupAuthoringFacade', () {
    late AppDatabase db;
    late GroupChatRepository groups;
    late GroupAuthoringFacade facade;
    late String a, b, c;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting();
      await db.select(db.characters).get();
      final storage = StorageService();
      await storage.setRootPath(
        Directory.systemTemp.createTempSync('fpai_root_').path,
      );
      final chars = CharacterRepository(db, storage);
      groups = GroupChatRepository(storage, db);
      final cf = CharacterFacade(db, storage, null, null, chars);
      a = (await cf.create({'name': 'Aria'}))!['id'] as String;
      b = (await cf.create({'name': 'Bram'}))!['id'] as String;
      c = (await cf.create({'name': 'Cleo'}))!['id'] as String;
      facade = GroupAuthoringFacade(groups, chars, db, storage);
    });

    tearDown(() => db.close());

    test('create denormalizes members + saves the group', () async {
      final res = await facade.create({
        'name': 'The Trio',
        'characterIds': [a, b],
        'turnOrder': 'random',
        'scenario': 'A tavern',
      });
      expect(res, isNotNull);
      final id = res!['id'] as String;

      final g = groups.getById(id);
      expect(g, isNotNull);
      expect(g!.name, 'The Trio');
      expect(g.turnOrder.name, 'random');

      final members = await groups.getMembersForGroup(id);
      expect(members.map((m) => m.name).toSet(), {'Aria', 'Bram'});
      // Each member got a private avatar copied into the group dir.
      expect(members.every((m) => (m.avatarFilename ?? '').isNotEmpty), isTrue);
    });

    test('create rejects fewer than 2 members or a blank name', () async {
      expect(await facade.create({'name': 'Solo', 'characterIds': [a]}), isNull);
      expect(await facade.create({'name': '', 'characterIds': [a, b]}), isNull);
    });

    test('edit changes settings and replaces membership', () async {
      final id = (await facade.create({'name': 'G', 'characterIds': [a, b]}))!['id'] as String;

      expect(
        await facade.edit(id, {
          'name': 'Renamed',
          'scenario': 'New scene',
          'characterIds': [b, c],
        }),
        isTrue,
      );

      final g = groups.getById(id)!;
      expect(g.name, 'Renamed');
      expect(g.scenario, 'New scene');
      final members = await groups.getMembersForGroup(id);
      expect(members.map((m) => m.name).toSet(), {'Bram', 'Cleo'});

      // Settings-only edit (no characterIds) keeps the roster.
      expect(await facade.edit(id, {'name': 'Again'}), isTrue);
      expect((await groups.getMembersForGroup(id)).length, 2);

      // Membership replace with <2 is rejected.
      expect(await facade.edit(id, {'characterIds': [b]}), isFalse);

      expect(await facade.edit('missing', {'name': 'x'}), isFalse);
    });
  });
}
