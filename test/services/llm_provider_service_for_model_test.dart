// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// LLMProvider.serviceForModel — the ONE resolver behind every model-pickable
// generation feature (AI character creator + AI Enhance, desktop + web).
// Extracted from the creator's private _resolveLlmService; these tests pin
// the contract: a picked remote model gets an ad-hoc service without ever
// switching the app's active model, and a managed local backend ignores the
// pick entirely (its loaded model IS the model).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
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

class _RemoteProvider extends LLMProvider {
  _RemoteProvider(super.k, super.o, super.s, super.b);
  @override
  bool get hasManagedProcess => false;
  @override
  LLMService get activeService => openRouterService;
}

class _LocalProvider extends LLMProvider {
  _LocalProvider(super.k, super.o, super.s, super.b);
  @override
  bool get hasManagedProcess => true;
  @override
  LLMService get activeService => koboldService;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;
  late OpenRouterService active;

  setUp(() async {
    _setupPathProviderMock();
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.initialized;
    // The provider's ctor reconfigures the remote service FROM storage, so
    // the active model must be seeded there, not on the service instance.
    await storage.backendSettings.setBackendType('openRouter');
    await storage.backendSettings.setRemoteModelName('current/model');
    // isReady demands a key (or a local URL) — seed one so the active-service
    // branch is actually reachable.
    await storage.backendSettings.setRemoteApiKey('test-key');
    active = OpenRouterService(
      apiUrl: 'https://api.example.test/v1',
      apiKey: 'k',
    );
  });

  _RemoteProvider remote() => _RemoteProvider(
    KoboldService(storage),
    active,
    storage,
    BackendManager(storage),
  );

  test('remote + different model → ad-hoc service, active model untouched', () {
    final provider = remote();
    final svc = provider.serviceForModel('other/model');
    expect(svc, isA<OpenRouterService>());
    expect((svc as OpenRouterService).modelName, 'other/model');
    expect(identical(svc, active), isFalse);
    expect(
      active.modelName,
      'current/model',
      reason: 'picking a run model must never switch the app model',
    );
  });

  test('remote + same/empty model id → the active service itself', () {
    final provider = remote();
    expect(
      identical(provider.serviceForModel('current/model'), active),
      isTrue,
    );
    expect(identical(provider.serviceForModel(''), active), isTrue);
  });

  test(
    'oMLX + a different pick still aims at localhost oMLX, not Remote API',
    () async {
      await storage.backendSettings.setBackendType('omlx');
      await storage.backendSettings.setRemoteApiUrl(
        'https://openrouter.ai/api/v1',
      );
      await storage.backendSettings.setRemoteModelName('Qwen3.6-40B');
      final provider = LLMProvider(
        KoboldService(storage),
        active,
        storage,
        BackendManager(storage),
      );
      final svc = provider.serviceForModel('Qwen3.8-27B-MLX-8bit');
      expect(svc, isA<OpenRouterService>());
      expect((svc as OpenRouterService).modelName, 'Qwen3.8-27B-MLX-8bit');
      expect(svc.apiUrl, 'http://localhost:8000/v1');
    },
  );

  test(
    'managed local backend ignores the pick (loaded model IS the model)',
    () {
      final provider = _LocalProvider(
        KoboldService(storage),
        active,
        storage,
        BackendManager(storage),
      );
      // The local Kobold service is not running in tests → not ready → null,
      // and crucially NOT an ad-hoc remote service for the picked id.
      expect(provider.serviceForModel('other/model'), isNull);
    },
  );
}
