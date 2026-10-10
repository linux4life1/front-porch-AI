// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One-Shot Auto asks whether the model that runs the Realism evals is local:
// the helper model when one is set, otherwise the chat model. It used to ask
// about the chat model only, so a cloud chat model with a small local
// KoboldCpp helper fused every eval into one heavy call on that helper, and a
// local chat model with a cloud helper never fused.
//
// The real chat service, provider and tool probe run. The probe is told the
// eval model has proven tool calls, the one case where Auto fuses.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/chat_db_teardown.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late AppDatabase db;
  late StorageService storage;
  late KoboldService kobold;
  late LLMProvider provider;
  late ChatService chat;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fpai_oneshot_eval_lane');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? dir.path
              : null,
        );
    SharedPreferences.setMockInitialValues({'update_auto_check': false});
    db = AppDatabase.forTesting();
    storage = StorageService();
    await storage.initialized;
    // The chat model is always a Custom URL here, so no test starts or
    // downloads KoboldCpp.
    await storage.backendSettings.setBackendType('openRouter');
    await storage.backendSettings.setRemoteModelName('chat-model');
    await storage.realismSettings.setOneShotMode(OneShotMode.auto);
    kobold = KoboldService(storage);
    provider = LLMProvider(
      kobold,
      OpenRouterService(apiUrl: '', apiKey: '', modelName: ''),
      storage,
      BackendManager(storage),
    );
    chat =
        ChatService(
            kobold,
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setLLMProvider(provider);
  });

  tearDown(() async {
    await disposeChatThenCloseDb(chat, db);
    provider.dispose();
    kobold.dispose();
    await dir.delete(recursive: true);
  });

  /// Chat at [chatUrl]; the helper lane on with tool calls proven for it.
  Future<void> withHelper(
    String chatUrl, {
    required String type,
    String url = '',
  }) async {
    await storage.backendSettings.setRemoteApiUrl(chatUrl);
    await storage.setWorkerBackendType(type);
    await storage.setWorkerRemoteApiUrl(url);
    await storage.setWorkerRemoteModelName('helper-model');
    expect(provider.workerService, isNotNull, reason: 'the helper lane is on');
    expect(
      chat.debugEvalBackendIdentity,
      startsWith('worker|'),
      reason: 'the tool verdict Auto reads is the helper model\'s',
    );
    chat.debugMarkEvalToolsSupported();
  }

  test(
    'a cloud chat model with a local KoboldCpp helper stays multi-call',
    () async {
      await withHelper('https://openrouter.ai/api/v1', type: 'kobold');
      expect(
        chat.debugOneShotActive,
        isFalse,
        reason:
            'the evals run on the local helper: Auto must keep the safer '
            'multi-call path there, whatever the chat model is',
      );
    },
  );

  test(
    'a cloud chat model with a helper at a LAN address stays multi-call',
    () async {
      await withHelper(
        'https://openrouter.ai/api/v1',
        type: 'openRouter',
        url: 'http://192.168.1.20:1234/v1',
      );
      expect(chat.debugOneShotActive, isFalse);
    },
  );

  test('a local chat model with a cloud helper fuses', () async {
    await withHelper(
      'http://127.0.0.1:5001/v1',
      type: 'openRouter',
      url: 'https://openrouter.ai/api/v1',
    );
    expect(
      chat.debugOneShotActive,
      isTrue,
      reason:
          'the evals run on the cloud helper with proven tools: Auto fuses, '
          'though the chat model is local',
    );
  });
}
