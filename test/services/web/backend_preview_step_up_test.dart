// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Preview routes (test-connection / remote-models / reasoning-menu) must
// demand a password step-up when the body would fire a live request at a
// non-stored apiUrl or with a non-stored apiKey. Session-only is fine when
// the request uses the already-saved pair unchanged. A refuse must not
// reach the facade (no outbound).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/facade/backend_facade.dart';
import 'package:front_porch_ai/services/web/routes/backend_routes.dart';
import 'package:front_porch_ai/services/web/util/step_up.dart';
import 'package:front_porch_ai/services/web/web_server_deps.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_services.dart';

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

class _CountingBackend extends BackendFacade {
  _CountingBackend(StorageService storage)
    : super(FakeLLMProvider(), storage, FakeModelManager());

  int remoteHits = 0;
  int menuHits = 0;
  int testHits = 0;

  @override
  Future<List<Map<String, dynamic>>> remoteModels({
    String? apiUrl,
    String? apiKey,
  }) async {
    remoteHits++;
    return const [];
  }

  @override
  Future<Map<String, dynamic>> reasoningMenu({
    required String model,
    String? apiUrl,
    String? apiKey,
  }) async {
    menuHits++;
    return const {'efforts': <String>[]};
  }

  @override
  Future<String> testRemoteConnection({String? apiUrl, String? apiKey}) async {
    testHits++;
    return 'Connection successful';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _mockPathProvider();
  SharedPreferences.setMockInitialValues({});

  late AppDatabase db;
  late AuthService auth;
  late StorageService storage;
  late _CountingBackend spy;
  late Router router;

  const storedUrl = 'https://openrouter.ai/api/v1';
  const storedKey = 'sk-stored';
  const attacker = 'https://attacker.example/v1';

  setUp(() async {
    db = AppDatabase.forTesting();
    auth = AuthService(db);
    storage = StorageService();
    await storage.initialized;
    await storage.backendSettings.setRemoteApiKey(storedKey);
    spy = _CountingBackend(storage);
    router = Router();
    WebBackendRoutes(
      WebServerDeps(storage: storage, db: db, auth: auth),
      router,
      backend: spy,
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

  Future<shelf.Response> post(String path, Map<String, dynamic> body) {
    return router.call(
      shelf.Request(
        'POST',
        Uri.parse('http://localhost$path'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode(body),
      ),
    );
  }

  Future<void> expectRefused(String path, Map<String, dynamic> body) async {
    final remoteBefore = spy.remoteHits;
    final menuBefore = spy.menuHits;
    final testBefore = spy.testHits;
    final res = await post(path, body);
    expect(res.statusCode, 401);
    expect(
      jsonDecode(await res.readAsString())['error'],
      'Current password is incorrect',
    );
    expect(spy.remoteHits, remoteBefore);
    expect(spy.menuHits, menuBefore);
    expect(spy.testHits, testBefore);
  }

  group('remoteCredentialPreviewNeedsStepUp', () {
    test('empty / omitted fields stay session-only', () {
      expect(
        remoteCredentialPreviewNeedsStepUp(
          {},
          currentRemoteApiUrl: storedUrl,
          currentRemoteApiKey: storedKey,
        ),
        isFalse,
      );
    });

    test('re-sending the stored URL without a key stays session-only', () {
      expect(
        remoteCredentialPreviewNeedsStepUp(
          {'apiUrl': storedUrl},
          currentRemoteApiUrl: storedUrl,
          currentRemoteApiKey: storedKey,
        ),
        isFalse,
      );
    });

    test('re-sending the stored key stays session-only', () {
      expect(
        remoteCredentialPreviewNeedsStepUp(
          {'apiKey': storedKey},
          currentRemoteApiUrl: storedUrl,
          currentRemoteApiKey: storedKey,
        ),
        isFalse,
      );
    });

    test('a non-stored host needs step-up', () {
      expect(
        remoteCredentialPreviewNeedsStepUp(
          {'apiUrl': attacker},
          currentRemoteApiUrl: storedUrl,
          currentRemoteApiKey: storedKey,
        ),
        isTrue,
      );
    });

    test('a non-stored key needs step-up', () {
      expect(
        remoteCredentialPreviewNeedsStepUp(
          {'apiKey': 'sk-other'},
          currentRemoteApiUrl: storedUrl,
          currentRemoteApiKey: storedKey,
        ),
        isTrue,
      );
    });
  });

  group('POST /api/backend/test-connection', () {
    test('refuses a non-stored apiUrl without step-up', () async {
      await expectRefused('/api/backend/test-connection', {'apiUrl': attacker});
    });

    test('refuses a non-stored apiKey without step-up', () async {
      await expectRefused('/api/backend/test-connection', {
        'apiKey': 'sk-other',
      });
    });

    test('session-only when the body uses the stored pair', () async {
      final res = await post('/api/backend/test-connection', {});
      expect(res.statusCode, 200);
      expect(spy.testHits, 1);
    });

    test('session-only when apiUrl equals the stored URL', () async {
      final res = await post('/api/backend/test-connection', {
        'apiUrl': storedUrl,
      });
      expect(res.statusCode, 200);
      expect(spy.testHits, 1);
    });

    test('a non-stored host proceeds after password step-up', () async {
      final res = await post('/api/backend/test-connection', {
        'apiUrl': attacker,
        'currentPassword': 'password123',
      });
      expect(res.statusCode, 200);
      expect(spy.testHits, 1);
    });
  });

  group('POST /api/backend/remote-models', () {
    test('refuses a non-stored apiUrl without step-up', () async {
      await expectRefused('/api/backend/remote-models', {'apiUrl': attacker});
    });

    test('refuses a non-stored apiKey without step-up', () async {
      await expectRefused('/api/backend/remote-models', {'apiKey': 'sk-other'});
    });

    test('session-only when the body uses the stored pair', () async {
      final res = await post('/api/backend/remote-models', {});
      expect(res.statusCode, 200);
      expect(spy.remoteHits, 1);
    });

    test('session-only when apiUrl equals the stored URL', () async {
      final res = await post('/api/backend/remote-models', {
        'apiUrl': storedUrl,
      });
      expect(res.statusCode, 200);
      expect(spy.remoteHits, 1);
    });
  });

  group('POST /api/backend/reasoning-menu', () {
    test('refuses a non-stored apiUrl without step-up', () async {
      await expectRefused('/api/backend/reasoning-menu', {
        'model': 'some/model',
        'apiUrl': attacker,
      });
    });

    test('refuses a non-stored apiKey without step-up', () async {
      await expectRefused('/api/backend/reasoning-menu', {
        'model': 'some/model',
        'apiKey': 'sk-other',
      });
    });

    test('empty model is 400 before the facade', () async {
      final res = await post('/api/backend/reasoning-menu', {
        'apiUrl': attacker,
      });
      expect(res.statusCode, 400);
      expect(spy.menuHits, 0);
    });

    test('session-only when apiUrl equals the stored URL', () async {
      final res = await post('/api/backend/reasoning-menu', {
        'model': 'some/model',
        'apiUrl': storedUrl,
      });
      expect(res.statusCode, 200);
      expect(spy.menuHits, 1);
    });
  });
}
