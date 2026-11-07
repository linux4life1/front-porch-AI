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
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/facade/chat_facade.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/facade/character_facade.dart';
import 'package:front_porch_ai/services/web/host/host.dart';
import 'package:front_porch_ai/services/web/tunnels/tunnels.dart';

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

  // Issue #667: the phone's chat insert is wired through the server assembly.
  // It must copy a Recent picture into the chat pictures folder, so the
  // shelf trimming it later never breaks the chat message.
  group('ChatFacade.insertImage as the server wires it', () {
    test('a Recent picture inserted from the phone survives a trim', () async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.forTesting();
      addTearDown(db.close);
      await db.select(db.characters).get();
      final storage = StorageService();
      await storage.initialized;
      final root = Directory.systemTemp.createTempSync('fpai_insert_root_');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      await storage.setRootPath(root.path);
      await storage.imageGenSettings.setStudioRecentLimit(kStudioRecentOff);
      final chat = _RecordingChatService();
      final repo = CharacterRepository(db, storage);
      final services = WebHostServices()
        ..chat = chat
        ..characters = repo
        ..imageGen = ImageGenService(storage);
      final assembled = assembleWebServerDeps(
        services: services,
        storage: storage,
        db: db,
        auth: AuthService(db),
        streamHub: null,
        characterFacade: CharacterFacade(db, storage, null, chat, repo),
        tunnelManager: TunnelManager(0),
        onClientActive: (_, _) {},
      );

      final first = await rememberStudioResult(
        storage,
        Uint8List.fromList([137, 80, 78, 71, 1]),
        prompt: 'first',
        edit: false,
      );
      expect(
        await assembled.deps.chatFacade!.insertImage(
          first!.name,
          prompt: 'first',
        ),
        isTrue,
      );
      final attached = chat.attached.single.$1;
      expect(p.dirname(attached), p.join(root.path, 'KoboldManager', 'images'));

      // Off keeps only the newest, so this trims the first picture.
      await rememberStudioResult(
        storage,
        Uint8List.fromList([137, 80, 78, 71, 2]),
        prompt: 'second',
        edit: false,
      );
      expect(File(first.path).existsSync(), isFalse);
      expect(File(attached).readAsBytesSync(), [137, 80, 78, 71, 1]);
    });
  });
}
