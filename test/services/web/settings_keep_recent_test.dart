// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's "Keep recent chats ready" goes through /api/settings: GET says
// the host's count (Off, only the open chat, unless changed) and the choices
// there are; POST stores a new one in the setting the desktop and the keeper
// read, with no password step-up (it is not a credential), kept for the
// next start of the app; a count that is not a choice is not stored.

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
    root = await Directory.systemTemp.createTemp('fpai keep recent');
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
    expect(body['koboldKeepRecentChats'], 0);
    expect(body['koboldKeepRecentChoices'], [0, 1, 2, 3, 4]);
  });

  test('POST stores a count in the desktop setting, kept for the next start, '
      'no password asked', () async {
    final body = await call('POST', {'koboldKeepRecentChats': 2});
    expect(body['koboldKeepRecentChats'], 2);
    expect(storage.backendSettings.keepRecentChats, 2);

    final again = StorageService();
    await again.initialized;
    expect(again.backendSettings.keepRecentChats, 2);
    expect((await call('GET'))['koboldKeepRecentChats'], 2);
  });

  test('a count that is not a choice is not stored', () async {
    await call('POST', {'koboldKeepRecentChats': 2});
    for (final bad in [5, -1]) {
      final body = await call('POST', {'koboldKeepRecentChats': bad});
      expect(body['koboldKeepRecentChats'], 2, reason: '$bad');
    }
    expect(storage.backendSettings.keepRecentChats, 2);
  });
}
