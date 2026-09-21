// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// `/join --full <library name>` on a 1:1 becomes a group with that member.
// Proven red: skip setGroupChatRepository (joinFull returns on a null repo)
// or restore the `_messages.isEmpty` silent fork without a banner.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../../integration_test/support/fake_backend.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_join_full_').path;
        }
        return null;
      });
}

CharacterCard _card(String name, {String firstMessage = 'Hello.'}) =>
    CharacterCard(
      name: name,
      description: 'Exists only inside the join-full convert test.',
      firstMessage: firstMessage,
      personality: '$name personality',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: false,
        needsSimEnabled: false,
        chaosModeEnabled: false,
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late CharacterRepository repo;
  late ChatService chat;
  late FakeBackendServer backend;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
    });
    backend = await FakeBackendServer.start(
      replyPieces: const ['They step onto the porch.'],
    );
    db = AppDatabase.forTesting();
    storage = StorageService();
    repo = CharacterRepository(db, storage);
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(repo)
          ..setGroupChatRepository(GroupChatRepository(storage, db))
          ..testLlmServiceOverride = OpenRouterService(
            apiUrl: '${backend.baseUrl}/v1',
            modelName: 'smoke-model',
          );
    await storage.initialized;
  });

  tearDown(() async {
    chat.dispose();
    await backend.close();
    await db.close();
  });

  test(
    '1:1 host + /join --full second card becomes a group with two members',
    () async {
      final host = _card('Zinna', firstMessage: 'The porch light hums.');
      final arrival = _card('Senjumaru');
      await repo.addCharacter(host);
      await repo.addCharacter(arrival);
      await chat.setActiveCharacter(host);

      expect(chat.activeGroup, isNull);
      await chat.sendMessage('/join --full senju');

      expect(
        chat.activeGroup,
        isNotNull,
        reason: 'THE BUG: joinFull never converted the 1:1 into a group',
      );
      expect(
        chat.groupCharacters.map((c) => c.name),
        containsAll(['Zinna', 'Senjumaru']),
      );
      expect(chat.groupCharacters, hasLength(2));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'joinFull with no history surfaces a banner, not a silent no-op',
    () async {
      final host = _card('Zinna', firstMessage: '');
      final arrival = _card('Senjumaru');
      await repo.addCharacter(host);
      await repo.addCharacter(arrival);
      await chat.setActiveCharacter(host);
      expect(chat.messages, isEmpty);

      await chat.joinFull(arrival);

      expect(chat.activeGroup, isNull);
      expect(chat.guestActivityStatus, contains('scene to convert'));
      expect(chat.guestActivityIsError, isTrue);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('/join --full with no unique name parks the FULL picker', () async {
    final host = _card('Zinna', firstMessage: 'Hi.');
    await repo.addCharacter(host);
    await repo.addCharacter(_card('Senjumaru'));
    await repo.addCharacter(_card('Senjuta'));
    await chat.setActiveCharacter(host);

    await chat.sendMessage('/join --full senj');

    expect(chat.pendingGuestPickerFilter, 'senj');
    expect(chat.pendingGuestPickerFull, isTrue);
    expect(chat.activeGroup, isNull);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
