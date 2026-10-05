// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// While KoboldCpp runs a preset, the preset's context is the context: the
// desktop locks the control, and so does the settings API the phone saves
// through. The phone sends the whole form with every save, so the context it
// read coming back is not a change; a different one is refused, in the
// desktop's words, and nothing else in that save is stored either. A preset
// left over on a remote backend owns nothing.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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
  _Llm(this.backend);

  BackendType backend;
  final OpenRouterService remote = OpenRouterService();

  @override
  BackendType get activeBackend => backend;

  @override
  bool get isLocal => backend == BackendType.kobold;

  @override
  Future<void> setActiveBackend(BackendType type) async => backend = type;

  @override
  OpenRouterService get openRouterService => remote;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late AppDatabase db;
  late StorageService storage;
  late String preset;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fpai context lock');
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
    preset = p.join(root.path, 'Long chats.kcpps');
    File(preset).writeAsStringSync(
      jsonEncode({'model_param': 'm.gguf', 'contextsize': 32768}),
    );
  });

  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  Future<shelf.Response> post(BackendType backend, Map<String, dynamic> body) {
    final router = Router();
    WebSettingsRoutes(
      WebServerDeps(
        storage: storage,
        db: db,
        auth: AuthService(db),
        settingsFacade: SettingsFacade(storage, _Llm(backend)),
      ),
      router,
    );
    return router.call(
      shelf.Request(
        'POST',
        Uri.parse('http://localhost/api/settings'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode(body),
      ),
    );
  }

  Future<void> usePreset() async {
    await storage.backendSettings.setActiveKcppsPath(preset);
    expect(storage.backendSettings.contextSize, 32768);
  }

  test('no preset: the context is set as before', () async {
    final res = await post(BackendType.kobold, {'contextSize': 8192});
    expect(res.statusCode, 200);
    expect(storage.backendSettings.contextSize, 8192);
  });

  test('a preset in use owns the context: another one is refused in the '
      "desktop's words, and the rest of that save is not stored", () async {
    await usePreset();
    final before = storage.generationSettings.temperature;
    final res = await post(BackendType.kobold, {
      'contextSize': 8192,
      'generation': {'temperature': before + 0.25},
    });
    expect(res.statusCode, 400);
    expect(
      (jsonDecode(await res.readAsString()) as Map)['error'],
      'Context size is controlled by the active .kcpps preset and cannot be '
      'edited here.',
    );
    expect(storage.backendSettings.contextSize, 32768);
    expect(storage.generationSettings.temperature, before);
  });

  test('the context the page read, coming back with the rest of the form, '
      'is not a change', () async {
    await usePreset();
    final before = storage.generationSettings.temperature;
    final res = await post(BackendType.kobold, {
      'contextSize': 32768,
      'generation': {'temperature': before + 0.25},
    });
    expect(res.statusCode, 200);
    expect(storage.backendSettings.contextSize, 32768);
    expect(
      storage.generationSettings.temperature,
      closeTo(before + 0.25, 1e-9),
    );
  });

  test('a preset left over on a remote backend owns nothing', () async {
    await usePreset();
    final res = await post(BackendType.openRouter, {'contextSize': 8192});
    expect(res.statusCode, 200);
    expect(storage.backendSettings.contextSize, 8192);
  });

  test('the same save may switch the backend either way', () async {
    await usePreset();
    // To KoboldCpp: the preset owns the context from then on.
    var res = await post(BackendType.openRouter, {
      'backend': 'kobold',
      'contextSize': 8192,
    });
    expect(res.statusCode, 400);
    expect(storage.backendSettings.contextSize, 32768);
    // From KoboldCpp: nothing owns it.
    res = await post(BackendType.kobold, {
      'backend': 'openRouter',
      'contextSize': 8192,
    });
    expect(res.statusCode, 200);
    expect(storage.backendSettings.contextSize, 8192);
  });
}
