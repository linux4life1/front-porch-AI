// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Stop pressed while a start is still being prepared calls that start off
// before KoboldCpp is spawned (kobold_stop_while_starting_test). The phone's
// Stop (POST /api/backend/stop) and the provider's stopAllManagedProcesses
// that it calls only stopped an engine that was running, so against a start
// that was still preparing they did nothing and the engine spawned anyway.
//
// The real facade, LLM provider and KoboldCpp service run; only a wait inside
// the preparation is held open, through the production seam, so Stop lands
// inside it. The "engine" is a shell script that sleeps, so a spawn is visible
// and harmless. POSIX only.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/backend_facade.dart';

import '../../golden/support/fakes_services.dart';
import '../kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

const _stopPressed =
    'KoboldCpp was not started: it was stopped while it was getting ready.';

class _Backend extends BackendManager {
  _Backend(super.storage, this.exe);
  final String exe;

  @override
  String? get backendPath => exe;
}

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
  late LLMProvider provider;
  late BackendFacade facade;
  late Directory dir;
  late String engine;
  late String model;

  setUp(() async {
    storage = await createStorageService();
    kobold = KoboldService(storage);
    dir = Directory.systemTemp.createTempSync('fpai_phone_stop_');
    engine = p.join(dir.path, 'koboldcpp');
    // Sleeps a second at a time, so a stop that lands while the script is
    // starting cannot leave a long sleeper behind.
    File(engine).writeAsStringSync(
      "#!/bin/sh\ntrap 'exit 0' TERM\nwhile :; do sleep 1; done\n",
    );
    await Process.run('chmod', ['755', engine]);
    model = p.join(dir.path, 'model.gguf');
    File(model).writeAsBytesSync([...'GGUF'.codeUnits, 3, 0, 0, 0]);
    provider = LLMProvider(
      kobold,
      OpenRouterService(apiUrl: '', apiKey: '', modelName: ''),
      storage,
      _Backend(storage, engine),
    );
    facade = BackendFacade(provider, storage, FakeModelManager());
  });

  tearDown(() async {
    await kobold.stopKobold();
    provider.dispose();
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

  /// A start held in its free-memory read, with [gate] to let it go on.
  Future<({Future<KoboldLaunchResult> start, Completer<FreeMemoryMb?> gate})>
  preparing() async {
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
    return (start: start, gate: gate);
  }

  test('the phone\'s Stop while a start is being prepared: nothing is '
      'spawned, and the start says it was stopped', () async {
    final held = await preparing();

    await facade.stop();
    held.gate.complete(null);
    final result = await held.start;

    printOnFailure(
      'result: started=${result.started} message=${result.message}\n'
      'logs:\n${kobold.logs.join('\n')}',
    );
    expect(result.started, isFalse);
    expect(result.message, _stopPressed);
    expect(kobold.isStarting, isFalse, reason: 'the start slot is released');
    expect(await _spawned(engine), isEmpty, reason: 'nothing was spawned');
  }, skip: skipOnWindows);

  test('stopAllManagedProcesses while a start is being prepared calls it '
      'off too', () async {
    final held = await preparing();

    await provider.stopAllManagedProcesses();
    held.gate.complete(null);
    final result = await held.start;

    expect(result.message, _stopPressed);
    expect(await _spawned(engine), isEmpty, reason: 'nothing was spawned');
  }, skip: skipOnWindows);
}
