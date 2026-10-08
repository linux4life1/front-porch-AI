// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// App-start autostart waits a few seconds before it starts KoboldCpp. An
// engine the user started in that time is left alone: a launch would stop
// it and start it again, throwing away a load in progress. The real
// SetupService.runAutoSetup (its wait included) drives the real
// KoboldService.launch; the engine is marked running with the service's
// own test hook, and only the stop is replaced (counted, nothing killed).
// The engine file does not exist, so a start that gets past the stop ends
// in a refusal, never a process.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/services/kobold_admin_swap.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/setup_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';

import 'kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;
import 'setup_service_test.dart' show FakeBackendManager;

class _Engine extends KoboldService {
  _Engine(super.storage);

  final calls = <String>[];

  @override
  Future<void> stopKobold() async => calls.add('stop');

  @override
  Future<KoboldLaunchResult> startKobold(
    String executablePath,
    String modelPath, {
    String? kcppsPath,
    String? mmprojPath,
    int port = 5001,
    int gpuLayers = 0,
    int contextSize = 4096,
    bool useVulkan = false,
    bool useCublas = false,
    bool useMetal = false,
    bool useRocm = false,
  }) {
    calls.add('start');
    return super.startKobold(
      executablePath,
      modelPath,
      kcppsPath: kcppsPath,
      mmprojPath: mmprojPath,
      port: port,
      gpuLayers: gpuLayers,
      contextSize: contextSize,
      useVulkan: useVulkan,
      useCublas: useCublas,
      useMetal: useMetal,
      useRocm: useRocm,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  late StorageService storage;
  late Directory dir;
  late _Engine kobold;
  late SetupService setup;

  setUp(() async {
    storage = await createStorageService();
    dir = Directory.systemTemp.createTempSync('fpai_autostart_');
    final model = p.join(dir.path, 'model.gguf');
    File(model).writeAsBytesSync([...'GGUF'.codeUnits, 3, 0, 0, 0]);
    final b = storage.backendSettings;
    await b.setBackendType('kobold');
    await b.setBackendChoiceDone(true);
    await b.setAutostartBackend(true);
    await b.setLastUsedModelPath(model);
    kobold = _Engine(storage);
    setup = SetupService(
      storage,
      FakeBackendManager(installedPath: p.join(dir.path, 'no-koboldcpp')),
      kobold,
    );
    expect(resolveKoboldLaunch(storage).canLaunch, isTrue);
  });

  tearDown(() {
    kobold.dispose();
    final admin = koboldAdminDirFor(storage);
    if (FileSystemEntity.isFileSync(admin)) File(admin).deleteSync();
    dir.deleteSync(recursive: true);
  });

  test('an engine the user started during the wait is left alone', () async {
    final run = setup.runAutoSetup();
    kobold.debugMarkProcessRunning();
    await run;
    expect(
      kobold.calls,
      isEmpty,
      reason: 'autostart stopped the running engine to start it again',
    );
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('with nothing running, autostart still starts', () async {
    await setup.runAutoSetup();
    expect(kobold.calls, ['start']);
    expect(kobold.isRunning, isFalse, reason: 'no engine file: refused');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
