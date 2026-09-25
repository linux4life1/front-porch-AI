// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A Scene Guest (lite) turn after an OOC skip must keep time_skip_to
// and the skip chip — the guest path must not drop skip ownership.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_lite_skip_').path;
        }
        return null;
      });
}

class _ScriptedLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield '*Riley waves from the steps.*';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'LiteSkipChip';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  AppDatabase? db;
  ChatService? chat;

  Future<void> drain() async {
    for (
      var i = 0;
      i < 400 && (chat!.isGenerating || chat!.isSettlingTurn);
      i++
    ) {
      await Future<void>.delayed(Duration.zero);
    }
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test('lite turn after an OOC skip keeps time_skip_to and the chip', () async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      'needs_sim_default': true,
      'passage_of_time_default': true,
    });
    db = AppDatabase.forTesting();
    final storage = StorageService();
    final repo = CharacterRepository(db!, storage);
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db!),
            storage,
            WorldRepository(storage, db!),
          )
          ..setDatabase(db!)
          ..setCharacterRepository(repo)
          ..testLlmServiceOverride = _ScriptedLlm();
    await storage.initialized;
    final host = CharacterCard(
      name: 'Flora',
      firstMessage: 'Evening.',
      imagePath: '/tmp/flora-lite-skip.png',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        needsSimEnabled: true,
      ),
    );
    final guest = CharacterCard(
      name: 'Riley',
      firstMessage: 'Hi.',
      imagePath: '/tmp/riley-lite-skip.png',
      frontPorchExtensions: FrontPorchExtensions(tier: 'lite'),
    );
    await repo.addCharacter(host);
    await repo.addCharacter(guest);
    await chat!.setActiveCharacter(host);
    await chat!.joinSceneGuest(guest);
    await drain();

    await chat!.sendMessage('(ooc: skip ahead two hours)');
    await drain();
    final hostSkip = chat!.messages.lastWhere((m) => m.sender == 'Flora');
    final skipTo = hostSkip.activeMetadata?['time_skip_to'];
    final chip = hostSkip.activeMetadata?['time_passed'];
    expect(skipTo, isNotNull, reason: 'OOC skip stamps time_skip_to');

    await chat!.speakGuestNow(guest);
    await drain();
    final lite = chat!.messages.lastWhere((m) => m.sender == 'Riley');
    expect(
      lite.activeMetadata?['time_skip_to'],
      skipTo,
      reason: 'lite turn after an OOC skip keeps time_skip_to',
    );
    expect(lite.activeMetadata?['time_passed'], chip);
  });
}
