// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A start that cannot go ahead must leave the next one possible.
//
// KoboldService marks itself "starting" before it prepares a launch. A
// failure in that preparation that was not the one expected kind used to
// leave the mark set: every later start was turned away ("KoboldCpp is
// already starting."), the Settings button offered "stop" for an engine
// that was not there, Stop did not clear it, and only restarting the app
// did. One preset file was enough: a number too large to hold.
//
// No engine is started here. The starts that are refused run the real
// service and stop before anything is spawned; the start that has to
// succeed afterwards is counted, not run.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/services/kobold_admin_swap.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:path/path.dart' as p;

import '../kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

class _Service extends KoboldService {
  _Service(super.storage);

  /// When set, a start is counted instead of run.
  bool countOnly = false;
  int starts = 0;

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
    if (!countOnly) {
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
    starts++;
    return Future.value(const KoboldLaunchResult.started());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  late StorageService storage;
  late _Service kobold;
  late Directory dir;
  late String engine;
  late String model;

  setUp(() async {
    storage = await createStorageService();
    kobold = _Service(storage);
    dir = Directory.systemTemp.createTempSync('fpai_start_');
    // Never created: nothing here gets as far as running it.
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

  String preset(String name, List<int> bytes) =>
      (File(p.join(dir.path, name))..writeAsBytesSync(bytes)).path;

  Future<KoboldLaunchResult> launchWith(String? presetPath) async {
    await storage.backendSettings.setActiveKcppsPath(presetPath);
    return kobold.launch(engine, pickedModel: model, port: 5999);
  }

  /// With no preset and a good model, Start is not turned away.
  Future<void> expectStartStillWorks() async {
    expect(kobold.isStarting, isFalse);
    kobold.countOnly = true;
    final next = await launchWith(null);
    expect(next.started, isTrue, reason: next.message);
    expect(kobold.starts, 1);
  }

  test(
    'a preset with a number too large to hold: finding the model, '
    'checking the launch and launching all answer, and none throws',
    () async {
      final bad = preset('bad.kcpps', '{"contextsize": 1e999}'.codeUnits);
      await storage.backendSettings.setActiveKcppsPath(bad);

      final resolved = resolveKoboldLaunch(storage, pickedModel: model);
      expect(resolved.modelPath, model);
      expect(resolved.kcppsPath, bad);

      final problem = await koboldLaunchProblem(storage, pickedModel: model);
      expect(problem, contains('bad.kcpps'));
      expect(problem, contains('too large'));

      final result = await kobold.launch(
        engine,
        pickedModel: model,
        port: 5999,
      );
      expect(result.started, isFalse);
      expect(result.message, contains('bad.kcpps'));
      expect(result.message, contains('too large'));

      await expectStartStillWorks();
    },
  );

  // What is in the file, and a word of the reason the user is given.
  final unreadable = <String, (List<int>, String)>{
    'not JSON at all': ('{not json'.codeUnits, 'not valid'),
    'a list, not a config': ('[1, 2]'.codeUnits, 'not a KoboldCpp config'),
    'an empty file': (const [], 'not valid'),
    // This one passed every check before the launch and stopped it while
    // the config was being written: the case that left Start dead.
    'a number too large to hold, in a setting the app only passes on': (
      '{"noswa": true, "defaultgenamt": 1e999}'.codeUnits,
      'too large',
    ),
    'saved as UTF-16 by a text editor': (
      [
        0xFF,
        0xFE,
        for (final c in '{"contextsize": 4096}'.codeUnits) ...[c, 0],
      ],
      'could not be opened',
    ),
  };

  for (final MapEntry(key: what, value: (bytes, reason))
      in unreadable.entries) {
    test('a preset that is $what is refused in plain words, and Start is '
        'not turned away afterwards', () async {
      final result = await launchWith(preset('bad.kcpps', bytes));

      expect(result.started, isFalse);
      expect(result.message, contains('bad.kcpps'));
      expect(result.message, contains(reason));
      expect(kobold.isRunning, isFalse);
      expect(kobold.logs.join('\n'), contains('bad.kcpps'));

      await expectStartStillWorks();
    });
  }

  test('the start a model swap makes itself, with a preset that cannot be '
      'read, also releases Start', () async {
    // A swap starts the engine directly with the helper model's own preset.
    final folder = Directory(p.join(dir.path, 'a-folder.kcpps'))..createSync();
    for (final bad in [
      preset('helper.kcpps', '{"contextsize": 1e999}'.codeUnits),
      preset(
        'helper2.kcpps',
        '{"noswa": true, "defaultgenamt": 1e999}'.codeUnits,
      ),
      folder.path,
    ]) {
      await kobold.startKobold(engine, model, kcppsPath: bad, port: 5999);
      expect(kobold.isStarting, isFalse, reason: bad);
      expect(kobold.isRunning, isFalse, reason: bad);
      expect(kobold.logs.join('\n'), contains(p.basename(bad)));
    }

    await expectStartStillWorks();
  });

  test('a launch whose config cannot be written is refused with the reason, '
      'and Start is not turned away once the cause is gone', () async {
    // Something else sits where the app's config folder has to be.
    final admin = koboldAdminDirFor(storage);
    final folder = Directory(admin);
    if (folder.existsSync()) folder.deleteSync(recursive: true);
    File(admin).writeAsStringSync('in the way');

    final result = await launchWith(null);

    expect(result.started, isFalse);
    expect(result.message, contains('could not be prepared'));
    expect(kobold.isStarting, isFalse);
    expect(kobold.isRunning, isFalse);

    File(admin).deleteSync();
    await expectStartStillWorks();
  });

  test('a second start while one is under way is still turned away', () async {
    final first = kobold.launch(engine, pickedModel: model, port: 5999);
    final second = await kobold.launch(engine, pickedModel: model, port: 5999);
    expect(second.started, isFalse);
    expect(second.message, 'KoboldCpp is already starting.');
    // The first goes on to run an engine file that is not there: refused
    // in words, not thrown at the button that asked.
    final ran = await first;
    expect(ran.started, isFalse);
    expect(ran.message, contains('could not be started'));
    expect(kobold.isStarting, isFalse);
  });
}
