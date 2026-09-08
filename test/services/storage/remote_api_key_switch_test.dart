// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// OpenRouter ↔ Nano-GPT must restore that host's key (or empty). Check
// Connection and chat/completions must send the same Authorization header
// after the switch — the community report was Check Connection green with
// a missing auth header on the live generate path.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';
import 'package:front_porch_ai/services/web/facade/backend_facade.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_services.dart';

const _openRouter = 'https://openrouter.ai/api/v1';
const _nanoGpt = 'https://nano-gpt.com/api/v1';
const _orKey = 'sk-or-openrouter';
const _nanoKey = 'sk-nano-nanogpt';

void _mockPathProvider() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_test_').path;
        }
        return null;
      });
}

Future<StorageService> _storage([Map<String, Object> seed = const {}]) async {
  SharedPreferences.setMockInitialValues(seed);
  final service = StorageService();
  await service.initialized;
  return service;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _mockPathProvider();

  group('RemoteApiKeyVault', () {
    test('normalizes trailing slash and host case to one slot', () {
      expect(
        normalizeRemoteApiUrl('https://OpenRouter.ai/api/v1/'),
        normalizeRemoteApiUrl(_openRouter),
      );
      final vault = RemoteApiKeyVault();
      vault.put('https://openrouter.ai/api/v1/', _orKey);
      expect(vault.keyFor(_openRouter), _orKey);
    });

    test('OpenRouter and Nano-GPT keep separate keys', () {
      final vault = RemoteApiKeyVault();
      vault.put(_openRouter, _orKey);
      vault.put(_nanoGpt, _nanoKey);
      expect(vault.keyFor(_openRouter), _orKey);
      expect(vault.keyFor(_nanoGpt), _nanoKey);
      vault.put(_nanoGpt, '');
      expect(vault.keyFor(_nanoGpt), isEmpty);
      expect(vault.urlsWithKeys, [_openRouter]);
    });
  });

  group('per-URL key restore on OpenRouter ↔ Nano-GPT switch', () {
    test(
      'switching to a host with no saved key clears the active key',
      () async {
        final storage = await _storage();
        await storage.setRemoteApiUrl(_openRouter);
        await storage.setRemoteApiKey(_orKey);

        await storage.setRemoteApiUrl(_nanoGpt);

        expect(storage.remoteApiUrl, _nanoGpt);
        expect(
          storage.remoteApiKey,
          isEmpty,
          reason: 'Nano-GPT must not inherit the OpenRouter key',
        );
        expect(storage.backendSettings.remoteApiKeyFor(_openRouter), _orKey);
        expect(storage.backendSettings.remoteApiKeyFor(_nanoGpt), isEmpty);
      },
    );

    test('switching back restores each host key', () async {
      final storage = await _storage();
      await storage.setRemoteApiUrl(_openRouter);
      await storage.setRemoteApiKey(_orKey);
      await storage.setRemoteApiUrl(_nanoGpt);
      await storage.setRemoteApiKey(_nanoKey);

      await storage.setRemoteApiUrl(_openRouter);
      expect(storage.remoteApiKey, _orKey);

      await storage.setRemoteApiUrl(_nanoGpt);
      expect(storage.remoteApiKey, _nanoKey);
    });

    test('legacy single remote_api_key seeds the active URL slot', () async {
      final storage = await _storage({
        'remote_api_url': _openRouter,
        'remote_api_key': _orKey,
      });
      expect(storage.remoteApiKey, _orKey);

      await storage.setRemoteApiUrl(_nanoGpt);
      expect(storage.remoteApiKey, isEmpty);

      await storage.setRemoteApiUrl(_openRouter);
      expect(storage.remoteApiKey, _orKey);
    });
  });

  group('Check Connection vs generate auth header after switch', () {
    late StorageService storage;
    late OpenRouterService remote;
    late LLMProvider provider;

    setUp(() async {
      storage = await _storage();
      await storage.setBackendType('openRouter');
      await storage.setRemoteApiUrl(_openRouter);
      await storage.setRemoteApiKey(_orKey);
      await storage.setRemoteModelName('test/model');
      remote = OpenRouterService();
      provider = LLMProvider(
        KoboldService(storage),
        remote,
        storage,
        BackendManager(storage),
      );
    });

    tearDown(() => provider.dispose());

    test(
      'live service key tracks the restored slot, not the previous host',
      () async {
        expect(remote.apiKey, _orKey);
        expect(remote.apiUrl, _openRouter);

        await storage.setRemoteApiUrl(_nanoGpt);

        expect(remote.apiUrl, _nanoGpt);
        expect(remote.apiKey, isEmpty);
        expect(
          remote.chatRequestHeaders.containsKey('Authorization'),
          isFalse,
          reason:
              'generate must not send Bearer <empty> after a keyless switch',
        );

        final check = await remote.testConnection(
          apiUrl: storage.remoteApiUrl,
          apiKey: storage.remoteApiKey,
        );
        expect(check, contains('API key'));
      },
    );

    test('Check Connection and generate send the same restored key', () async {
      await storage.setRemoteApiUrl(_nanoGpt);
      await storage.setRemoteApiKey(_nanoKey);

      await storage.setRemoteApiUrl(_openRouter);
      expect(remote.apiKey, _orKey);

      await storage.setRemoteApiUrl(_nanoGpt);
      expect(storage.remoteApiKey, _nanoKey);
      expect(remote.apiKey, _nanoKey);

      http.BaseRequest? pingReq;
      http.BaseRequest? genReq;
      remote.httpClientFactory = () => MockClient((request) async {
        if (request.url.path.endsWith('/models')) {
          pingReq = request;
          return http.Response('{"data":[]}', 200);
        }
        genReq = request;
        return http.Response(
          'data: {"choices":[{"delta":{"content":"ok"}}]}\n\n'
          'data: [DONE]\n\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final check = await remote.testConnection(
        apiUrl: storage.remoteApiUrl,
        apiKey: storage.remoteApiKey,
      );
      expect(check, contains('successful'));
      expect(pingReq, isNotNull);
      expect(pingReq!.headers['authorization'], 'Bearer $_nanoKey');

      expect(remote.chatRequestHeaders['Authorization'], 'Bearer $_nanoKey');
      expect(
        remoteAuthHeaders(remote.apiKey)['Authorization'],
        pingReq!.headers['authorization'],
      );

      try {
        await remote
            .generateStream(const GenerationParams(prompt: 'hi'))
            .join();
      } catch (_) {
        // Header capture is the assertion; a mock SSE body may not parse.
      }
      expect(genReq, isNotNull);
      expect(
        genReq!.headers['authorization'],
        pingReq!.headers['authorization'],
        reason: 'live generate must reuse Check Connection\'s auth header',
      );
    });
  });

  group(
    'web Check Connection preview uses the URL\'s key, not the other host',
    () {
      test(
        'probing Nano-GPT does not send the stored OpenRouter key',
        () async {
          final storage = await _storage();
          await storage.setRemoteApiUrl(_openRouter);
          await storage.setRemoteApiKey(_orKey);

          final facade = BackendFacade(
            FakeLLMProvider(),
            storage,
            FakeModelManager(),
          );
          final msg = await facade.testRemoteConnection(apiUrl: _nanoGpt);
          expect(
            msg,
            contains('API key'),
            reason: 'preview of Nano-GPT must not ride the OpenRouter key',
          );
        },
      );
    },
  );
}
