// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Guard: the startup probe in KoboldService must not SIGKILL a KoboldCpp it
// does not own. `killOrphanedKoboldProcesses` sweeps the whole machine by
// image name (`pkill -KILL -f koboldcpp`), and `reconnectIfAlive()` runs from
// the CONSTRUCTOR on every launch — so a user running their own KoboldCpp and
// pointing Front Porch at it as a Remote API (127.0.0.1 needs no key: a
// supported setup) used to have that server killed out from under them.
//
// Deliberately only the NEGATIVE case is exercised. Asserting the positive
// ("kobold mode still kills") would run a real machine-wide pkill on whoever
// runs the suite, which is precisely the destructive act under test.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // path_provider has no platform channel under `flutter test`; StorageService
  // needs a real writable documents dir to finish its init.
  setUpAll(() {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return Directory.systemTemp
                .createTempSync('fpai_kobold_gate_')
                .path;
          }
          return null;
        });
    // The test binding stubs HttpClient — clear it so the loopback server is
    // actually reachable.
    HttpOverrides.global = null;
  });

  test(
    'a live KoboldCpp is left alone when the selected backend is remote',
    () async {
      // A stand-in KoboldCpp: answers /api/extra/version like the real thing.
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response.headers.contentType = ContentType.json;
        req.response.write('{"result":"KoboldCpp","version":"1.90"}');
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));

      // Remote API selected — this app instance neither started nor wants the
      // server on that port.
      SharedPreferences.setMockInitialValues({'backend_type': 'openRouter'});
      final storage = StorageService();
      await storage.initialized;
      expect(storage.backendSettings.backendType, 'openRouter');

      final kobold = KoboldService(storage);
      addTearDown(kobold.dispose);
      kobold.setBaseUrl('http://127.0.0.1:${server.port}');

      await kobold.reconnectIfAlive();

      // killOrphanedKoboldProcesses logs this line whenever it runs.
      expect(
        kobold.logs.any((l) => l.contains('Killed orphaned KoboldCPP')),
        isFalse,
        reason: 'a machine-wide pkill must not fire while on a remote backend',
      );
      // And we must not pretend we own the server either.
      expect(kobold.isProcessRunning, isFalse);
    },
  );
}
