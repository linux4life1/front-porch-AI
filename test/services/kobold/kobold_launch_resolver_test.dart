// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// One rule for "which model does this launch load", checked against real
// files on disk: the active preset's own model when it is here, otherwise
// the model just picked, otherwise the last-used one. And the phone's model
// switch, which must bring the new model's own preset or none.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/backend_facade.dart';
import 'package:path/path.dart' as p;

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_services.dart';
import '../../golden/support/fakes_storage.dart';

class _Kobold extends FakeKoboldService {
  bool running = false;

  @override
  bool get isProcessRunning => running;
}

class _Llm extends FakeLLMProvider {
  int restarts = 0;
  int reloads = 0;
  final kobold = _Kobold();

  @override
  KoboldService get koboldService => kobold;

  @override
  Future<void> reloadChatKobold() async => reloads++;

  @override
  Future<void> stopAllManagedProcesses() async {}

  @override
  Future<void> ensureManagedBackendIsRunning({
    bool forGpuSwap = false,
    String? modelPath,
    String? kcppsPath,
  }) async => restarts++;
}

void main() {
  late Directory dir;
  late FakeStorageService storage;

  /// A file with the GGUF magic, enough for the app's model check.
  String model(String name) => (File(
    p.join(dir.path, name),
  )..writeAsBytesSync('GGUF'.codeUnits + List.filled(32, 0))).path;

  String preset(String name, String json) =>
      (File(p.join(dir.path, name))..writeAsStringSync(json)).path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fpai resolver');
    storage = FakeStorageService();
  });

  // The storage double is left undisposed: its constructor starts setters
  // that finish (and notify) after a quick test has already ended.
  tearDown(() => dir.deleteSync(recursive: true));

  group('which model a launch loads', () {
    test('no preset: the last-used model', () async {
      final a = model('a.gguf');
      await storage.backendSettings.setLastUsedModelPath(a);

      final launch = resolveKoboldLaunch(storage);
      expect(launch.modelPath, a);
      expect(launch.kcppsPath, isNull);
      expect(launch.note, isNull);
    });

    test('a model picked just now wins over the last-used one', () async {
      final a = model('a.gguf');
      final b = model('b.gguf');
      await storage.backendSettings.setLastUsedModelPath(a);
      expect(resolveKoboldLaunch(storage, pickedModel: b).modelPath, b);
    });

    test('a preset that names a model on this disk loads that model, '
        'whatever was picked or used last', () async {
      final a = model('a.gguf');
      final b = model('b.gguf');
      final owned = preset('b.kcpps', '{"model_param": "$b"}');
      await storage.backendSettings.setLastUsedModelPath(a);
      await storage.backendSettings.setActiveKcppsPath(owned);

      final launch = resolveKoboldLaunch(storage, pickedModel: a);
      expect(launch.modelPath, b);
      expect(launch.kcppsPath, owned);
    });

    test('a preset from another computer keeps its settings and runs the '
        'model chosen here, and says so', () async {
      final a = model('a.gguf');
      final foreign = preset(
        'theirs.kcpps',
        '{"model_param": "/somewhere/else/big-model.gguf"}',
      );
      await storage.backendSettings.setLastUsedModelPath(a);
      await storage.backendSettings.setActiveKcppsPath(foreign);

      final launch = resolveKoboldLaunch(storage);
      expect(launch.modelPath, a);
      expect(launch.kcppsPath, foreign);
      expect(launch.note, contains('big-model.gguf'));
    });

    test('a preset with no model of its own runs the picked model', () async {
      final a = model('a.gguf');
      final plain = preset('plain.kcpps', '{"contextsize": 8192}');
      await storage.backendSettings.setActiveKcppsPath(plain);

      final launch = resolveKoboldLaunch(storage, pickedModel: a);
      expect(launch.modelPath, a);
      expect(launch.kcppsPath, plain);
      expect(launch.note, isNull);
    });

    test('a preset whose file is gone is dropped, with a reason', () async {
      final a = model('a.gguf');
      final gone = preset('gone.kcpps', '{}');
      await storage.backendSettings.setLastUsedModelPath(a);
      await storage.backendSettings.setActiveKcppsPath(gone);
      File(gone).deleteSync();

      final launch = resolveKoboldLaunch(storage);
      expect(launch.modelPath, a);
      expect(launch.kcppsPath, isNull);
      expect(launch.note, contains('gone.kcpps'));
    });

    test(
      'the vision file is the resolved model\'s, not the picked one\'s',
      () async {
        final a = model('a.gguf');
        final b = model('b.gguf');
        await storage.presetSettings.setModelMmproj(a, '/v/a-proj.gguf');
        await storage.presetSettings.setModelMmproj(b, '/v/b-proj.gguf');
        await storage.backendSettings.setActiveKcppsPath(
          preset('b.kcpps', '{"model_param": "$b"}'),
        );
        expect(
          resolveKoboldLaunch(storage, pickedModel: a).mmprojPath,
          '/v/b-proj.gguf',
        );
      },
    );

    test('nothing chosen yet: nothing to launch, and a plain reason', () async {
      expect(resolveKoboldLaunch(storage).canLaunch, isFalse);
      expect(await koboldLaunchProblem(storage), 'Please select a model.');
    });

    test('the model is read before launching, so a file that is not a '
        'model is refused with its reason', () async {
      final bad = (File(
        p.join(dir.path, 'bad.gguf'),
      )..writeAsStringSync('not a model')).path;
      expect(
        await koboldLaunchProblem(storage, pickedModel: bad),
        contains('Not a valid GGUF'),
      );
      expect(
        await koboldLaunchProblem(storage, pickedModel: model('ok.gguf')),
        isNull,
      );
    });
  });

  group('picking a model', () {
    test('brings that model\'s own preset, or none', () async {
      final a = model('a.gguf');
      final b = model('b.gguf');
      final aPreset = preset('a.kcpps', '{"contextsize": 4096}');
      await storage.presetSettings.setModelPreset(a, aPreset);

      await selectKoboldModel(storage, a);
      expect(storage.backendSettings.lastUsedModelPath, a);
      expect(storage.backendSettings.activeKcppsPath, aPreset);

      // B has no preset: A's must not stay active.
      await selectKoboldModel(storage, b);
      expect(storage.backendSettings.lastUsedModelPath, b);
      expect(storage.backendSettings.activeKcppsPath, isNull);

      // A preset that was deleted is not brought back.
      File(aPreset).deleteSync();
      await selectKoboldModel(storage, a);
      expect(storage.backendSettings.activeKcppsPath, isNull);
    });

    test('switching model from the phone leaves the old model\'s preset '
        'behind and restarts the engine', () async {
      final small = model('small.gguf');
      final big = model('big.gguf');
      final smallPreset = preset(
        'small.kcpps',
        '{"model_param": "$small", "contextsize": 4096}',
      );
      await storage.presetSettings.setModelPreset(small, smallPreset);
      await selectKoboldModel(storage, small);

      LocalModelInfo info(String path) => LocalModelInfo(
        path: path,
        filename: p.basename(path),
        sizeBytes: 36,
        modified: DateTime(2026),
      );
      final llm = _Llm();
      addTearDown(llm.dispose);
      final facade = BackendFacade(
        llm,
        storage,
        FakeModelManager(localModels: [info(small), info(big)]),
      );

      expect(await facade.switchModel(big), isTrue);

      expect(llm.restarts, 1);
      final launch = resolveKoboldLaunch(storage);
      expect(launch.modelPath, big, reason: 'not the old preset\'s model');
      expect(launch.kcppsPath, isNull);

      // A path the app does not know is refused and changes nothing.
      expect(await facade.switchModel('/etc/passwd'), isFalse);
      expect(storage.backendSettings.lastUsedModelPath, big);

      // With KoboldCpp running, the new model is loaded in place.
      llm.kobold.running = true;
      expect(await facade.switchModel(small), isTrue);
      expect(llm.reloads, 1);
      expect(llm.restarts, 1, reason: 'no second restart');
      expect(resolveKoboldLaunch(storage).modelPath, small);
    });
  });
}
