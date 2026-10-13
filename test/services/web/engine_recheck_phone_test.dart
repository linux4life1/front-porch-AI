// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The phone's Models page after the KoboldCpp engine file was removed. The
// status the host sends is its last look, so the page went on saying the
// engine was installed. POST /api/backend/engine/check (additive) looks
// again first, as the desktop Backend tab does when it opens.
//
// The real facade and routes, on the real LLM provider, KoboldCpp service
// and engine manager (told it is on Linux), with a real engine file.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/facade/backend_facade.dart';
import 'package:front_porch_ai/services/web/routes/backend_routes.dart';
import 'package:front_porch_ai/services/web/web_server_deps.dart';

import '../../golden/support/fakes_services.dart';

class _LinuxManager extends BackendManager {
  _LinuxManager(super.storage)
    : super(onLinux: true, onMac: false, readArch: () async => 'x86_64');
  @override
  Future<void> checkForUpdates() async {}
}

void main() {
  late Directory root;
  late AppDatabase db;
  late StorageService storage;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    root = Directory.systemTemp.createTempSync('fpai engine recheck phone');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return call.method == 'getApplicationDocumentsDirectory'
              ? root.path
              : null;
        });
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.initialized;
    await storage.backendSettings.setBackendType('kobold');
    await storage.backendSettings.setUseVulkan(true);
    db = AppDatabase.forTesting();
  });

  tearDown(() async {
    await db.close();
    root.deleteSync(recursive: true);
  });

  test('a removed engine reads as not installed once the page asks the host '
      'to look again', () async {
    await storage.binDir.create(recursive: true);
    final engine = File(
      p.join(storage.binDir.path, 'koboldcpp-linux-x64-nocuda'),
    );
    await engine.writeAsBytes(List.filled(2048, 1));
    final engines = _LinuxManager(storage);
    final kobold = KoboldService(storage);
    final provider = LLMProvider(
      kobold,
      OpenRouterService(apiUrl: '', apiKey: '', modelName: ''),
      storage,
      engines,
    );
    addTearDown(() {
      provider.dispose();
      kobold.dispose();
    });
    await engines.engineChecked;

    final router = Router();
    WebBackendRoutes(
      WebServerDeps(storage: storage, db: db, auth: AuthService(db)),
      router,
      backend: BackendFacade(provider, storage, FakeModelManager()),
    );
    Future<Map<String, dynamic>> call(String method, String path) async {
      final res = await router.call(
        shelf.Request(method, Uri.parse('http://localhost$path')),
      );
      expect(res.statusCode, 200, reason: '$method $path');
      return jsonDecode(await res.readAsString()) as Map<String, dynamic>;
    }

    expect((await call('GET', '/api/backend/status'))['engineInstalled'], true);

    await engine.delete();
    final looked = await call('POST', '/api/backend/engine/check');

    expect(looked['engineInstalled'], false);
    expect(looked['isLocal'], true, reason: 'the rest of the status is there');
  });
}
