// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's "Free graphics memory when idle" goes through /api/settings:
// GET says the host's choice (Off unless changed) and the choices there are,
// POST stores a new one in the setting the desktop uses, with no password
// step-up (it is not a credential), and a value that is not a choice is not
// stored.

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
import 'package:front_porch_ai/services/web/web_server_deps.dart';

import '../../golden/support/fakes.dart';

class _Llm extends FakeLLMProvider {
  final OpenRouterService remote = OpenRouterService();
  @override
  OpenRouterService get openRouterService => remote;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late AppDatabase db;
  late StorageService storage;
  late Router router;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fpai idle settings');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return call.method == 'getApplicationDocumentsDirectory'
              ? root.path
              : null;
        });
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase.forTesting();
    storage = StorageService();
    await storage.initialized;
    router = Router();
    WebSettingsRoutes(
      WebServerDeps(
        storage: storage,
        db: db,
        auth: AuthService(db),
        settingsFacade: SettingsFacade(storage, _Llm()),
      ),
      router,
    );
  });

  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  Future<Map<String, dynamic>> call(String method, [Object? body]) async {
    final res = await router.call(
      shelf.Request(
        method,
        Uri.parse('http://localhost/api/settings'),
        headers: {'content-type': 'application/json'},
        body: body == null ? null : jsonEncode(body),
      ),
    );
    expect(res.statusCode, 200);
    return jsonDecode(await res.readAsString()) as Map<String, dynamic>;
  }

  test('GET says Off and the choices', () async {
    final body = await call('GET');
    expect(body['koboldIdleUnloadMinutes'], 0);
    expect(body['koboldIdleUnloadChoices'], [0, 10, 30, 60]);
  });

  test(
    'POST stores a choice in the desktop setting, no password asked',
    () async {
      final body = await call('POST', {'koboldIdleUnloadMinutes': 30});
      expect(body['koboldIdleUnloadMinutes'], 30);
      expect(storage.backendSettings.idleUnloadMinutes, 30);
    },
  );

  test('a value that is not a choice is not stored', () async {
    await call('POST', {'koboldIdleUnloadMinutes': 30});
    final body = await call('POST', {'koboldIdleUnloadMinutes': 45});
    expect(body['koboldIdleUnloadMinutes'], 30);
    expect(storage.backendSettings.idleUnloadMinutes, 30);
  });
}
