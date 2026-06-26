// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/facade/chat_facade.dart';

import '../../golden/support/fakes.dart';

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

ChatFacade _facadeFor(CharacterRepository repo, List<ChatMessage> seed) =>
    ChatFacade(FakeChatService(messages: seed), repo, null, null, null);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  group('ChatFacade.insertImage', () {
    late AppDatabase db;
    late CharacterRepository repo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting();
      await db.select(db.characters).get();
      repo = CharacterRepository(db, StorageService());
    });

    tearDown(() => db.close());

    test('appends inline markdown to the last message', () {
      final seed = [
        ChatMessage(text: 'Hi', sender: 'You', isUser: true),
        ChatMessage(text: 'A quiet evening.', sender: 'Mae', isUser: false),
      ];
      final facade = _facadeFor(repo, seed);

      expect(facade.insertImage('img_42.png'), isTrue);
      expect(
        seed.last.text,
        'A quiet evening.\n\n![generated image](/api/image/saved/img_42.png)',
      );
      // Earlier messages are untouched.
      expect(seed.first.text, 'Hi');
    });

    test('returns false when there are no messages', () {
      expect(_facadeFor(repo, const []).insertImage('img_1.png'), isFalse);
    });

    test('rejects a blank filename', () {
      final seed = [ChatMessage(text: 'Hi', sender: 'You', isUser: true)];
      expect(_facadeFor(repo, seed).insertImage('   '), isFalse);
      expect(seed.first.text, 'Hi');
    });
  });
}
