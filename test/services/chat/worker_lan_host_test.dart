// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/chat_db_teardown.dart';

const _otherPc = <String>[
  'http://10.1.2.3:5001/v1',
  'http://172.16.0.4:5001/v1',
  'http://172.20.1.8:5001/v1',
  'http://172.31.255.9:5001/v1',
  'http://192.168.1.50:5001/v1',
  'http://100.64.0.8:5001/v1',
  'http://100.127.9.9:5001/v1',
  'http://server.local:5001/v1',
];

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_lan_').path;
        }
        return null;
      });
}

class _Mouth extends KoboldService {
  _Mouth(super.storage);

  int streamCalls = 0;

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
    yield 'mouth';
  }
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('another PC is not this machine for the worker lane', () {
    for (final url in _otherPc) {
      expect(backendLaneIsLocal('openRouter', url), isFalse, reason: url);
      expect(
        workerPairAllowed(
          mouthType: 'kobold',
          mouthUrl: '',
          workerType: 'openRouter',
          workerUrl: url,
        ),
        isTrue,
        reason: url,
      );
      expect(
        localSwapKindFor(backendType: 'openRouter', apiUrl: url),
        isNull,
        reason: url,
      );
      expect(isLocalRemoteUrl(url), isTrue, reason: url);
      expect(evalLaneIsHomeNetwork('openRouter', url), isTrue, reason: url);
    }
  });

  test('the whole 127.0.0.0/8 is this machine', () {
    for (final url in [
      'http://127.0.0.1:5001/v1',
      'http://127.0.0.2:5001/v1',
      'http://127.255.255.255:5001/v1',
    ]) {
      expect(backendLaneIsLocal('openRouter', url), isTrue, reason: url);
      expect(
        workerPairAllowed(
          mouthType: 'kobold',
          mouthUrl: '',
          workerType: 'openRouter',
          workerUrl: url,
        ),
        isFalse,
        reason: url,
      );
    }
  });

  test('loopback names stay on this machine beside managed Kobold', () {
    for (final url in [
      'http://localhost:5001/v1',
      'http://[::1]:5001/v1',
      'http://0.0.0.0:5001/v1',
      kLmStudioApiV1,
      kOmlxApiV1,
    ]) {
      expect(
        workerPairAllowed(
          mouthType: 'kobold',
          mouthUrl: '',
          workerType: 'openRouter',
          workerUrl: url,
        ),
        isFalse,
        reason: url,
      );
    }
    expect(
      workerPairAllowed(
        mouthType: 'kobold',
        mouthUrl: '',
        workerType: 'omlx',
        workerUrl: kOmlxApiV1,
      ),
      isFalse,
    );
    expect(
      workerPairAllowed(
        mouthType: 'kobold',
        mouthUrl: '',
        workerType: 'kobold',
        workerUrl: '',
      ),
      isFalse,
    );
    expect(
      workerPairAllowed(
        mouthType: 'kobold',
        mouthUrl: '',
        workerType: 'openRouter',
        workerUrl: kLmStudioApiV1,
        gpuSwapAvailable: true,
      ),
      isTrue,
    );
  });

  test('a hosts-file name and a cloud mouth stay allowed', () {
    expect(
      workerPairAllowed(
        mouthType: 'kobold',
        mouthUrl: '',
        workerType: 'openRouter',
        workerUrl: 'http://evalbox:5001/v1',
      ),
      isTrue,
    );
    expect(
      workerPairAllowed(
        mouthType: 'openRouter',
        mouthUrl: kOpenRouterApiV1,
        workerType: 'openRouter',
        workerUrl: 'http://192.168.1.50:5001/v1',
      ),
      isTrue,
    );
    expect(isLocalRemoteUrl('http://192.168.1.10:1234/v1'), isTrue);
    expect(isLocalRemoteUrl('http://host.local:1234/v1'), isTrue);
    expect(isLocalRemoteUrl('https://openrouter.ai/api/v1'), isFalse);
  });

  test('side-lane eval posts to the other PC', () async {
    _setupPathProviderMock();
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({'update_auto_check': false});

    for (final url in _otherPc) {
      final db = AppDatabase.forTesting();
      final storage = StorageService();
      final mouth = _Mouth(storage);
      late ChatService chat;
      try {
        await storage.initialized;
        await storage.backendSettings.setBackendType('kobold');
        await storage.backendSettings.setLastUsedModelPath('/models/chat.gguf');
        await storage.setWorkerBackendType('openRouter');
        await storage.setWorkerRemoteApiUrl(url);
        await storage.setWorkerRemoteModelName('qwen');
        await storage.setRemoteApiKeyFor(url, 'second-pc');

        final llm = LLMProvider(
          mouth,
          OpenRouterService(),
          storage,
          _QuietBackend(storage),
        );
        final posts = <Uri>[];
        llm.workerRemoteService.httpClientFactory = () =>
            MockClient((request) async {
              posts.add(request.url);
              expect(request.method, 'POST');
              return http.Response(
                'data: ${jsonEncode({
                  'choices': [
                    {
                      'delta': {'content': '{"ok":true}'},
                    },
                  ],
                })}\n\n'
                'data: [DONE]\n',
                200,
              );
            });

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

        expect(llm.workerRefusedDualLocal, isFalse, reason: url);
        expect(identical(llm.sideLaneService, llm.workerRemoteService), isTrue);
        expect(identical(llm.activeService, mouth), isTrue);

        final raw = await chat.debugFireSideLaneEval('{"bond_delta":0}');
        expect(mouth.streamCalls, 0, reason: url);
        expect(raw, contains('ok'), reason: url);
        expect(posts, isNotEmpty, reason: url);
        expect(
          posts.every((u) => u.toString() == '$url/chat/completions'),
          isTrue,
          reason: posts.map((u) => u.toString()).join(', '),
        );
        llm.dispose();
      } finally {
        await disposeChatThenCloseDb(chat, db);
      }
    }
  });
}
