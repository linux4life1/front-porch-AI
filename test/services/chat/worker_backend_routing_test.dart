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
          return Directory.systemTemp.createTempSync('fpai_docs_').path;
        }
        return null;
      });
}

class _HangUntilAbort extends _RecordingLlm {
  _HangUntilAbort(super.backendName);

  @override
  void abortGeneration() {
    abortCalls++;
    if (!_released.isCompleted) _released.complete();
  }

  final Completer<void> _released = Completer<void>();

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    streamCalls++;
    streamPrompts.add(params.prompt);
    await _released.future;
  }
}

class _RecordingLlm extends LLMService {
  _RecordingLlm(this.backendName);

  int streamCalls = 0;
  int toolsCalls = 0;
  int abortCalls = 0;
  final List<String> streamPrompts = [];
  final List<String> toolsIdentities = [];

  @override
  final String backendName;

  @override
  bool get isReady => true;

  @override
  void abortGeneration() {
    abortCalls++;
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    streamCalls++;
    streamPrompts.add(params.prompt);
    yield '{"ok":true} Hello from $backendName.';
  }

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    toolsCalls++;
    toolsIdentities.add(params.backendIdentity);
    return const LlmToolResponse(calls: [], text: '');
  }
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
    await storage.webSearchSettings.setSearchApiKey('bs-test');
    await storage.webSearchSettings.setWebSearchDefault(true);
  });

  tearDown(() async {
    chat.dispose();
    await db.close();
  });

  CharacterCard card() => CharacterCard(
    name: 'Mara',
    description: 'Worker-lane routing only.',
    firstMessage: 'Hi.',
    frontPorchExtensions: FrontPorchExtensions(
      realismEnabled: false,
      needsSimEnabled: false,
      chaosModeEnabled: false,
    ),
  )..dbId = 'char-worker-1';

  Future<void> drainTurn() async {
    for (
      var i = 0;
      i < 400 && (chat.isGenerating || chat.isSettlingTurn);
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  test(
    'worker override: evals and identity hit worker; mouth stays mouth',
    () async {
      expect(identical(chat.debugMouthLlm, mouth), isTrue);
      expect(identical(chat.debugSideLaneLlm, worker), isTrue);
      expect(chat.debugEvalBackendIdentity, startsWith('worker|'));
      expect(chat.debugEvalBackendIdentity, isNot(contains('|mouth|')));

      final raw = await chat.debugFireSideLaneEval('{"bond_delta":0}');
      expect(raw, isNotNull);
      expect(worker.streamCalls, greaterThan(0));
      expect(mouth.streamCalls, 0);
    },
  );

  test('clerk doorbell hits worker; spoken stream stays on mouth', () async {
    await chat.setActiveCharacter(card());
    await chat.sendMessage('Who is the Wandenreich?');
    await drainTurn();

    expect(worker.toolsCalls, greaterThan(0), reason: 'clerk is the worker');
    expect(mouth.toolsCalls, 0, reason: 'mouth must not run the doorbell');
    expect(mouth.streamCalls, greaterThan(0), reason: 'spoken reply is mouth');
    expect(worker.toolsIdentities, everyElement(startsWith('worker|')));
  });

  test(
    'worker off: side lane and identity fall back to the mouth override',
    () {
      chat.testWorkerLlmServiceOverride = null;
      expect(identical(chat.debugSideLaneLlm, mouth), isTrue);
      expect(identical(chat.debugMouthLlm, mouth), isTrue);
      expect(chat.debugEvalBackendIdentity, isNot(startsWith('worker|')));
    },
  );

  test('cancel aborts mouth and worker, not mouth only', () async {
    await chat.cancelRealismEval();
    expect(mouth.abortCalls, 1);
    expect(worker.abortCalls, 1);
  });

  test('stopGeneration while speaking aborts both lanes', () async {
    await chat.setActiveCharacter(card());
    final hangMouth = _HangUntilAbort('mouth');
    chat.testLlmServiceOverride = hangMouth;
    final send = chat.sendMessage('Hello there.');
    for (var i = 0; i < 200 && !chat.isGenerating; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(chat.isGenerating, isTrue);
    chat.stopGeneration();
    await send;
    await drainTurn();
    expect(hangMouth.abortCalls, greaterThan(0));
    expect(worker.abortCalls, greaterThan(0));
  });

  test(
    'dual-local refuse: clerk and evals hit the mouth, not a worker',
    () async {
      chat.testLlmServiceOverride = null;
      chat.testWorkerLlmServiceOverride = null;
      await storage.setBackendType('kobold');
      await storage.setWorkerBackendType('omlx');
      await storage.setWorkerRemoteApiUrl(kOmlxApiV1);
      final mouthKobold = _RecordingMouthKobold(storage);
      final llm = LLMProvider(
        mouthKobold,
        OpenRouterService(),
        storage,
        _QuietBackend(storage),
      );
      addTearDown(llm.dispose);
      chat.setLLMProvider(llm);

      expect(llm.workerService, isNull);
      expect(llm.workerRefusedDualLocal, isTrue);
      expect(identical(chat.debugSideLaneLlm, mouthKobold), isTrue);
      expect(identical(chat.debugMouthLlm, mouthKobold), isTrue);
      expect(chat.debugEvalBackendIdentity, isNot(startsWith('worker|')));

      final raw = await chat.debugFireSideLaneEval('{"bond_delta":0}');
      expect(raw, isNotNull);
      expect(
        mouthKobold.streamCalls,
        greaterThan(0),
        reason: 'refused worker must not steal evals from the mouth',
      );

      await chat.setActiveCharacter(card());
      await chat.sendMessage('Who is the Wandenreich?');
      await drainTurn();
      expect(
        mouthKobold.toolsCalls,
        greaterThan(0),
        reason: 'clerk stays on the mouth when the worker pair is refused',
      );
      expect(
        mouthKobold.toolsIdentities,
        everyElement(isNot(startsWith('worker|'))),
      );
    },
  );
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

  int streamCalls = 0;
  int toolsCalls = 0;
  final List<String> toolsIdentities = [];

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

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    streamCalls++;
    yield '{"ok":true} Hello from mouth.';
  }

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    toolsCalls++;
    toolsIdentities.add(params.backendIdentity);
    return const LlmToolResponse(calls: [], text: '');
  }
}
