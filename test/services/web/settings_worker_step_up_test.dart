// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// POST /api/settings must demand a password step-up when the body would
// change workerRemoteApiUrl or overwrite workerApiKey — the same gate the
// mouth remote already has. Unchanged URL + blank key stay session-only.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/facade/facades.dart';
import 'package:front_porch_ai/services/web/routes/routes.dart';
import 'package:front_porch_ai/services/web/util/step_up.dart';
import 'package:front_porch_ai/services/web/web_server_deps.dart';

import '../../golden/support/fakes.dart';

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

class _Llm extends FakeLLMProvider {
  final OpenRouterService remote = OpenRouterService();
  @override
  OpenRouterService get openRouterService => remote;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _mockPathProvider();
  SharedPreferences.setMockInitialValues({});

  late AppDatabase db;
  late AuthService auth;
  late StorageService storage;
  late SettingsFacade facade;
  late Router router;

  const storedWorkerUrl = 'https://openrouter.ai/api/v1';
  const attacker = 'https://attacker.example/v1';

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase.forTesting();
    auth = AuthService(db);
    storage = StorageService();
    await storage.initialized;
    await storage.setWorkerRemoteApiUrl(storedWorkerUrl);
    facade = SettingsFacade(storage, _Llm());
    router = Router();
    WebSettingsRoutes(
      WebServerDeps(
        storage: storage,
        db: db,
        auth: auth,
        settingsFacade: facade,
      ),
      router,
    );
    expect(
      await auth.setupAccount(
        'admin',
        'password123',
        isDirectLoopbackClient: true,
      ),
      SetupStatus.success,
    );
  });

  tearDown(() => db.close());

  Future<shelf.Response> post(Map<String, dynamic> body) {
    return router.call(
      shelf.Request(
        'POST',
        Uri.parse('http://localhost/api/settings'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode(body),
      ),
    );
  }

  group('workerCredentialWriteNeedsStepUp', () {
    test('unchanged URL and blank key stay session-only', () {
      expect(
        workerCredentialWriteNeedsStepUp({
          'workerRemoteApiUrl': storedWorkerUrl,
        }, currentWorkerRemoteApiUrl: storedWorkerUrl),
        isFalse,
      );
      expect(
        workerCredentialWriteNeedsStepUp({
          'workerApiKey': '',
        }, currentWorkerRemoteApiUrl: storedWorkerUrl),
        isFalse,
      );
      expect(
        workerCredentialWriteNeedsStepUp(
          {},
          currentWorkerRemoteApiUrl: storedWorkerUrl,
        ),
        isFalse,
      );
    });

    test('a new worker URL needs step-up', () {
      expect(
        workerCredentialWriteNeedsStepUp({
          'workerRemoteApiUrl': attacker,
        }, currentWorkerRemoteApiUrl: storedWorkerUrl),
        isTrue,
      );
    });

    test('a non-empty workerApiKey needs step-up', () {
      expect(
        workerCredentialWriteNeedsStepUp({
          'workerApiKey': 'sk-stolen',
        }, currentWorkerRemoteApiUrl: storedWorkerUrl),
        isTrue,
      );
    });
  });

  test('changing workerRemoteApiUrl without a password is refused', () async {
    final res = await post({'workerRemoteApiUrl': attacker});
    expect(res.statusCode, 401);
    expect(
      jsonDecode(await res.readAsString())['error'],
      'Current password is incorrect',
    );
    expect(storage.workerRemoteApiUrl, storedWorkerUrl);
  });

  test('overwriting workerApiKey without a password is refused', () async {
    final res = await post({'workerApiKey': 'sk-stolen'});
    expect(res.statusCode, 401);
    expect(
      jsonDecode(await res.readAsString())['error'],
      'Current password is incorrect',
    );
  });

  test('changing workerRemoteApiUrl succeeds after password step-up', () async {
    final res = await post({
      'workerRemoteApiUrl': 'https://nano-gpt.com/api/v1',
      'currentPassword': 'password123',
    });
    expect(res.statusCode, 200);
    expect(storage.workerRemoteApiUrl, 'https://nano-gpt.com/api/v1');
  });

  test(
    're-sending the current worker URL without a password is not a change',
    () async {
      final res = await post({'workerRemoteApiUrl': storedWorkerUrl});
      expect(res.statusCode, 200);
      expect(storage.workerRemoteApiUrl, storedWorkerUrl);
    },
  );

  test('a sampler-only write does not require worker step-up', () async {
    final res = await post({
      'generation': {'temperature': 0.42},
    });
    expect(res.statusCode, 200);
    expect(storage.generationSettings.temperature, 0.42);
    expect(storage.workerRemoteApiUrl, storedWorkerUrl);
  });
}
