// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Why KoboldCpp stopped stays on the status line until the next Start or
// Stop (kobold_stop_reason_status_test.dart), even when something else
// answers on its port. A start polls the port every five seconds until the
// model is ready; an engine that exits before that left the poll running, and
// any program answering there (a second KoboldCpp, a leftover one) made the
// app mark a dead engine "ready", which wiped the reason from the desktop's
// card, the home screen and the phone. Stop and exit handling stay as they
// were: the poll now only listens for the process the app runs.
//
// The real KoboldService and a real process: the "engine" is a shell script
// that prints what KoboldCpp prints when it runs out of graphics memory and
// exits. The program on the port is a real listening server, standing in for
// whatever else might be there. POSIX only.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:path/path.dart' as p;

import '../kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

Future<void> _until(bool Function() done, {int tries = 300}) async {
  for (var i = 0; i < tries && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  late StorageService storage;
  late KoboldService kobold;
  late Directory dir;
  late String model;
  late HttpServer stranger;

  /// Version requests the program on the port was sent.
  var asked = 0;

  /// It answers "200 OK" once [answerWhen] says so, and holds the request
  /// until then (up to ten seconds), as a busy program might.
  late bool Function() answerWhen;

  setUp(() async {
    // Real requests: the test binding answers every one with 400 otherwise.
    HttpOverrides.global = null;
    storage = await createStorageService();
    kobold = KoboldService(storage);
    dir = Directory.systemTemp.createTempSync('fpai_reason_sticks_');
    model = p.join(dir.path, 'model.gguf');
    File(model).writeAsBytesSync([...'GGUF'.codeUnits, 3, 0, 0, 0]);
    asked = 0;
    answerWhen = () => true;
    stranger = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    stranger.listen((request) async {
      if (request.uri.path == '/api/extra/version') asked++;
      await _until(answerWhen, tries: 500);
      request.response
        ..statusCode = answerWhen() ? 200 : 503
        ..write('{"result":"KoboldCpp","version":"1.122.1"}');
      await request.response.close();
    });
    kobold.setBaseUrl('http://127.0.0.1:${stranger.port}');
  });

  tearDown(() async {
    await kobold.stopKobold();
    kobold.dispose();
    await stranger.close(force: true);
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

  /// An engine that runs out of graphics memory after [seconds].
  String dyingAfter(String seconds) {
    final script = p.join(dir.path, 'koboldcpp-dies');
    File(script).writeAsStringSync(
      '#!/bin/sh\n'
      'sleep $seconds\n'
      "echo 'ggml_backend_cuda_buffer_type_alloc_buffer: allocating 9000.00 "
      "MiB on device 0: cudaMalloc failed: out of memory'\n"
      'sleep 0.3\n'
      'exit 1\n',
    );
    Process.runSync('chmod', ['755', script]);
    return script;
  }

  /// Waits past the start's first readiness poll (five seconds after the
  /// spawn), then says whether the reason is still what every screen reads.
  Future<void> expectReasonKept(Stopwatch since) async {
    await _until(
      () => since.elapsed > const Duration(milliseconds: 6800),
      tries: 600,
    );
    printOnFailure(
      'version requests: $asked\nlogs:\n${kobold.logs.join('\n')}',
    );
    expect(kobold.lastFailure, isNotNull);
    expect(kobold.modelLoadingStatus, kobold.lastFailure!.message);
    expect(kobold.modelLoadingStatus, contains('ran out of graphics memory'));
    expect(kobold.phase, KoboldPhase.stopped);
  }

  test('an engine that exits before it is ready: something answering on its '
      'port at the next poll does not wipe why it stopped', () async {
    answerWhen = () => kobold.lastFailure != null;
    final since = Stopwatch()..start();
    final started = await kobold.startKobold(
      dyingAfter('0'),
      model,
      port: stranger.port,
    );
    expect(started.started, isTrue, reason: 'it was spawned');
    await _until(() => kobold.lastFailure != null);
    expect(kobold.isRunning, isFalse, reason: 'it stopped on its own');

    await expectReasonKept(since);
  }, skip: skipOnWindows);

  test('an engine that exits while the poll waits for an answer: the late '
      'answer does not wipe why it stopped', () async {
    // The poll at five seconds asks while the engine still runs; the
    // answer comes once it has exited.
    answerWhen = () => kobold.lastFailure != null;
    final since = Stopwatch()..start();
    final started = await kobold.startKobold(
      dyingAfter('5.4'),
      model,
      port: stranger.port,
    );
    expect(started.started, isTrue, reason: 'it was spawned');
    await _until(() => kobold.lastFailure != null, tries: 450);
    expect(kobold.isRunning, isFalse, reason: 'it stopped on its own');
    expect(asked, greaterThan(0), reason: 'the poll asked while it ran');

    await expectReasonKept(since);
  }, skip: skipOnWindows);
}
