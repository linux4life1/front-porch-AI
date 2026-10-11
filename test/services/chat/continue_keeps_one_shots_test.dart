// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Continue is a pure append. It strips the one-shot directives from its own
// wire, so it must not TAKE them either: a Chance Time event or a Porch Night
// force-ack armed before a Continue still reaches the next real Send.
//
// Proven red: set `skipOneShots` to false in the generation plan — Continue
// marks the event delivered / takes the ack, the next Send clears it, and
// both tests fail on the second request body.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../../integration_test/support/fake_backend.dart';
import '../../helpers/chat_db_teardown.dart';

const _event = 'A raccoon tips the RACCOON-MARKER bin off the porch.';
const _ack = '\n[TABLE TALK — HARD REQUIRED OPENING: ACK-MARKER Mafia.]\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_oneshot_').path;
        }
        return null;
      });

  late FakeBackendServer backend;
  late AppDatabase db;
  late ChatService chat;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
    });
    backend = await FakeBackendServer.start(replyPieces: ['She nods.']);
    db = AppDatabase.forTesting();
    final storage = StorageService();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..testLlmServiceOverride = OpenRouterService(
            apiUrl: '${backend.baseUrl}/v1',
            modelName: 'smoke-model',
          );
    await storage.initialized;
    await chat.setActiveCharacter(
      CharacterCard(
        name: 'Mara',
        description: 'Exists only inside the one-shot Continue test.',
        firstMessage: 'The porch light hums.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: false,
          needsSimEnabled: false,
          chaosModeEnabled: false,
        ),
      )..dbId = 'char-oneshot-continue',
    );
    await chat.sendMessage('Evening.');
  });

  tearDown(() async {
    await disposeChatThenCloseDb(chat, db);
    await backend.close();
  });

  String lastWire() {
    final msgs = (jsonDecode(backend.lastChatBody) as Map)['messages'] as List;
    return msgs.map((m) => (m as Map)['content'].toString()).join('\n');
  }

  Future<void> continueThenSend() async {
    backend.replyPieces
      ..clear()
      ..add(' And hums.');
    await chat.continueGeneration();
    for (var i = 0; i < 100 && chat.isSettlingTurn; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test(
    'a Chance Time event armed before Continue reaches the next Send',
    () async {
      await chat.applyChanceTimeResult(_event, 'Mara');
      await continueThenSend();
      expect(lastWire(), isNot(contains('RACCOON-MARKER')));

      backend.replyPieces
        ..clear()
        ..add('She jumps.');
      await chat.sendMessage('What was that?');
      expect(
        lastWire(),
        contains('RACCOON-MARKER'),
        reason: 'Continue must leave the event armed for the next real turn',
      );
    },
  );

  test('a Porch Night force-ack survives Continue to the next Send', () async {
    chat.debugArmPorchNightForTest(
      diaryCharacterId: chat.characterIdFor(chat.activeCharacter!),
      injectionText: _ack,
    );
    await continueThenSend();
    expect(lastWire(), isNot(contains('ACK-MARKER')));

    backend.replyPieces
      ..clear()
      ..add('She deals the cards.');
    await chat.sendMessage('Shall we play?');
    expect(
      lastWire(),
      contains('ACK-MARKER'),
      reason: 'Continue must not take the force-ack it strips',
    );
  });
}
