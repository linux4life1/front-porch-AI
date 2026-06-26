// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/facade/group_facade.dart';

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

  group('GroupFacade.updateSettings', () {
    late AppDatabase db;
    late GroupChatRepository groups;
    late GroupFacade facade;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting();
      await db.select(db.characters).get();
      final storage = StorageService();
      await storage.setRootPath(
        Directory.systemTemp.createTempSync('fpai_root_').path,
      );
      groups = GroupChatRepository(storage, db);
      await groups.save(GroupChat(id: 'g1', name: 'Original'));
      facade = GroupFacade(groups, storage);
    });

    tearDown(() => db.close());

    test('updates settings-only fields and persists', () async {
      expect(
        await facade.updateSettings('g1', {
          'name': 'Renamed',
          'systemPrompt': 'Be terse.',
          'scenario': 'A tavern',
          'turnOrder': 'random',
          'characterSystemPrompts': {'alice': 'whisper', 'bram': 'shout'},
        }),
        isTrue,
      );

      final g = groups.getById('g1')!;
      expect(g.name, 'Renamed');
      expect(g.systemPrompt, 'Be terse.');
      expect(g.scenario, 'A tavern');
      expect(g.turnOrder.name, 'random');
      expect(g.characterSystemPrompts['alice'], 'whisper');
      expect(g.characterSystemPrompts['bram'], 'shout');
    });

    test('unknown group returns false', () async {
      expect(await facade.updateSettings('nope', {'name': 'x'}), isFalse);
    });
  });
}
