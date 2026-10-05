// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// However a start ends, the one start slot is released: a start that cannot
// stop the engine it replaces used to be the one exit that had to remember to
// do it by hand, and a slot left claimed turns every later start away with
// "KoboldCpp is already starting." until the app is restarted.
//
// No engine is started here: the stop is the part that fails.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold_admin_swap.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:path/path.dart' as p;

import '../kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

/// An engine that will not stop while [stuck].
class _Stuck extends KoboldService {
  _Stuck(super.storage);

  bool stuck = true;
  int stops = 0;

  @override
  Future<void> stopKobold() {
    stops++;
    return stuck
        ? Future<void>.error(StateError('the engine will not stop'))
        : Future<void>.value();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  late StorageService storage;
  late _Stuck kobold;
  late Directory dir;
  late String engine;
  late String model;

  setUp(() async {
    storage = await createStorageService();
    kobold = _Stuck(storage);
    dir = Directory.systemTemp.createTempSync('fpai_slot_');
    engine = p.join(dir.path, 'koboldcpp');
    model = p.join(dir.path, 'model.gguf');
    File(model).writeAsBytesSync([...'GGUF'.codeUnits, 3, 0, 0, 0]);
  });

  tearDown(() {
    kobold.stuck = false;
    kobold.dispose();
    final admin = koboldAdminDirFor(storage);
    if (FileSystemEntity.isFileSync(admin)) File(admin).deleteSync();
    dir.deleteSync(recursive: true);
  });

  test('a start that cannot stop the engine it replaces throws that, and '
      'the next start is not turned away as "already starting"', () async {
    kobold.debugMarkProcessRunning();

    await expectLater(
      kobold.startKobold(engine, model, port: 5999),
      throwsStateError,
    );
    expect(kobold.isStarting, isFalse);
    expect(kobold.logs.join('\n'), contains('Could not stop the previous'));

    final again = kobold.launch(engine, pickedModel: model, port: 5999);
    await expectLater(again, throwsStateError);
    expect(
      kobold.stops,
      2,
      reason:
          'the second start tried, it was not '
          'turned away',
    );
  });
}
