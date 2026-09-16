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
          final tmp = Directory.systemTemp.createTempSync('fpai_swap_');
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
    await storage.setBackendType('kobold');
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

  test('injected swap allows dual-local and uses the worker service', () async {
    await storage.setWorkerBackendType('omlx');
    await storage.setWorkerRemoteApiUrl(kOmlxApiV1);
    await storage.setWorkerRemoteModelName('mlx-qwen');
    await storage.setRemoteApiKeyFor(kOmlxApiV1, 'omlx-key');

    final p = provider();
    addTearDown(p.dispose);
    expect(p.workerRefusedDualLocal, isTrue);
    expect(p.workerService, isNull);

    final occ = GpuSwapOccupancy(
      mouth: _RecHost('mouth'),
      worker: _RecHost('worker'),
    );
    p.debugGpuSwap = occ;
    expect(p.workerGpuSwapAvailable, isTrue);
    expect(p.workerRefusedDualLocal, isFalse);
    expect(p.workerService, isNotNull);
    expect(identical(p.workerService, p.activeService), isFalse);
    expect(p.sideLaneService, same(p.workerService));
    expect(p.workerEvalIdentity, startsWith('worker|'));
  });

  test(
    'withWorkerLane leaves worker hot; next lane does not re-swap',
    () async {
      await storage.setWorkerBackendType('omlx');
      await storage.setWorkerRemoteApiUrl(kOmlxApiV1);
      await storage.setWorkerRemoteModelName('mlx-qwen');
      final p = provider();
      addTearDown(p.dispose);
      final occ = GpuSwapOccupancy(
        mouth: _RecHost('mouth'),
        worker: _RecHost('worker'),
      );
      p.debugGpuSwap = occ;

      var workAt = -1;
      await p.withWorkerLane(() async {
        workAt = occ.steps.length;
        expect(occ.steps, ['unload-mouth:mouth', 'prepare-worker:worker']);
      });
      expect(workAt, 2);
      expect(occ.mouthDown, isTrue);
      expect(occ.steps.last, 'prepare-worker:worker');

      await p.withWorkerLane(() async {});
      expect(
        occ.steps.where((s) => s.startsWith('unload-mouth')).length,
        1,
        reason: 'next pre-eval must not unload/reload mouth first',
      );
      expect(occ.steps.where((s) => s.startsWith('prepare-worker')).length, 1);
      expect(occ.mouthDown, isTrue);

      await p.waitForWorkerLaneIdle();
      expect(occ.steps.last, 'restore-mouth:mouth');
      expect(occ.mouthDown, isFalse);
    },
  );

  test(
    'waitForWorkerLaneIdle does not return until mouth restore finishes',
    () async {
      await storage.setWorkerBackendType('omlx');
      await storage.setWorkerRemoteApiUrl(kOmlxApiV1);
      await storage.setWorkerRemoteModelName('mlx-qwen');
      final p = provider();
      addTearDown(p.dispose);
      var restoreDone = false;
      final occ = GpuSwapOccupancy(
        mouth: _SlowRestoreHost('mouth', () async {
          await Future<void>.delayed(const Duration(milliseconds: 60));
          restoreDone = true;
        }),
        worker: _RecHost('worker'),
      );
      p.debugGpuSwap = occ;
      await p.withWorkerLane(() async {});
      expect(restoreDone, isFalse, reason: 'release must leave worker hot');
      final wait = p.waitForWorkerLaneIdle();
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(
        restoreDone,
        isFalse,
        reason: 'wait must not return during restore tail',
      );
      await wait;
      expect(restoreDone, isTrue);
      expect(occ.mouthDown, isFalse);
    },
  );

  test(
    'mid-hold occupancy replace still restores the acquired instance',
    () async {
      await storage.setWorkerBackendType('omlx');
      await storage.setWorkerRemoteApiUrl(kOmlxApiV1);
      await storage.setWorkerRemoteModelName('mlx-qwen');
      final p = provider();
      addTearDown(p.dispose);
      final first = GpuSwapOccupancy(
        mouth: _RecHost('mouth'),
        worker: _RecHost('worker'),
      );
      p.debugGpuSwap = first;
      await p.openWorkerLane();
      expect(first.steps, ['unload-mouth:mouth', 'prepare-worker:worker']);
      expect(first.isHeld, isTrue);
      final expandoBefore = p.debugGpuSwapExpando;

      await storage.setWorkerRemoteModelName('other-mlx');
      expect(
        identical(p.debugGpuSwapExpando, expandoBefore),
        isTrue,
        reason: 'mid-hold _rebuildGpuSwap must not mint a second occupancy',
      );
      expect(identical(p.debugGpuSwap, first), isTrue);

      final second = GpuSwapOccupancy(
        mouth: _RecHost('mouth2'),
        worker: _RecHost('worker2'),
      );
      p.debugGpuSwap = second;

      await p.withWorkerLane(() async {});
      await p.closeWorkerLane();

      expect(second.steps, isEmpty, reason: 'replacement must not swap');
      expect(first.steps.where((s) => s.startsWith('unload-mouth')).length, 1);
      expect(first.mouthDown, isTrue);
      expect(first.isHeld, isFalse);
      expect(
        identical(p.debugGpuSwap, first),
        isTrue,
        reason: 'dirty rebuild must not drop the mouthDown occupancy',
      );
      await p.waitForWorkerLaneIdle();
      expect(first.steps.last, 'restore-mouth:mouth');
      expect(first.mouthDown, isFalse);
    },
  );

  test('V1 pairs still expose a worker without needing a swap', () async {
    await storage.setBackendType('openRouter');
    await storage.setRemoteApiUrl(kOpenRouterApiV1);
    await storage.setRemoteModelName('x-ai/grok-4.6');
    await storage.setRemoteApiKey('or-key');
    await storage.setWorkerBackendType('openRouter');
    await storage.setWorkerRemoteApiUrl(kNanoGptApiV1);
    await storage.setWorkerRemoteModelName('z-ai/glm-5.3');
    await storage.setRemoteApiKeyFor(kNanoGptApiV1, 'nano-key');

    final p = provider();
    addTearDown(p.dispose);
    expect(p.workerRefusedDualLocal, isFalse);
    expect(p.workerService, isNotNull);
    await p.withWorkerLane(() async {});
    expect(p.debugGpuSwap, isNull);
  });
}

class _RecHost implements GpuSwapHost {
  _RecHost(this.label);

  @override
  final String label;

  @override
  Future<void> unload() async {}

  @override
  Future<void> restore() async {}
}

class _SlowRestoreHost implements GpuSwapHost {
  _SlowRestoreHost(this.label, this.onRestore);

  @override
  final String label;
  final Future<void> Function() onRestore;

  @override
  Future<void> unload() async {}

  @override
  Future<void> restore() => onRestore();
}
