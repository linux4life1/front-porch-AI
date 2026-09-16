// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
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

class _RecordingLlm extends LLMService {
  _RecordingLlm(this.backendName);

  int streamCalls = 0;
  int toolsCalls = 0;
  final List<String> streamPrompts = [];
  final List<String> toolsIdentities = [];

  @override
  final String backendName;

  @override
  bool get isReady => true;

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

  test('call sites in wiring use the side-lane getters', () {
    final evals = File(
      'lib/services/chat/chat_service_wiring_evals.dart',
    ).readAsStringSync();
    expect(evals, contains('getLlmService: () => _sideLaneLlm'));
    expect(evals, contains('final service = _sideLaneLlm;'));
    expect(evals, contains('workerEvalIdentityFor('));

    final request = File(
      'lib/services/chat/chat_service_generation_request.dart',
    ).readAsStringSync();
    expect(request, contains('llm: sideLaneLlm'));
    expect(request, contains('t.stream = llmService.generateStream'));
    expect(request, contains('final llmService = _mouthLlm;'));

    final clerk = File(
      'lib/services/chat/catalog_clerk.dart',
    ).readAsStringSync();
    expect(
      clerk,
      contains('backendIdentity: backendIdentity ?? mouth.backendIdentity'),
    );
  });
}
