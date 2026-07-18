// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ChatFacade.insertImage now attaches a real image MESSAGE through
// ChatService.addGeneratedImageMessage — the same path the desktop /image
// command and the Image Studio's "Send to chat" use — instead of the old
// markdown-append-to-last-message hack (which never rendered on desktop).
// These tests pin the delegation contract: filename → resolver → attach,
// plus the guard paths (no resolver / unresolvable name / blank name).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
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

/// Records addGeneratedImageMessage calls (the fake base class noSuchMethods
/// everything else the facade touches).
class _RecordingChatService extends FakeChatService {
  final List<(String path, String prompt)> attached = [];

  @override
  Future<void> addGeneratedImageMessage(
    String path,
    String prompt, {
    String? senderName,
    String? characterId,
  }) async {
    attached.add((path, prompt));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  group('ChatFacade.insertImage', () {
    late AppDatabase db;
    late CharacterRepository repo;
    late _RecordingChatService chat;

    ChatFacade facadeWith({File? Function(String name)? resolver}) =>
        ChatFacade(chat, repo, null, null, null, resolveSavedImage: resolver);

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting();
      await db.select(db.characters).get();
      repo = CharacterRepository(db, StorageService());
      chat = _RecordingChatService();
    });

    tearDown(() => db.close());

    test('resolves the filename and attaches an image message', () async {
      final facade = facadeWith(
        resolver: (name) =>
            name == 'img_42.png' ? File('/data/images/img_42.png') : null,
      );
      expect(
        await facade.insertImage('img_42.png', prompt: 'a quiet evening'),
        isTrue,
      );
      expect(chat.attached.single, (
        '/data/images/img_42.png',
        'a quiet evening',
      ));
    });

    test('returns false when the name does not resolve', () async {
      final facade = facadeWith(resolver: (_) => null);
      expect(await facade.insertImage('nope.png'), isFalse);
      expect(chat.attached, isEmpty);
    });

    test('returns false without a resolver (image facade absent)', () async {
      expect(await facadeWith().insertImage('img_1.png'), isFalse);
      expect(chat.attached, isEmpty);
    });

    test('trims and rejects a blank filename', () async {
      var asked = <String>[];
      final facade = facadeWith(
        resolver: (name) {
          asked.add(name);
          return null;
        },
      );
      expect(await facade.insertImage('   '), isFalse);
      expect(asked, ['']); // trimmed before the resolver sees it
      expect(chat.attached, isEmpty);
    });
  });
}
