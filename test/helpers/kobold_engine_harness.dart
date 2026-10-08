// A real KoboldService talking to a [FakeKoboldEngine] over loopback: the
// service believes the engine runs and its model is loaded, so every request
// goes out the way it does in the app.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/system_role_probe.dart';

import 'fake_kobold_engine.dart';

class KoboldEngineHarness {
  KoboldEngineHarness._(this.engine, this.kobold, this.storage, this.probe);

  final FakeKoboldEngine engine;
  final KoboldService kobold;
  final StorageService storage;

  /// The service's own system-role verdicts, shared with nothing else.
  final SystemRoleProbe probe;

  /// [prepare] runs on the service before it is marked ready, for a test
  /// that needs something in place first (a resident config).
  static Future<KoboldEngineHarness> start({
    int slots = 5,
    void Function(KoboldService kobold)? prepare,
  }) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The test binding answers every request 400 unless told otherwise.
    HttpOverrides.global = null;
    final tmp = Directory.systemTemp.createTempSync('fpai_kobold_engine_');
    addTearDown(() => tmp.delete(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? tmp.path
              : null,
        );
    // A remote backend: the service's start-up probe must never kill a
    // KoboldCpp the developer runs on the default port.
    SharedPreferences.setMockInitialValues({
      'backend_type': 'openRouter',
      'character_evolution_enabled': false,
    });
    final storage = StorageService();
    await storage.initialized;
    final engine = await FakeKoboldEngine.start(slots: slots);
    final probe = SystemRoleProbe();
    final kobold = KoboldService(storage, systemRoleProbe: probe);
    kobold.setBaseUrl(engine.baseUrl);
    kobold.debugMarkProcessRunning();
    prepare?.call(kobold);
    // Settles the system-role check, so none of it is left to land later.
    await kobold.debugMarkModelReady();
    engine
      ..forgetLog()
      ..live = [];
    return KoboldEngineHarness._(engine, kobold, storage, probe);
  }

  Future<void> dispose() async {
    kobold.dispose();
    await engine.close();
  }
}
