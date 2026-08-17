// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// POST /api/settings must demand a password step-up when the body would
// change remoteApiUrl or overwrite apiKey. Harmless sampler writes stay
// session-only. GET must still redact the key (hasApiKey only).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/facade/settings_facade.dart';
import 'package:front_porch_ai/services/web/routes/settings_routes.dart';
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

  setUp(() async {
    db = AppDatabase.forTesting();
    auth = AuthService(db);
    storage = StorageService();
    await storage.initialized;
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

  Future<shelf.Response> get() {
    return router.call(
      shelf.Request('GET', Uri.parse('http://localhost/api/settings')),
    );
  }

  test('changing remoteApiUrl without a password is refused', () async {
    final before = storage.backendSettings.remoteApiUrl;
    final res = await post({'remoteApiUrl': 'https://attacker.example/v1'});
    expect(res.statusCode, 401);
    expect(
      jsonDecode(await res.readAsString())['error'],
      'Current password is incorrect',
    );
    expect(storage.backendSettings.remoteApiUrl, before);
  });

  test('overwriting apiKey without a password is refused', () async {
    expect(storage.backendSettings.remoteApiKey, isEmpty);
    final res = await post({'apiKey': 'sk-stolen'});
    expect(res.statusCode, 401);
    expect(storage.backendSettings.remoteApiKey, isEmpty);
  });

  test('changing remoteApiUrl succeeds after password step-up', () async {
    final res = await post({
      'remoteApiUrl': 'https://nano-gpt.com/api/v1',
      'currentPassword': 'password123',
    });
    expect(res.statusCode, 200);
    expect(storage.backendSettings.remoteApiUrl, 'https://nano-gpt.com/api/v1');
  });

  test('a sampler-only write does not require step-up', () async {
    final res = await post({
      'generation': {'temperature': 0.42},
    });
    expect(res.statusCode, 200);
    expect(storage.generationSettings.temperature, 0.42);
  });

  test(
    're-sending the current URL without a password is not a change',
    () async {
      final current = storage.backendSettings.remoteApiUrl;
      final res = await post({'remoteApiUrl': current});
      expect(res.statusCode, 200);
      expect(storage.backendSettings.remoteApiUrl, current);
    },
  );

  test('GET still redacts the API key after a stepped-up write', () async {
    final wrote = await post({
      'apiKey': 'sk-keep-secret',
      'currentPassword': 'password123',
    });
    expect(wrote.statusCode, 200);
    final res = await get();
    expect(res.statusCode, 200);
    final body = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
    expect(body['hasApiKey'], isTrue);
    expect(body.containsKey('apiKey'), isFalse);
    expect(jsonEncode(body).contains('sk-keep-secret'), isFalse);
  });
}
