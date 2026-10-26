// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's Bubble opacity goes through /api/settings: GET says the
// opacity the desktop paints (opaque with the Ambient scene off, 0.25 while
// it paints, unless the user stored their own), so a scene change made here
// moves it too; POST stores a number in the desktop's own setting, held to
// the desktop slider's 0.1..1, and anything else is not stored.

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
    root = await Directory.systemTemp.createTemp('fpai bubble opacity');
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

  test('GET follows the ambient scene until an opacity is stored', () async {
    expect((await call('GET'))['bubbleOpacity'], 1.0);
    final changed = await call('POST', {'ambientScene': 'effects'});
    expect(changed['bubbleOpacity'], 0.25);
    expect((await call('GET'))['bubbleOpacity'], 0.25);
    expect(storage.uiSettings.bubbleOpacity, 0.25);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('bubble_opacity'), isFalse);

    final stored = await call('POST', {'bubbleOpacity': 0.45});
    expect(stored['bubbleOpacity'], 0.45);
    await call('POST', {'ambientScene': 'off'});
    expect((await call('GET'))['bubbleOpacity'], 0.45);
  });

  test('POST stores the opacity in the desktop setting, kept for the next '
      'start, held to 0.1..1', () async {
    await call('POST', {'bubbleOpacity': 0.6});
    expect(storage.uiSettings.bubbleOpacity, 0.6);
    final again = StorageService();
    await again.initialized;
    expect(again.uiSettings.bubbleOpacity, 0.6);

    expect((await call('POST', {'bubbleOpacity': 7}))['bubbleOpacity'], 1.0);
    expect((await call('POST', {'bubbleOpacity': 0}))['bubbleOpacity'], 0.1);
    for (final bad in ['0.5', null, true]) {
      final body = await call('POST', {'bubbleOpacity': bad});
      expect(body['bubbleOpacity'], 0.1, reason: '$bad');
    }
  });
}
