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

  LLMProvider managedProvider(_RecordingKobold kobold) =>
      LLMProvider(kobold, mouthRemote, storage, _FixedPathBackend(storage));

  test(
    'API+API: worker is a second service; mouth URL/model stay put',
    () async {
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
    },
  );

  test('same host, different model ids — two remotes, one vault URL', () async {
    await storage.setRemoteApiUrl(kNanoGptApiV1);
    await storage.setRemoteModelName('moonshotai/kimi-k2.6:thinking');
    await storage.setRemoteApiKeyFor(kNanoGptApiV1, 'shared-nano');
    await storage.setWorkerBackendType('openRouter');
    await storage.setWorkerRemoteApiUrl(kNanoGptApiV1);
    await storage.setWorkerRemoteModelName('z-ai/glm-5.3');

    final p = provider();
    expect(p.workerRefusedDualLocal, isFalse);
    expect(identical(p.workerRemoteService, p.openRouterService), isFalse);
    expect(p.openRouterService.apiUrl, kNanoGptApiV1);
    expect(
      p.openRouterService.modelName,
      'moonshotai/kimi-k2.6:thinking',
      reason: 'same-host worker must not overwrite the mouth model id',
    );
    expect(p.workerRemoteService.apiUrl, kNanoGptApiV1);
    expect(p.workerRemoteService.modelName, 'z-ai/glm-5.3');
    expect(p.openRouterService.apiKey, 'shared-nano');
    expect(
      p.workerRemoteService.apiKey,
      'shared-nano',
      reason: 'same host reuses the per-URL key vault',
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

  test(
    'API mouth + Kobold worker: ensure starts Kobold; mouth stays remote',
    () async {
      await storage.setWorkerBackendType('kobold');
      await storage.setLastUsedModelPath('/tmp/worker-model.gguf');
      final kobold = _RecordingKobold(storage);
      final p = managedProvider(kobold);
      addTearDown(p.dispose);

      expect(p.workerRefusedDualLocal, isFalse);
      expect(p.workerService, same(kobold));
      expect(identical(p.activeService, mouthRemote), isTrue);

      await p.ensureManagedBackendIsRunning();
      expect(
        kobold.startCalls,
        1,
        reason: 'API mouth must still start a Kobold worker',
      );
      expect(kobold.lastExe, '/tmp/fake-koboldcpp');
      expect(identical(p.activeService, mouthRemote), isTrue);
    },
  );

  test('API+API ensure does not start Kobold', () async {
    await storage.setWorkerBackendType('openRouter');
    await storage.setWorkerRemoteApiUrl(kNanoGptApiV1);
    await storage.setWorkerRemoteModelName('z-ai/glm-5.3');
    await storage.setLastUsedModelPath('/tmp/worker-model.gguf');
    final kobold = _RecordingKobold(storage);
    final p = managedProvider(kobold);
    addTearDown(p.dispose);

    await p.ensureManagedBackendIsRunning();
    expect(kobold.startCalls, 0);
  });

  test('refused dual-local does not start a Kobold worker', () async {
    await storage.setBackendType('omlx');
    await storage.setWorkerBackendType('kobold');
    await storage.setLastUsedModelPath('/tmp/worker-model.gguf');
    final kobold = _RecordingKobold(storage);
    final p = managedProvider(kobold);
    addTearDown(p.dispose);

    expect(p.workerRefusedDualLocal, isTrue);
    await p.ensureManagedBackendIsRunning();
    expect(kobold.startCalls, 0);
  });

  test('API mouth + oMLX worker starts the oMLX poller', () async {
    await storage.setWorkerBackendType('omlx');
    await storage.setWorkerRemoteApiUrl(kOmlxApiV1);
    await storage.setWorkerRemoteModelName('local-mlx');
    final p = provider();
    addTearDown(p.dispose);

    expect(p.workerRefusedDualLocal, isFalse);
    expect(
      p.debugOmlxPollerStarted,
      isTrue,
      reason: 'oMLX worker must be polled even when the mouth is remote',
    );
  });

  test('key typed last still configures the worker remote', () async {
    await storage.setWorkerBackendType('openRouter');
    await storage.setWorkerRemoteApiUrl(kNanoGptApiV1);
    await storage.setWorkerRemoteModelName('z-ai/glm-5.3');
    final p = provider();
    addTearDown(p.dispose);
    expect(p.workerRemoteService.apiKey, isNot('late-nano-key'));

    await storage.setRemoteApiKeyFor(kNanoGptApiV1, 'late-nano-key');
    expect(
      p.workerRemoteService.apiKey,
      'late-nano-key',
      reason: 'vault key change must reconfigure the worker',
    );
    expect(p.openRouterService.apiKey, 'or-key');
  });

  test('same-host key refresh updates mouth and worker', () async {
    await storage.setRemoteApiUrl(kNanoGptApiV1);
    await storage.setRemoteModelName('moonshotai/kimi-k2.6:thinking');
    await storage.setRemoteApiKeyFor(kNanoGptApiV1, 'first-nano');
    await storage.setWorkerBackendType('openRouter');
    await storage.setWorkerRemoteApiUrl(kNanoGptApiV1);
    await storage.setWorkerRemoteModelName('z-ai/glm-5.3');
    final p = provider();
    addTearDown(p.dispose);
    expect(p.workerRemoteService.apiKey, 'first-nano');

    await storage.setRemoteApiKeyFor(kNanoGptApiV1, 'refreshed-nano');
    expect(p.openRouterService.apiKey, 'refreshed-nano');
    expect(p.workerRemoteService.apiKey, 'refreshed-nano');
  });

  test('API mouth + unstarted Kobold worker surfaces unready copy', () async {
    await storage.setWorkerBackendType('kobold');
    final p = provider();
    addTearDown(p.dispose);
    expect(p.workerService, isNotNull);
    expect(p.workerService!.isReady, isFalse);
    expect(p.workerUnreadyMessage, contains('KoboldCPP'));
    expect(p.workerUnreadyMessage, contains('Side jobs'));
  });

  test('empty worker does not start the oMLX poller on a remote mouth', () {
    final p = provider();
    addTearDown(p.dispose);
    expect(p.debugOmlxPollerStarted, isFalse);
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

class _RecordingKobold extends KoboldService {
  _RecordingKobold(super.storage);

  int startCalls = 0;
  String? lastExe;

  @override
  Future<void> startKobold(
    String executablePath,
    String modelPath, {
    String? kcppsPath,
    String? mmprojPath,
    int port = 5001,
    int gpuLayers = 0,
    int contextSize = 4096,
    bool useVulkan = false,
    bool useCublas = false,
    bool useMetal = false,
    bool useRocm = false,
  }) async {
    startCalls++;
    lastExe = executablePath;
  }
}

class _FixedPathBackend extends BackendManager {
  _FixedPathBackend(super.storage);

  @override
  String? get backendPath => '/tmp/fake-koboldcpp';
}
