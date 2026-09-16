// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_swap_docs_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late _RecordingLlm mouth;
  late _RecordingLlm worker;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
      'pockets_enabled': false,
      'journal_enabled': false,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    mouth = _RecordingLlm('mouth');
    worker = _RecordingLlm('worker');
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage))
          ..testLlmServiceOverride = mouth
          ..testWorkerLlmServiceOverride = worker;
    await storage.initialized;
    await storage.setMaxLength(256);
  });

  tearDown(() async {
    chat.dispose();
    await db.close();
  });

  test(
    'swap-available dual-local routes evals to the worker service',
    () async {
      chat.testLlmServiceOverride = null;
      chat.testWorkerLlmServiceOverride = null;
      await storage.setBackendType('kobold');
      await storage.setWorkerBackendType('omlx');
      await storage.setWorkerRemoteApiUrl(kOmlxApiV1);
      await storage.setWorkerRemoteModelName('mlx-qwen');
      final mouthKobold = _RecordingMouthKobold(storage);
      final llm = LLMProvider(
        mouthKobold,
        OpenRouterService(),
        storage,
        _QuietBackend(storage),
      );
      addTearDown(llm.dispose);
      llm.debugGpuSwap = GpuSwapOccupancy(
        mouth: _RecHost('mouth'),
        worker: _RecHost('worker'),
      );
      chat.setLLMProvider(llm);

      expect(llm.workerRefusedDualLocal, isFalse);
      expect(llm.workerService, isNotNull);
      expect(identical(chat.debugSideLaneLlm, llm.workerService), isTrue);
      expect(identical(chat.debugMouthLlm, mouthKobold), isTrue);
      expect(chat.debugEvalBackendIdentity, startsWith('worker|'));
    },
  );

  test('cancel during a swapped hold still restores mouth', () async {
    chat.testLlmServiceOverride = null;
    chat.testWorkerLlmServiceOverride = null;
    await storage.setBackendType('kobold');
    await storage.setWorkerBackendType('omlx');
    await storage.setWorkerRemoteApiUrl(kOmlxApiV1);
    await storage.setWorkerRemoteModelName('mlx-qwen');
    final llm = LLMProvider(
      _RecordingMouthKobold(storage),
      OpenRouterService(),
      storage,
      _QuietBackend(storage),
    );
    addTearDown(llm.dispose);
    final occ = GpuSwapOccupancy(
      mouth: _RecHost('mouth'),
      worker: _RecHost('worker'),
    );
    llm.debugGpuSwap = occ;
    chat.setLLMProvider(llm);

    final started = Completer<void>();
    final released = Completer<void>();
    final hold = llm.withWorkerLane(() async {
      started.complete();
      await released.future;
    });
    await started.future;
    expect(occ.steps, ['unload-mouth:mouth', 'prepare-worker:worker']);
    await chat.cancelRealismEval();
    released.complete();
    await hold;
    expect(occ.steps.last, 'restore-mouth:mouth');
  });

  test('stop still aborts mouth and worker when a swap is armed', () async {
    final hangMouth = _HangUntilAbort('mouth');
    final hangWorker = _HangUntilAbort('worker');
    chat.testLlmServiceOverride = hangMouth;
    chat.testWorkerLlmServiceOverride = hangWorker;
    await chat.setActiveCharacter(
      CharacterCard(
        name: 'Mara',
        description: 'Swap cancel.',
        firstMessage: 'Hi.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: false,
          needsSimEnabled: false,
          chaosModeEnabled: false,
        ),
      )..dbId = 'char-swap-1',
    );
    final send = chat.sendMessage('Hello there.');
    for (var i = 0; i < 200 && !chat.isGenerating; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    chat.stopGeneration();
    await send;
    expect(hangMouth.abortCalls, greaterThan(0));
    expect(hangWorker.abortCalls, greaterThan(0));
  });
}

class _QuietBackend extends BackendManager {
  _QuietBackend(super.storage);

  @override
  String? get backendPath => '/tmp/fake-koboldcpp';

  @override
  Future<void> checkBackendAvailability() async {}

  @override
  Future<void> ensureEngineInstalled() async {}
}

class _RecordingMouthKobold extends KoboldService {
  _RecordingMouthKobold(super.storage);

  @override
  bool get isReady => true;

  @override
  bool get isProcessRunning => true;

  @override
  Future<void> reconnectIfAlive() async {}

  @override
  Future<void> ensureServerIdle() async {}

  @override
  Future<void> waitForIdle() async {}
}

class _RecordingLlm extends LLMService {
  _RecordingLlm(this.backendName);

  int abortCalls = 0;

  @override
  final String backendName;

  @override
  bool get isReady => true;

  @override
  void abortGeneration() => abortCalls++;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    yield '{"ok":true}';
  }
}

class _HangUntilAbort extends _RecordingLlm {
  _HangUntilAbort(super.backendName);

  final Completer<void> _released = Completer<void>();

  @override
  void abortGeneration() {
    abortCalls++;
    if (!_released.isCompleted) _released.complete();
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    await _released.future;
  }
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
