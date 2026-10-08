// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// An Intel Mac cannot run KoboldCpp. The desktop hides its KoboldCpp section
// there and says so in one sentence; the phone's Models page showed the
// Local backend, Local model and preset cards anyway, with an engine to
// download and restart that could never work, and no reason given.
//
// /api/backend/status now says it (`localUnsupported`, additive: an older
// phone ignores it), from the same check the desktop uses, so the phone can
// hide those cards and say the desktop's sentence instead.
//
// The real facade and routes, on the real LLM provider and KoboldCpp
// service; only the processor the engine manager sees is chosen.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

/// The engine manager on a Mac with an Intel processor, or not.
class _Engine extends BackendManager {
  _Engine(super.storage, {required this.intelMac});
  final bool intelMac;

  @override
  bool get isIntelMac => intelMac;
}

void main() {
  late Directory root;
  late AppDatabase db;
  late StorageService storage;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    root = Directory.systemTemp.createTempSync('fpai intel mac phone');
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
    db = AppDatabase.forTesting();
  });

  tearDown(() async {
    await db.close();
    root.deleteSync(recursive: true);
  });

  /// What GET /api/backend/status sends the phone, as the phone reads it.
  Future<Map<String, dynamic>> statusOn({required bool intelMac}) async {
    final kobold = KoboldService(storage);
    final provider = LLMProvider(
      kobold,
      OpenRouterService(apiUrl: '', apiKey: '', modelName: ''),
      storage,
      _Engine(storage, intelMac: intelMac),
    );
    addTearDown(() {
      provider.dispose();
      kobold.dispose();
    });
    final router = Router();
    WebBackendRoutes(
      WebServerDeps(storage: storage, db: db, auth: AuthService(db)),
      router,
      backend: BackendFacade(provider, storage, FakeModelManager()),
    );
    final res = await router.call(
      shelf.Request('GET', Uri.parse('http://localhost/api/backend/status')),
    );
    expect(res.statusCode, 200);
    return jsonDecode(await res.readAsString()) as Map<String, dynamic>;
  }

  test('on an Intel Mac the phone is told local models cannot run', () async {
    final status = await statusOn(intelMac: true);

    expect(status['localUnsupported'], isTrue);
    expect(status['isLocal'], isTrue, reason: 'the backend is still KoboldCpp');
  });

  test(
    'elsewhere it is false, and the rest of the status is as it was',
    () async {
      final status = await statusOn(intelMac: false);

      expect(status['localUnsupported'], isFalse);
      expect(status['isLocal'], isTrue);
      expect(status['phase'], 'stopped');
    },
  );

  test('the phone says the desktop\'s own sentence', () {
    // The phone's words live in its shared backend list, used by the Models
    // page and the Side jobs host picker.
    final phone = File('web_ui/src/backendOptions.ts').readAsStringSync();

    expect(phone, contains("'$kIntelMacLocalUnsupported'"));
  });
}
