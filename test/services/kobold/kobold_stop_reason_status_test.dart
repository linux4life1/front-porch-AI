// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// When KoboldCpp stops on its own (out of graphics memory, a model it cannot
// read, dying in the middle of a reply), the app works out a plain sentence
// saying why (KoboldService.lastFailure). Only the engine log showed it:
// every screen just said "Stopped". The sentence now goes on the status line
// the app already has (modelLoadingStatus, which the desktop's cards and
// home screen and the phone all read), set by the exit and cleared by the
// next Start or Stop (maintainer's ruling, 2026-10-05).
//
// The real KoboldService runs: startKobold -> _spawn -> Process.start, and
// the real stopKobold is the Stop button. The "engine" is a shell script
// that prints what KoboldCpp prints when it runs out of graphics memory and
// exits, so a real process ends on its own. POSIX only.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:path/path.dart' as p;

import '../kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 300 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  late StorageService storage;
  late KoboldService kobold;
  late Directory dir;
  late String dies;
  late String sleeps;
  late String model;

  setUp(() async {
    storage = await createStorageService();
    kobold = KoboldService(storage);
    dir = Directory.systemTemp.createTempSync('fpai_stop_reason_');
    // What KoboldCpp prints when the card has no room, then its exit.
    dies = p.join(dir.path, 'koboldcpp-dies');
    File(dies).writeAsStringSync(
      '#!/bin/sh\n'
      "echo 'ggml_backend_cuda_buffer_type_alloc_buffer: allocating 9000.00 "
      "MiB on device 0: cudaMalloc failed: out of memory'\n"
      'sleep 0.5\n'
      'exit 1\n',
    );
    sleeps = p.join(dir.path, 'koboldcpp-sleeps');
    File(sleeps).writeAsStringSync(
      "#!/bin/sh\ntrap 'exit 0' TERM\nwhile :; do sleep 1; done\n",
    );
    await Process.run('chmod', ['755', dies, sleeps]);
    model = p.join(dir.path, 'model.gguf');
    File(model).writeAsBytesSync([...'GGUF'.codeUnits, 3, 0, 0, 0]);
  });

  tearDown(() async {
    await kobold.stopKobold();
    kobold.dispose();
    final left = await Process.run('pgrep', ['-f', RegExp.escape(dir.path)]);
    dir.deleteSync(recursive: true);
    expect(
      (left.stdout as String).trim(),
      isEmpty,
      reason: 'no engine is left running after the test',
    );
  });

  final skipOnWindows = Platform.isWindows
      ? 'the engine here is a shell script'
      : false;

  /// Starts the engine that dies, and waits until its exit has been noted.
  Future<void> startAndDie() async {
    final started = await kobold.startKobold(dies, model, port: 5993);
    expect(started.started, isTrue, reason: 'it was spawned');
    await _until(() => !kobold.isRunning && kobold.lastFailure != null);
    printOnFailure('logs:\n${kobold.logs.join('\n')}');
    expect(kobold.isRunning, isFalse, reason: 'it stopped on its own');
    expect(kobold.lastFailure, isNotNull);
  }

  test('an engine that stops on its own leaves why on the status line, '
      'with nothing said to be loading', () async {
    await startAndDie();

    expect(kobold.modelLoadingStatus, kobold.lastFailure!.message);
    expect(kobold.modelLoadingStatus, contains('ran out of graphics memory'));
    expect(kobold.phase, KoboldPhase.stopped);
  }, skip: skipOnWindows);

  test('Stop clears it', () async {
    await startAndDie();

    await kobold.stopKobold();

    expect(kobold.modelLoadingStatus, isEmpty);
  }, skip: skipOnWindows);

  test('the next Start clears it while it gets ready, before anything is '
      'spawned', () async {
    await startAndDie();
    final gate = Completer<FreeMemoryMb?>();
    var reads = 0;
    kobold.readFreeMemory = () {
      reads++;
      return gate.future;
    };

    final start = kobold.startKobold(sleeps, model, port: 5993);
    await _until(() => reads == 1);
    expect(kobold.isStarting, isTrue, reason: 'the start is getting ready');
    expect(kobold.modelLoadingStatus, isEmpty);

    gate.complete(null);
    expect((await start).started, isTrue);
    expect(kobold.modelLoadingStatus, 'Initializing model...');
  }, skip: skipOnWindows);
}
