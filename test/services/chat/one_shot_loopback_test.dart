// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One-Shot Auto keeps the multi-call path on local models. A Custom URL at
// http://127.0.0.1:5001/v1 is a local KoboldCpp reached the OpenAI way, and
// Auto used to fuse every Realism eval into one heavy call there, because
// locality was read from the backend type alone (only the managed KoboldCpp
// counted). A loopback is local.
//
// The real chat service, provider and tool probe run. The probe is told the
// model has proven tool calls, the one case where Auto fuses a remote model.

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
    dir = await Directory.systemTemp.createTemp('fpai_oneshot_loopback');
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
    await storage.backendSettings.setBackendType('openRouter');
    await storage.backendSettings.setRemoteModelName('some-model');
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

  /// Point the Custom backend at [url], with tool calls proven for it.
  Future<void> customAt(String url) async {
    await storage.backendSettings.setRemoteApiUrl(url);
    expect(provider.activeBackend, BackendType.openRouter);
    expect(provider.openRouterService.apiUrl, url);
    chat.debugMarkEvalToolsSupported();
  }

  test('Auto keeps multi-call for a Custom backend at 127.0.0.1', () async {
    await customAt('http://127.0.0.1:5001/v1');
    expect(
      chat.debugOneShotActive,
      isFalse,
      reason:
          'a loopback is this machine: Auto must keep the safer multi-call '
          'path, as the sidebar promises for local models',
    );
  });

  test('Auto still fuses a remote host with proven tools', () async {
    await customAt('https://openrouter.ai/api/v1');
    expect(chat.debugOneShotActive, isTrue);
  });
}
