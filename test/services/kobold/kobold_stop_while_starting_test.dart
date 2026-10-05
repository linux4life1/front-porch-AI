// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Stop pressed while a start is still being prepared (the start slot is
// claimed, no process exists yet: the free-memory read, the model file
// check, the first-run graphics card check) calls that start off before
// KoboldCpp is spawned. Until then Stop did nothing, the engine spawned
// anyway, and a second Stop was needed.
//
// The real KoboldService runs: startKobold -> _spawn -> Process.start, and
// the real stopKobold is the Stop button. Only a wait inside the preparation
// is held open, through the production seams, so Stop lands inside it. The
// "engine" is a shell script that sleeps, so a spawn is visible and
// harmless. POSIX only.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:path/path.dart' as p;

import '../kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

const _stopPressed =
    'KoboldCpp was not started: it was stopped while it was getting ready.';

/// Process ids whose command line mentions [engine]: the script, run by its
/// interpreter, which is why this is not anchored to the start of the line.
Future<List<String>> _spawned(String engine) async {
  final out = await Process.run('pgrep', ['-f', RegExp.escape(engine)]);
  return (out.stdout as String)
      .split('\n')
      .where((pid) => pid.trim().isNotEmpty)
      .toList();
}

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 250 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

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
    dir = Directory.systemTemp.createTempSync('fpai_stop_starting_');
    engine = p.join(dir.path, 'koboldcpp');
    // Sleeps a second at a time, so a stop that lands while the script is
    // starting cannot leave a long sleeper behind.
    File(engine).writeAsStringSync(
      "#!/bin/sh\ntrap 'exit 0' TERM\nwhile :; do sleep 1; done\n",
    );
    await Process.run('chmod', ['755', engine]);
    model = p.join(dir.path, 'model.gguf');
    File(model).writeAsBytesSync([...'GGUF'.codeUnits, 3, 0, 0, 0]);
  });

  tearDown(() async {
    await kobold.stopKobold();
    kobold.dispose();
    final admin = koboldAdminDirFor(storage);
    if (FileSystemEntity.isFileSync(admin)) File(admin).deleteSync();
    final left = await _spawned(engine);
    dir.deleteSync(recursive: true);
    expect(left, isEmpty, reason: 'no engine is left running after the test');
  });

  final skipOnWindows = Platform.isWindows
      ? 'the engine here is a shell script'
      : false;

  test('Stop pressed while the free memory is being read: nothing is spawned, '
      'and the start says it was stopped', () async {
    final gate = Completer<FreeMemoryMb?>();
    var reads = 0;
    kobold.readFreeMemory = () {
      reads++;
      return gate.future;
    };

    final start = kobold.startKobold(engine, model, port: 5997);
    await _until(() => reads == 1);
    expect(reads, 1, reason: 'the start reached its preparation');
    expect(kobold.isStarting, isTrue);
    expect(kobold.isRunning, isFalse);

    await kobold.stopKobold(); // the Stop button, as Settings calls it
    gate.complete(null);
    final result = await start;

    printOnFailure(
      'result: started=${result.started} message=${result.message}\n'
      'logs:\n${kobold.logs.join('\n')}',
    );
    expect(result.started, isFalse);
    expect(result.message, _stopPressed);
    expect(kobold.isRunning, isFalse);
    expect(kobold.isStarting, isFalse, reason: 'the start slot is released');
    expect(await _spawned(engine), isEmpty, reason: 'nothing was spawned');
  }, skip: skipOnWindows);

  test('Stop pressed during the first-run graphics card check: nothing is '
      'spawned, and the status stops saying it is checking', () async {
    final gate = Completer<HardwareInfo?>();
    var asked = 0;
    kobold.hardwareWhenKnown = () {
      asked++;
      return gate.future;
    };

    final start = kobold.startKobold(engine, model, port: 5997);
    await _until(() => asked == 1);
    expect(asked, 1, reason: 'the start waited for the hardware');
    expect(kobold.modelLoadingStatus, 'Checking your graphics card...');

    await kobold.stopKobold();
    expect(kobold.modelLoadingStatus, isEmpty);
    gate.complete(null);
    final result = await start;

    printOnFailure('logs:\n${kobold.logs.join('\n')}');
    expect(result.started, isFalse);
    expect(result.message, _stopPressed);
    expect(await _spawned(engine), isEmpty, reason: 'nothing was spawned');
  }, skip: skipOnWindows);

  test('the start after a called-off one goes ahead', () async {
    final gate = Completer<FreeMemoryMb?>();
    var reads = 0;
    kobold.readFreeMemory = () {
      reads++;
      return gate.future;
    };
    final first = kobold.startKobold(engine, model, port: 5997);
    await _until(() => reads == 1);
    await kobold.stopKobold();
    gate.complete(null);
    expect((await first).message, _stopPressed);

    final again = await kobold.startKobold(engine, model, port: 5997);

    printOnFailure('logs:\n${kobold.logs.join('\n')}');
    expect(again.started, isTrue);
    expect(again.message, isNull);
    expect(kobold.isRunning, isTrue);
    expect(await _spawned(engine), isNotEmpty);
  }, skip: skipOnWindows);

  test('a start that replaces a running engine is not called off by its own '
      'stop of that engine', () async {
    // Running, but with no process of its own to stop: the stop the start
    // makes returns at once, like a Stop press that finds nothing.
    kobold.debugMarkProcessRunning();

    final result = await kobold.startKobold(engine, model, port: 5997);

    printOnFailure(
      'result: started=${result.started} message=${result.message}\n'
      'logs:\n${kobold.logs.join('\n')}',
    );
    expect(result.started, isTrue);
    expect(result.message, isNull);
    expect(kobold.isRunning, isTrue);
    expect(await _spawned(engine), isNotEmpty);
  }, skip: skipOnWindows);
}
