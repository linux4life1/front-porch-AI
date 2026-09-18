// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_speech_pin_').path;
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
  late _GatedMouth mouth;
  late LLMProvider llm;
  late GpuSwapOccupancy occ;

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
    await storage.initialized;
    await storage.generationSettings.setMaxLength(256);
    await storage.backendSettings.setBackendType('kobold');
    await storage.setWorkerBackendType('omlx');
    await storage.setWorkerRemoteApiUrl(kOmlxApiV1);
    await storage.setWorkerRemoteModelName('mlx-qwen');
    mouth = _GatedMouth(storage);
    llm = LLMProvider(
      mouth,
      OpenRouterService(),
      storage,
      _QuietBackend(storage),
    );
    occ = GpuSwapOccupancy(
      mouth: _RecHost('mouth'),
      worker: _RecHost('worker'),
    );
    llm.debugGpuSwap = occ;
    chat =
        ChatService(
            mouth,
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage))
          ..setLLMProvider(llm);
    await chat.setActiveCharacter(
      CharacterCard(
        name: 'Flora',
        description: 'Speech pin.',
        firstMessage: 'Hi.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: false,
          needsSimEnabled: false,
          chaosModeEnabled: false,
        ),
      )..dbId = 'char-speech-pin',
    );
  });

  tearDown(() async {
    chat.dispose();
    llm.dispose();
    await db.close();
  });

  test(
    'restore-mouth generate then post unload; not unload before generate',
    () async {
      await llm.withWorkerLane(() async {});
      expect(occ.steps, ['unload-mouth:mouth', 'prepare-worker:worker']);

      final send = chat.sendMessage('Hello there.');
      await mouth.started.future.timeout(const Duration(seconds: 5));
      expect(occ.steps.last, 'restore-mouth:mouth');
      expect(
        occ.steps.where((s) => s.startsWith('unload-mouth')).length,
        1,
        reason: 'regression: post-eval unload ran before generate',
      );

      final raced = llm.openWorkerLane();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        occ.steps.where((s) => s.startsWith('unload-mouth')).length,
        1,
        reason: 'speech pin must block post-eval unload until mouth finishes',
      );
      expect(mouth.generateStarts, 1);

      mouth.release();
      await send;
      await raced;
      expect(
        occ.steps.where((s) => s.startsWith('unload-mouth')).length,
        2,
        reason: 'post-eval unload must follow generate',
      );
      expect(occ.steps, contains('restore-mouth:mouth'));
    },
  );

  test('empty mouth stream after PRE-GEN is a visible failure', () async {
    mouth.yieldText = false;
    mouth.release();
    await chat.sendMessage('Hello there.');
    final reply = chat.messages.last;
    expect(reply.isUser, isFalse);
    expect(reply.text, isNot(isEmpty));
    expect(reply.text, kEmptySpeechAfterPregenNotice);
  });

  test(
    'waitForWorkerLaneIdle(pinSpeech) blocks hold until endMouthSpeech',
    () async {
      await llm.withWorkerLane(() async {});
      await llm.waitForWorkerLaneIdle(pinSpeech: true);
      expect(occ.steps.last, 'restore-mouth:mouth');
      expect(occ.speechHeld, isTrue);

      final post = llm.openWorkerLane();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        occ.steps.where((s) => s.startsWith('unload-mouth')).length,
        1,
        reason: 'call-site pinSpeech must hold unload until endMouthSpeech',
      );
      llm.endMouthSpeech();
      await post;
      expect(occ.steps.where((s) => s.startsWith('unload-mouth')).length, 2);
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

class _GatedMouth extends KoboldService {
  _GatedMouth(super.storage);

  int generateStarts = 0;
  bool yieldText = true;
  final Completer<void> started = Completer<void>();
  final Completer<void> _hold = Completer<void>();

  void release() {
    if (!_hold.isCompleted) _hold.complete();
  }

  @override
  bool get isReady => true;

  @override
  bool get isProcessRunning => true;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    generateStarts++;
    if (!started.isCompleted) started.complete();
    await _hold.future;
    if (yieldText) yield 'Hi from mouth.';
  }

  @override
  Future<void> reconnectIfAlive() async {}

  @override
  Future<void> ensureServerIdle() async {}

  @override
  Future<void> waitForIdle() async {}
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
