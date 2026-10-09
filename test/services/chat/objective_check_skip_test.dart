// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Skip goal check" on the objective overlay stops only the goal check.
// A real ChatService sends a turn to a loopback OpenAI-compatible backend
// that holds the goal-check request open (and would answer YES, which would
// retire the quest). Skip must: let the reply land, leave the quest as it
// was, and hang up the held request instead of leaving it running.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../../integration_test/support/fake_backend.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_goal_skip_').path;
        }
        return null;
      });
}

/// No engine on disk and no download: this test never starts KoboldCpp.
class _QuietBackend extends BackendManager {
  _QuietBackend(super.storage);

  @override
  String? get backendPath => '/tmp/fake-koboldcpp';

  @override
  Future<void> checkBackendAvailability() async {}

  @override
  Future<void> ensureEngineInstalled() async {}
}

Future<void> _until(bool Function() done, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  test('Skip goal check: the reply lands, the quest is untouched, and the '
      'held check request is hung up', () async {
    HttpOverrides.global = null;
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'backend_type': 'openRouter',
      'realism_default': false,
      'pockets_enabled': false,
      'journal_enabled': false,
    });
    final backend = await FakeBackendServer.start(
      replyPieces: ['The lemonade is ', 'still cold.'],
    );
    final hold = Completer<void>();
    backend
      ..objectiveCheckVerdict = '1: YES'
      ..holdObjectiveCheck = hold;

    final db = AppDatabase.forTesting(sameIsolate: true);
    final storage = StorageService();
    await storage.initialized;
    final kobold = KoboldService(storage);
    final provider = LLMProvider(
      kobold,
      OpenRouterService(apiUrl: '', apiKey: '', modelName: ''),
      storage,
      _QuietBackend(storage),
    );
    final chat =
        ChatService(
            kobold,
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage))
          // The check only runs with a provider wired, as in the app.
          ..setLLMProvider(provider)
          ..testLlmServiceOverride = OpenRouterService(
            apiUrl: '${backend.baseUrl}/v1',
            modelName: 'smoke-model',
          );
    addTearDown(() async {
      if (!hold.isCompleted) hold.complete();
      await disposeChatThenCloseDb(chat, db);
      provider.dispose();
      await backend.close();
    });

    await chat.setActiveCharacter(
      CharacterCard(
        name: 'Jennifer',
        description: 'Exists only inside the goal-check skip test.',
        firstMessage: 'Welcome to the porch.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: false,
          needsSimEnabled: false,
          chaosModeEnabled: false,
        ),
      )..dbId = 'char-goal-skip',
    );
    await chat.setObjective('Share porch lemonade before sunset');
    final quest = chat.activeObjectives.single;
    await chat.updateCheckFrequency(quest, 1);

    final send = chat.sendMessage('Want some lemonade?');
    await backend.objectiveCheckHeld.future.timeout(
      const Duration(seconds: 10),
    );
    expect(chat.isCheckingCompletion, isTrue);

    chat.skipObjectiveCheck();
    await send.timeout(const Duration(seconds: 10));

    expect(chat.isCheckingCompletion, isFalse);
    expect(backend.chatRequests, 1, reason: 'the reply was still asked for');
    final reply = chat.messages.last;
    expect(reply.isUser, isFalse);
    expect(reply.displayText, 'The lemonade is still cold.');
    expect(chat.activeObjectives.map((o) => o.id), [
      quest.id,
    ], reason: 'the held check would have answered YES and retired the quest');
    await _until(
      () => backend.objectiveChecksHungUp == 1,
      'the held goal-check request to be hung up',
    );
    expect(backend.objectiveCheckRequests, 1);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
