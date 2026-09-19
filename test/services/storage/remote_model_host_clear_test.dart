// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Host/type change must blank the live model picker. Worker clears only
// its own remote model. lastUsedModelPath and same-as-chat stay put.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';
import 'package:front_porch_ai/services/storage/settings/remote_provider.dart';
import 'package:front_porch_ai/services/web/facade/settings_facade.dart';
import 'package:front_porch_ai/services/web/facade/settings_worker.dart';
import 'package:front_porch_ai/ui/settings/widgets/remote_provider_apply.dart';
import 'package:front_porch_ai/ui/settings/widgets/worker_provider_apply.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../golden/support/fakes.dart';

void _mockPathProvider() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_host_clear_').path;
        }
        return null;
      });
}

Future<StorageService> _storage() async {
  SharedPreferences.setMockInitialValues({});
  final service = StorageService();
  await service.initialized;
  return service;
}

class _Llm extends FakeLLMProvider {
  _Llm(this.storage) : super(activeBackend: BackendType.openRouter);

  final StorageService storage;
  final OpenRouterService remote = OpenRouterService();
  BackendType _type = BackendType.openRouter;

  @override
  BackendType get activeBackend => _type;

  @override
  OpenRouterService get openRouterService => remote;

  @override
  Future<void> setActiveBackend(BackendType type) async {
    if (type == _type) return;
    _type = type;
    await storage.backendSettings.setBackendType(switch (type) {
      BackendType.kobold => 'kobold',
      BackendType.omlx => 'omlx',
      BackendType.openRouter => 'openRouter',
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _mockPathProvider();

  test('Kobold ↔ OpenRouter clears even when they share a URL slot', () async {
    final storage = await _storage();
    addTearDown(storage.dispose);
    await storage.backendSettings.setBackendType('openRouter');
    await storage.backendSettings.setRemoteApiUrl(kOpenRouterApiV1);
    await storage.backendSettings.setRemoteModelName('x-ai/grok-4.6');
    await storage.backendSettings.setLastUsedModelPath('/models/chat.gguf');

    await storage.backendSettings.setBackendType('kobold');
    expect(storage.backendSettings.remoteModelName, isEmpty);
    expect(storage.backendSettings.lastUsedModelPath, '/models/chat.gguf');

    await storage.backendSettings.setRemoteModelName('should-not-stick');
    await storage.backendSettings.setBackendType('openRouter');
    expect(storage.backendSettings.remoteModelName, isEmpty);
    expect(storage.backendSettings.lastUsedModelPath, '/models/chat.gguf');
  });

  test(
    'leaving a host with an empty picker does not wipe the parked vault',
    () async {
      final storage = await _storage();
      addTearDown(storage.dispose);
      await storage.backendSettings.setRemoteApiUrl(kOpenRouterApiV1);
      await storage.backendSettings.setRemoteModelName('x-ai/grok-4.6');
      await storage.backendSettings.setRemoteApiUrl(kNanoGptApiV1);
      expect(
        storage.backendSettings.remoteApiModelFor(kOpenRouterApiV1),
        'x-ai/grok-4.6',
      );

      await storage.backendSettings.setRemoteApiUrl(kOpenRouterApiV1);
      expect(storage.backendSettings.remoteModelName, isEmpty);
      expect(
        storage.backendSettings.remoteApiModelFor(kOpenRouterApiV1),
        'x-ai/grok-4.6',
        reason: 'stash must not put an empty live id over a parked vault entry',
      );
    },
  );

  test('equivalent URL rewrite does not clear the live model', () async {
    final storage = await _storage();
    addTearDown(storage.dispose);
    await storage.backendSettings.setRemoteApiUrl(kOpenRouterApiV1);
    await storage.backendSettings.setRemoteModelName('x-ai/grok-4.6');

    await storage.backendSettings.setRemoteApiUrl(kOpenRouterApiV1);
    expect(storage.backendSettings.remoteModelName, 'x-ai/grok-4.6');
  });

  test('worker host change clears only the worker model', () async {
    final storage = await _storage();
    addTearDown(storage.dispose);
    await storage.backendSettings.setBackendType('openRouter');
    await storage.backendSettings.setRemoteApiUrl(kOpenRouterApiV1);
    await storage.backendSettings.setRemoteModelName('x-ai/grok-4.6');
    await storage.backendSettings.setLastUsedModelPath('/models/chat.gguf');
    await storage.setWorkerBackendType('openRouter');
    await storage.setWorkerRemoteApiUrl(kNanoGptApiV1);
    await storage.setWorkerRemoteModelName('moonshotai/kimi-k2.6:thinking');

    await storage.setWorkerBackendType('openRouter');
    await storage.setWorkerRemoteApiUrl(kOpenRouterApiV1);
    expect(storage.workerRemoteModelName, isEmpty);
    expect(storage.backendSettings.remoteModelName, 'x-ai/grok-4.6');
    expect(storage.backendSettings.lastUsedModelPath, '/models/chat.gguf');
  });

  test('same-as-chat does not thrash the parked worker model', () async {
    final storage = await _storage();
    addTearDown(storage.dispose);
    await storage.setWorkerBackendType('openRouter');
    await storage.setWorkerRemoteApiUrl(kNanoGptApiV1);
    await storage.setWorkerRemoteModelName('moonshotai/kimi-k2.6:thinking');

    await storage.setWorkerBackendType('');
    expect(storage.workerRemoteModelName, 'moonshotai/kimi-k2.6:thinking');
  });

  test('applyRemoteProvider blanks the model controller', () async {
    final storage = await _storage();
    addTearDown(storage.dispose);
    final llm = _Llm(storage);
    addTearDown(llm.dispose);
    await storage.backendSettings.setBackendType('openRouter');
    await storage.backendSettings.setRemoteApiUrl(kOpenRouterApiV1);
    await storage.backendSettings.setRemoteModelName('x-ai/grok-4.6');
    final model = TextEditingController(text: 'x-ai/grok-4.6');
    addTearDown(model.dispose);

    await applyRemoteProvider(
      kind: RemoteProviderKind.nanoGpt,
      storage: storage,
      llm: llm,
      modelController: model,
    );
    expect(storage.backendSettings.remoteModelName, isEmpty);
    expect(model.text, isEmpty);

    await storage.backendSettings.setRemoteModelName('moonshotai/kimi');
    model.text = 'moonshotai/kimi';
    await applyRemoteProvider(
      kind: RemoteProviderKind.kobold,
      storage: storage,
      llm: llm,
      modelController: model,
    );
    expect(storage.backendSettings.remoteModelName, isEmpty);
    expect(model.text, isEmpty);
  });

  test('applyWorkerProvider blanks only the worker model', () async {
    final storage = await _storage();
    addTearDown(storage.dispose);
    await storage.backendSettings.setRemoteModelName('x-ai/grok-4.6');
    await storage.setWorkerBackendType('openRouter');
    await storage.setWorkerRemoteApiUrl(kNanoGptApiV1);
    await storage.setWorkerRemoteModelName('moonshotai/kimi');
    final model = TextEditingController(text: 'moonshotai/kimi');
    addTearDown(model.dispose);

    await applyWorkerProvider(
      kind: RemoteProviderKind.openRouter,
      storage: storage,
      modelController: model,
    );
    expect(storage.workerRemoteModelName, isEmpty);
    expect(model.text, isEmpty);
    expect(storage.backendSettings.remoteModelName, 'x-ai/grok-4.6');
  });

  test('web leftover model is ignored; a new pick still lands', () async {
    final storage = await _storage();
    addTearDown(storage.dispose);
    final llm = _Llm(storage);
    addTearDown(llm.dispose);
    await storage.backendSettings.setBackendType('openRouter');
    await storage.backendSettings.setRemoteApiUrl(kOpenRouterApiV1);
    await storage.backendSettings.setRemoteModelName('x-ai/grok-4.6');
    final facade = SettingsFacade(storage, llm);

    await facade.update({
      'backend': 'openRouter',
      'remoteApiUrl': kNanoGptApiV1,
      'remoteModelName': 'x-ai/grok-4.6',
    });
    expect(storage.backendSettings.remoteModelName, isEmpty);

    await storage.backendSettings.setRemoteModelName('parked');
    await facade.update({
      'backend': 'openRouter',
      'remoteApiUrl': kOpenRouterApiV1,
      'remoteModelName': 'openai/gpt-5',
    });
    expect(storage.backendSettings.remoteModelName, 'openai/gpt-5');
  });

  test('web leftover worker model is ignored on host change', () async {
    final storage = await _storage();
    addTearDown(storage.dispose);
    await storage.setWorkerBackendType('openRouter');
    await storage.setWorkerRemoteApiUrl(kNanoGptApiV1);
    await storage.setWorkerRemoteModelName('moonshotai/kimi');

    await updateWorkerSettings(
      storage: storage,
      body: {
        'workerBackend': 'openRouter',
        'workerRemoteApiUrl': kOpenRouterApiV1,
        'workerRemoteModelName': 'moonshotai/kimi',
      },
    );
    expect(storage.workerRemoteModelName, isEmpty);
  });
}
