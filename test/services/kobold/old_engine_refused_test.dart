// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// KoboldCpp before 1.112 stops at load on the config the app stages (it
// reads the cache type as a number, and a config file is not converted the
// way a command line is). Those versions are not supported (design note,
// decision 8), so the app says so instead of starting one to fail. An
// engine whose version the app never recorded is still started.
//
// No engine is started: the refusal comes before anything is spawned, and
// a start that goes ahead is refused at the spawn, in other words, on a
// missing engine file.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/services/kobold_admin_swap.dart';
import 'package:front_porch_ai/services/kobold_binary_version.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:path/path.dart' as p;

import '../kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  late StorageService storage;
  late KoboldService kobold;
  late Directory dir;
  late String engine;
  late String model;

  setUp(() async {
    storage = await createStorageService();
    kobold = KoboldService(storage);
    dir = Directory.systemTemp.createTempSync('fpai_old_engine_');
    engine = p.join(dir.path, 'koboldcpp');
    model = p.join(dir.path, 'model.gguf');
    File(model).writeAsBytesSync([...'GGUF'.codeUnits, 3, 0, 0, 0]);
  });

  tearDown(() {
    kobold.dispose();
    final admin = koboldAdminDirFor(storage);
    if (FileSystemEntity.isFileSync(admin)) File(admin).deleteSync();
    dir.deleteSync(recursive: true);
  });

  test('an engine older than 1.112 is not started, and the reason says to '
      'update it', () async {
    // The record is trusted only for the binary it was written for.
    File(engine).writeAsBytesSync([0]);
    await KoboldBinaryVersion.write(dir.path, version: '1.110', size: 1);

    final result = await kobold.launch(engine, pickedModel: model, port: 5998);

    expect(result.started, isFalse);
    expect(result.message, contains('too old'));
    expect(result.message, contains('1.112'));
    expect(kobold.isRunning, isFalse);
  });

  // Past the check, the start reaches the spawn, which fails here on the
  // missing engine file: that refusal, and not the "too old" one, is how the
  // test knows it got there.
  void expectReachedTheSpawn(KoboldLaunchResult result) {
    expect(result.started, isFalse);
    expect(result.message, contains('could not be started'));
    expect(result.message, isNot(contains('too old')));
  }

  test('1.112 goes on to start', () async {
    await KoboldBinaryVersion.write(dir.path, version: '1.112', size: 1);
    expectReachedTheSpawn(
      await kobold.launch(engine, pickedModel: model, port: 5998),
    );
  });

  test('an engine of unknown version goes on to start', () async {
    expectReachedTheSpawn(
      await kobold.launch(engine, pickedModel: model, port: 5998),
    );
  });
}
