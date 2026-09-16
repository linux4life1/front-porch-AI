// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          final tmp = Directory.systemTemp.createTempSync('fpai_test_');
          return tmp.path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;
  late OpenRouterService mouthRemote;

  setUp(() async {
    _setupPathProviderMock();
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.initialized;
    await storage.setBackendType('openRouter');
    await storage.setRemoteApiUrl(kOpenRouterApiV1);
    await storage.setRemoteModelName('x-ai/grok-4.6');
    await storage.setRemoteApiKey('or-key');
    mouthRemote = OpenRouterService(
      apiUrl: kOpenRouterApiV1,
      apiKey: 'or-key',
      modelName: 'x-ai/grok-4.6',
    );
  });

  LLMProvider provider() => LLMProvider(
    KoboldService(storage),
    mouthRemote,
    storage,
    BackendManager(storage),
  );

  test('API+API: worker is a second service; mouth URL/model stay put', () async {
    await storage.setWorkerBackendType('openRouter');
    await storage.setWorkerRemoteApiUrl(kNanoGptApiV1);
    await storage.setWorkerRemoteModelName('z-ai/glm-5.3');
    await storage.setRemoteApiKeyFor(kNanoGptApiV1, 'nano-key');

    final p = provider();
    expect(p.workerRefusedDualLocal, isFalse);
    expect(p.workerService, isNotNull);
    expect(identical(p.workerService, p.activeService), isFalse);
    expect(p.openRouterService.apiUrl, kOpenRouterApiV1);
    expect(p.openRouterService.modelName, 'x-ai/grok-4.6');
    expect(p.workerRemoteService.apiUrl, kNanoGptApiV1);
    expect(p.workerRemoteService.modelName, 'z-ai/glm-5.3');
    expect(p.sideLaneService, same(p.workerService));
    expect(p.workerEvalIdentity, startsWith('worker|'));
  });

  test('same host, different model ids — two remotes, one vault URL', () async {
    await storage.setRemoteApiUrl(kNanoGptApiV1);
    await storage.setRemoteModelName('moonshotai/kimi-k2.6:thinking');
    await storage.setWorkerBackendType('openRouter');
    await storage.setWorkerRemoteApiUrl(kNanoGptApiV1);
    await storage.setWorkerRemoteModelName('z-ai/glm-5.3');

    final p = provider();
    expect(p.workerRefusedDualLocal, isFalse);
    expect(p.workerRemoteService.apiUrl, kNanoGptApiV1);
    expect(p.workerRemoteService.modelName, 'z-ai/glm-5.3');
    expect(
      p.openRouterService.modelName,
      isNot('z-ai/glm-5.3'),
      reason: 'worker model must not overwrite the mouth model',
    );
  });

  test('empty worker → side lane is the mouth', () {
    final p = provider();
    expect(p.workerService, isNull);
    expect(identical(p.sideLaneService, p.activeService), isTrue);
  });

  test('dual-local fail-closed: worker service is unused', () async {
    await storage.setBackendType('kobold');
    await storage.setWorkerBackendType('omlx');
    await storage.setWorkerRemoteApiUrl(kOmlxApiV1);
    await storage.setWorkerRemoteModelName('local-mlx');

    final p = provider();
    expect(p.workerRefusedDualLocal, isTrue);
    expect(p.workerService, isNull);
    expect(identical(p.sideLaneService, p.activeService), isTrue);
  });

  test('worker fields survive a fresh StorageService load', () async {
    await storage.setWorkerBackendType('openRouter');
    await storage.setWorkerRemoteApiUrl(kNanoGptApiV1);
    await storage.setWorkerRemoteModelName('z-ai/glm-5.3');

    final again = StorageService();
    await again.initialized;
    expect(again.workerBackendType, 'openRouter');
    expect(again.workerRemoteApiUrl, kNanoGptApiV1);
    expect(again.workerRemoteModelName, 'z-ai/glm-5.3');
  });
}
