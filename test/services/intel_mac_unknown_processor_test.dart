// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The app asks the Mac's processor (`uname -m`) a moment after it starts.
// Until it answered, every Mac counted as an Intel Mac, which cannot run
// KoboldCpp: an Apple Silicon Mac's phone could be told `localUnsupported`
// and hide its KoboldCpp cards, the desktop could hide its KoboldCpp section,
// and the first-run setup could skip itself. Now a processor that has not
// answered is not an Intel one; the app says "Intel Mac" only once it knows,
// tells its listeners then, and what depends on it (the first-run setup,
// which engine to download) waits for the answer.
//
// The real engine manager, setup, routes and facade; only the machine is
// chosen (a Mac or not, and when and what its processor answers).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/setup_service.dart';
import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/facade/backend_facade.dart';
import 'package:front_porch_ai/services/web/routes/backend_routes.dart';
import 'package:front_porch_ai/services/web/web_server_deps.dart';

import '../golden/support/fakes_services.dart';

void main() {
  late Directory root;
  late AppDatabase db;
  late StorageService storage;
  late Completer<String?> processor;
  late BackendManager engine;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    root = Directory.systemTemp.createTempSync('fpai unknown processor');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return call.method == 'getApplicationDocumentsDirectory'
              ? root.path
              : null;
        });
    SharedPreferences.setMockInitialValues({'update_auto_check': false});
    storage = StorageService();
    await storage.initialized;
    await storage.backendSettings.setBackendType('kobold');
    db = AppDatabase.forTesting();
    processor = Completer<String?>();
    engine = BackendManager(
      storage,
      onMac: true,
      readArch: () => processor.future,
    );
  });

  tearDown(() async {
    if (!processor.isCompleted) processor.complete('arm64');
    engine.dispose();
    await db.close();
    root.deleteSync(recursive: true);
  });

  /// What GET /api/backend/status sends the phone now.
  Future<Map<String, dynamic>> status() async {
    final kobold = KoboldService(storage);
    final provider = LLMProvider(
      kobold,
      OpenRouterService(apiUrl: '', apiKey: '', modelName: ''),
      storage,
      engine,
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

  test('a Mac whose processor has not answered is not an Intel Mac, on the '
      'desktop or the phone', () async {
    expect(engine.isIntelMac, isFalse);
    expect((await status())['localUnsupported'], isFalse);
  });

  test('an Intel processor makes it one once it answers, and listeners are '
      'told', () async {
    var told = 0;
    engine.addListener(() => told++);

    processor.complete('x86_64');
    await engine.architectureKnown;

    expect(engine.isIntelMac, isTrue);
    expect(told, greaterThan(0), reason: 'the desktop redraws its section');
    expect((await status())['localUnsupported'], isTrue);
  });

  test('Apple Silicon stays able to run it before and after', () async {
    expect((await status())['localUnsupported'], isFalse);

    processor.complete('arm64');
    await engine.architectureKnown;

    expect(engine.isIntelMac, isFalse);
    expect((await status())['localUnsupported'], isFalse);
  });

  test('the first-run setup waits for the processor: an Intel Mac that '
      'answers late still skips it', () async {
    final setup = SetupService(storage, engine, FakeKoboldService());
    addTearDown(setup.dispose);

    final running = setup.runAutoSetup();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      setup.currentStep,
      SetupStep.idle,
      reason: 'nothing is decided before the processor answers',
    );

    processor.complete('x86_64');
    await running;

    expect(setup.currentStep, SetupStep.complete);
  });

  test('anywhere but a Mac nothing is asked, and nothing waits', () async {
    var asked = 0;
    final other = BackendManager(
      storage,
      onMac: false,
      readArch: () async {
        asked++;
        return 'x86_64';
      },
    );
    addTearDown(other.dispose);

    await other.architectureKnown.timeout(const Duration(seconds: 5));
    expect(other.isIntelMac, isFalse);
    expect(asked, 0);
  });
}
