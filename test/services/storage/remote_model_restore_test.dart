// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Switching OpenRouter → Nano-GPT → OpenRouter brings back the model last
// used on each host: desktop provider bar, Realism evals host, a restart,
// and the web relay. KoboldCpp has no remote model and never lends one.

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

const _grok = 'x-ai/grok-4.6';
const _kimi = 'moonshotai/kimi-k2.6:thinking';

void _mockPathProvider() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp
              .createTempSync('fpai_model_restore_')
              .path;
        }
        return null;
      });
}

Future<StorageService> _storage({bool fresh = true}) async {
  if (fresh) SharedPreferences.setMockInitialValues({});
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

  test('provider bar: each host gets its own last model back', () async {
    final storage = await _storage();
    addTearDown(storage.dispose);
    final llm = _Llm(storage);
    addTearDown(llm.dispose);
    await storage.backendSettings.setBackendType('openRouter');
    await storage.backendSettings.setRemoteApiUrl(kOpenRouterApiV1);
    await storage.backendSettings.setRemoteModelName(_grok);
    final model = TextEditingController(text: _grok);
    addTearDown(model.dispose);

    Future<void> tap(RemoteProviderKind kind) => applyRemoteProvider(
      kind: kind,
      storage: storage,
      llm: llm,
      modelController: model,
    );

    await tap(RemoteProviderKind.nanoGpt);
    expect(model.text, isEmpty, reason: 'Nano-GPT has no model yet');
    await storage.backendSettings.setRemoteModelName(_kimi);

    await tap(RemoteProviderKind.openRouter);
    expect(storage.backendSettings.remoteModelName, _grok);
    expect(model.text, _grok);

    await tap(RemoteProviderKind.kobold);
    expect(storage.backendSettings.remoteModelName, isEmpty);

    await tap(RemoteProviderKind.nanoGpt);
    expect(storage.backendSettings.remoteModelName, _kimi);
    expect(model.text, _kimi);
  });

  test('the remembered models survive a restart', () async {
    final first = await _storage();
    await first.backendSettings.setBackendType('openRouter');
    await first.backendSettings.setRemoteApiUrl(kOpenRouterApiV1);
    await first.backendSettings.setRemoteModelName(_grok);
    await first.backendSettings.setRemoteApiUrl(kNanoGptApiV1);
    await first.backendSettings.setRemoteModelName(_kimi);
    await first.setWorkerBackendType('openRouter');
    await first.setWorkerRemoteApiUrl(kNanoGptApiV1);
    await first.setWorkerRemoteModelName(_kimi);
    await first.setWorkerRemoteApiUrl(kOpenRouterApiV1);
    await first.setWorkerRemoteModelName(_grok);
    first.dispose();

    final again = await _storage(fresh: false);
    addTearDown(again.dispose);
    expect(again.backendSettings.remoteModelName, _kimi);
    await again.backendSettings.setRemoteApiUrl(kOpenRouterApiV1);
    expect(again.backendSettings.remoteModelName, _grok);
    expect(again.workerRemoteModelName, _grok);
    await again.setWorkerRemoteApiUrl(kNanoGptApiV1);
    expect(again.workerRemoteModelName, _kimi);
  });

  test('Realism evals host: each host gets its own last model back', () async {
    final storage = await _storage();
    addTearDown(storage.dispose);
    await storage.backendSettings.setRemoteModelName(_grok);
    final model = TextEditingController();
    addTearDown(model.dispose);

    Future<void> tap(RemoteProviderKind? kind) => applyWorkerProvider(
      kind: kind,
      storage: storage,
      modelController: model,
    );

    await tap(RemoteProviderKind.openRouter);
    await storage.setWorkerRemoteModelName('openai/gpt-5');
    await tap(RemoteProviderKind.nanoGpt);
    expect(model.text, isEmpty, reason: 'Nano-GPT has no worker model yet');
    await storage.setWorkerRemoteModelName(_kimi);

    await tap(RemoteProviderKind.openRouter);
    expect(storage.workerRemoteModelName, 'openai/gpt-5');
    expect(model.text, 'openai/gpt-5');

    await tap(RemoteProviderKind.kobold);
    expect(storage.workerRemoteModelName, isEmpty);
    await tap(RemoteProviderKind.nanoGpt);
    expect(storage.workerRemoteModelName, _kimi);

    await tap(null);
    expect(storage.workerRemoteModelName, _kimi, reason: 'same-as-chat');
    expect(
      storage.backendSettings.remoteModelName,
      _grok,
      reason: 'the chat model is its own memory',
    );
  });

  test('web: a host switch with no model restores it, and the snapshot '
      'lists every host\'s last model', () async {
    final storage = await _storage();
    addTearDown(storage.dispose);
    final llm = _Llm(storage);
    addTearDown(llm.dispose);
    await storage.backendSettings.setBackendType('openRouter');
    await storage.backendSettings.setRemoteApiUrl(kOpenRouterApiV1);
    await storage.backendSettings.setRemoteModelName(_grok);
    await storage.backendSettings.setRemoteApiUrl(kNanoGptApiV1);
    await storage.backendSettings.setRemoteModelName(_kimi);
    final facade = SettingsFacade(storage, llm);

    await facade.update({
      'backend': 'openRouter',
      'remoteApiUrl': kOpenRouterApiV1,
    });
    expect(storage.backendSettings.remoteModelName, _grok);

    // An older PWA still sends the previous host's id: skipped, and the
    // restored model stays.
    await facade.update({
      'backend': 'openRouter',
      'remoteApiUrl': kNanoGptApiV1,
      'remoteModelName': _grok,
    });
    expect(storage.backendSettings.remoteModelName, _kimi);

    final models = facade.read()['remoteApiModels'] as Map<String, String>;
    expect(models[normalizeRemoteApiUrl(kOpenRouterApiV1)], _grok);
    expect(models[normalizeRemoteApiUrl(kNanoGptApiV1)], _kimi);
  });

  test('web: the Realism evals host restores and lists its models', () async {
    final storage = await _storage();
    addTearDown(storage.dispose);
    final llm = _Llm(storage);
    addTearDown(llm.dispose);
    await storage.setWorkerBackendType('openRouter');
    await storage.setWorkerRemoteApiUrl(kOpenRouterApiV1);
    await storage.setWorkerRemoteModelName(_grok);
    await storage.setWorkerRemoteApiUrl(kNanoGptApiV1);
    await storage.setWorkerRemoteModelName(_kimi);

    await updateWorkerSettings(
      storage: storage,
      body: {
        'workerBackend': 'openRouter',
        'workerRemoteApiUrl': kOpenRouterApiV1,
      },
    );
    expect(storage.workerRemoteModelName, _grok);
    final models =
        readWorkerSettings(storage, llm)['workerRemoteApiModels']
            as Map<String, String>;
    expect(models[normalizeRemoteApiUrl(kNanoGptApiV1)], _kimi);
  });
}
