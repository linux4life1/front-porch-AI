// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// What a running model is called is read from its file when a load is
// CONFIRMED, not when one is asked for: a reload that was accepted can still
// fail, and KoboldCpp then goes back to the model it had, so a file replaced
// on disk meanwhile is not what runs. `residentGeneration` is the counter the
// name is read against, and it goes up only on a confirmed load.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/system_role_probe.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late StorageService storage;
  late KoboldService kobold;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fpai resident generation');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? dir.path
              : null,
        );
    SharedPreferences.setMockInitialValues({'update_auto_check': false});
    storage = StorageService();
    await storage.initialized;
    kobold = KoboldService(
      storage,
      systemRoleProbe: SystemRoleProbe(retryBackoff: Duration.zero),
    )..setBaseUrl('http://127.0.0.1:1');
    kobold.debugMarkProcessRunning();
  });

  tearDown(() async {
    kobold.dispose();
    await dir.delete(recursive: true);
  });

  test('goes up when a load is read back as what was asked for, and only '
      'then', () async {
    final before = kobold.residentGeneration;

    // A reload is asked for and accepted: nothing is known yet.
    kobold.markModelLoading('Loading a.gguf...');
    kobold.noteAdminLoadedPair(modelPath: '/models/a.gguf', kcppsPath: '');
    expect(kobold.residentGeneration, before);

    // The engine answers again. A reload it could not do looks the same: it
    // went back to the model it had.
    await kobold.debugMarkModelReady();
    expect(kobold.residentGeneration, before);

    // Read back: not what was asked for.
    kobold.noteResident('');
    kobold.forgetAdminLoadedPair();
    expect(kobold.residentGeneration, before);

    // A later reload, read back: it is what was asked for.
    kobold.markModelLoading('Loading a.gguf...');
    kobold.noteAdminLoadedPair(modelPath: '/models/a.gguf', kcppsPath: '');
    await kobold.debugMarkModelReady();
    kobold.noteResident('config of a.gguf');
    expect(kobold.residentGeneration, before + 1);
    expect(kobold.answeringModelPath, '/models/a.gguf');
  });
}
