// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// `/speak` is the porch mic: with a Scene Guest present, `/speak <host>`
// generates the host (no guestSpeaker). Bare `/speak` stays last guest.
// Proven red: drop getHostCharacter wiring and `/speak Zinna` lists guests
// and never calls generatePrimaryTurn.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/chat/chat_command_handler.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../../integration_test/support/fake_backend.dart';
import '../../helpers/chat_db_teardown.dart';

CharacterCard _card(String name) => CharacterCard(
  name: name,
  frontPorchExtensions: FrontPorchExtensions(tier: 'lite'),
);

ChatCommandHandler _handler({
  required List<CharacterCard> guests,
  required CharacterCard host,
  required List<String> systemMessages,
  required List<CharacterCard> spokeGuests,
  required List<int> hostTurns,
}) {
  return ChatCommandHandler(
    setExpression: (_) {},
    activeCharacterIsSet: () => true,
    getSceneGuestCards: () => guests,
    setPendingGuestDeparture: (_) {},
    onSystemMessage: systemMessages.add,
    generatePrimaryTurn: () async => hostTurns.add(1),
    createGuest: (_, _) async {},
    exitGuest: (_) async {},
    getJoinableCharacters: () => const [],
    joinGuest: (_) async {},
    joinFull: (_) async {},
    promoteScene: () async {},
    requestGuestPicker: (_, _) {},
    runCastScan: () async => false,
    speakGuest: (g) async => spokeGuests.add(g),
    armExitUndo: (_) {},
    getGroupMembers: () => const [],
    getGroupJoinableCharacters: () => const [],
    removeGroupMember: (_) async => true,
    speakGroupMember: (_) async {},
    isGroupTurnOrderRandom: () => false,
    setGroupTurnOrder: (_, _) async {},
    configureAfk: (enabled, maxMessages, intervalSeconds) => (
      enabled: enabled,
      maxMessages: maxMessages ?? 3,
      intervalSeconds: intervalSeconds ?? 60,
    ),
    generateImage: (_) async {},
    getHostCharacter: () => host,
  );
}

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_porch_speak_').path;
        }
        return null;
      });
}

void main() {
  group('ChatCommandHandler porch mic', () {
    final host = _card('Zinna');
    late List<CharacterCard> guests;
    late List<String> systemMessages;
    late List<CharacterCard> spokeGuests;
    late List<int> hostTurns;

    setUp(() {
      guests = [_card('Nora')];
      systemMessages = [];
      spokeGuests = [];
      hostTurns = [];
    });

    ChatCommandHandler build() => _handler(
      guests: guests,
      host: host,
      systemMessages: systemMessages,
      spokeGuests: spokeGuests,
      hostTurns: hostTurns,
    );

    test('/speak <host> generates the host, not the guest', () async {
      expect(await build().handle('/speak Zinna'), true);
      expect(hostTurns, isNotEmpty);
      expect(spokeGuests, isEmpty);
    });

    test('/speak <host substring> unique-matches the host', () async {
      expect(await build().handle('/speak zin'), true);
      expect(hostTurns, isNotEmpty);
      expect(spokeGuests, isEmpty);
    });

    test('/speak <guest> still speaks the guest', () async {
      expect(await build().handle('/speak Nora'), true);
      expect(spokeGuests.single.name, 'Nora');
      expect(hostTurns, isEmpty);
    });

    test('/speak (no name) still targets the last guest', () async {
      guests = [_card('Aria'), _card('Bram')];
      await build().handle('/speak');
      expect(spokeGuests.single.name, 'Bram');
      expect(hostTurns, isEmpty);
    });

    test('/speak unknown lists host and guests', () async {
      await build().handle('/speak Zelda');
      expect(spokeGuests, isEmpty);
      expect(hostTurns, isEmpty);
      expect(systemMessages.single, contains('Zelda'));
      expect(systemMessages.single, contains('Zinna'));
      expect(systemMessages.single, contains('Nora'));
    });

    test('slash helper names host, guest, and group member', () {
      final speak = ChatCommandHandler.commands.firstWhere(
        (c) => c.command == 'speak',
      );
      expect(speak.example, '/speak [name]');
      expect(speak.description.toLowerCase(), contains('host'));
      expect(speak.description.toLowerCase(), contains('guest'));
    });
  });

  group('ChatService /speak host is not a guest turn', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    _setupPathProviderMock();

    test(
      '/speak host puts the host on the wire, not SCENE GUEST TURN',
      () async {
        HttpOverrides.global = null;
        SharedPreferences.setMockInitialValues({
          'update_auto_check': false,
          'realism_default': false,
        });
        final backend = await FakeBackendServer.start(
          replyPieces: const ['The porch is quiet.'],
        );
        final db = AppDatabase.forTesting();
        final storage = StorageService();
        final repo = CharacterRepository(db, storage);
        final chat =
            ChatService(
                KoboldService(storage),
                UserPersonaService(db),
                storage,
                WorldRepository(storage, db),
              )
              ..setDatabase(db)
              ..setCharacterRepository(repo)
              ..testLlmServiceOverride = OpenRouterService(
                apiUrl: '${backend.baseUrl}/v1',
                modelName: 'smoke-model',
              );
        addTearDown(() async {
          await disposeChatThenCloseDb(chat, db);
          await backend.close();
        });
        await storage.initialized;

        final host = CharacterCard(
          name: 'Zinna',
          personality: 'HOST_PERSONA_MARKER',
          firstMessage: 'The screen door bangs shut.',
          frontPorchExtensions: FrontPorchExtensions(
            realismEnabled: false,
            needsSimEnabled: false,
            chaosModeEnabled: false,
          ),
        );
        final guest = CharacterCard(
          name: 'Nora',
          personality: 'GUEST_PERSONA_MARKER',
          firstMessage: 'Hi.',
          frontPorchExtensions: FrontPorchExtensions(
            realismEnabled: false,
            needsSimEnabled: false,
            chaosModeEnabled: false,
            tier: 'lite',
          ),
        );
        await repo.addCharacter(host);
        await repo.addCharacter(guest);
        await chat.setActiveCharacter(host);
        await chat.joinSceneGuest(guest);
        await chat.sendMessage('/speak Zinna');

        final messages =
            (jsonDecode(backend.lastChatBody) as Map)['messages'] as List;
        final system = messages.first['content'] as String;
        final user = messages.last['content'] as String;
        expect(user, isNot(contains('SCENE GUEST TURN')));
        expect(system, contains("Zinna's Persona"));
        expect(user, contains('\nZinna:'));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
