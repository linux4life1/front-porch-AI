// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Which model a preset names. One rule, the one KoboldCpp itself uses, read
// in one place: Settings shows what it returns and a launch loads what it
// returns. And a model named by a relative path, which KoboldCpp resolves
// against the folder it runs in: the engine folder.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:path/path.dart' as p;

import '../kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

/// Records the start a launch asks for instead of running an engine.
class _Service extends KoboldService {
  _Service(super.storage);
  final List<String> startedModels = [];

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
  }) async {
    startedModels.add(modelPath);
    return const KoboldLaunchResult.started();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  late StorageService storage;
  late Directory dir;

  /// A file with the GGUF magic, enough for the app's model check.
  String model(String path) {
    final file = File(path)..createSync(recursive: true);
    file.writeAsBytesSync('GGUF'.codeUnits + List.filled(32, 0));
    return file.path;
  }

  Future<String> activate(Map<String, dynamic> content) async {
    final file = File(p.join(dir.path, 'mine.kcpps'))
      ..writeAsStringSync(jsonEncode(content));
    await storage.backendSettings.setActiveKcppsPath(file.path);
    return file.path;
  }

  setUp(() async {
    storage = await createStorageService();
    dir = Directory.systemTemp.createTempSync('fpai model path');
    storage.binDir.createSync(recursive: true);
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
    for (final left in storage.binDir.listSync()) {
      left.deleteSync(recursive: true);
    }
  });

  test('the model a config names is found the way KoboldCpp finds it', () {
    expect(
      kcppsModelOf({'model_param': '/m/a.gguf', 'model': '/m/b.gguf'}),
      '/m/a.gguf',
    );
    // An empty `model_param` does not hide `model`.
    expect(kcppsModelOf({'model_param': '', 'model': 'x'}), 'x');
    expect(kcppsModelOf({'model_param': '  ', 'model': 'x'}), 'x');
    expect(kcppsModelOf({'model_param': null, 'model': 'x'}), 'x');
    // The list form KoboldCpp's launcher saves: its first entry.
    expect(
      kcppsModelOf({
        'model': ['x'],
      }),
      'x',
    );
    expect(
      kcppsModelOf({
        'model': ['x', 'y'],
      }),
      'x',
    );
    expect(
      kcppsModelOf({
        'model_param': '',
        'model': ['x'],
      }),
      'x',
    );
    // Nothing named.
    expect(kcppsModelOf({}), '');
    expect(kcppsModelOf({'model': <Object?>[]}), '');
    expect(kcppsModelOf({'model': ''}), '');
    expect(
      kcppsModelOf({
        'model_param': 7,
        'model': [7],
      }),
      '',
    );
  });

  for (final (what, content)
      in <(String, Map<String, dynamic> Function(String))>[
        (
          'an empty model_param beside model',
          (x) => {'model_param': '', 'model': x},
        ),
        (
          'model as a list',
          (x) => {
            'model': [x],
          },
        ),
      ]) {
    test('$what: Settings and the launch name the same model', () async {
      final x = model(p.join(dir.path, 'x.gguf'));
      await activate(content(x));

      expect(storage.backendSettings.kcppsModelPath, x);
      expect(storage.backendSettings.kcppsHasModel, isTrue);

      final launch = resolveKoboldLaunch(storage);
      expect(launch.modelPath, x);
    });
  }

  group('a model named by a relative path', () {
    test(
      'is looked for in the engine folder, and comes back as a full path',
      () async {
        final engineDir = Directory(p.join(dir.path, 'engine'))..createSync();
        final rel = model(p.join(engineDir.path, 'rel.gguf'));
        await activate({'model_param': 'rel.gguf'});

        final launch = resolveKoboldLaunch(storage, engineDir: engineDir.path);
        expect(launch.modelPath, rel);
        expect(p.isAbsolute(launch.modelPath), isTrue);
      },
    );

    test('with no folder given, the app\'s own engine folder is used, and '
        'Settings names the same file', () async {
      final rel = model(p.join(storage.binDir.path, 'rel.gguf'));
      await activate({'model_param': 'rel.gguf'});

      final launch = resolveKoboldLaunch(storage);
      expect(launch.modelPath, rel);

      // Settings, the vision check and the thinking settings all read this.
      expect(storage.backendSettings.kcppsModelPath, rel);
      expect(storage.backendSettings.kcppsModelFileExists, isTrue);
    });

    test('the same holds for a vision file named by a relative path', () async {
      final proj = model(p.join(storage.binDir.path, 'proj.gguf'));
      await activate({'model_param': 'rel.gguf', 'mmproj': 'proj.gguf'});
      expect(storage.backendSettings.kcppsMmprojPath, proj);

      // A full path, and none, are as they were.
      await activate({'mmproj': '/elsewhere/proj.gguf'});
      expect(storage.backendSettings.kcppsMmprojPath, '/elsewhere/proj.gguf');
      await activate({'mmproj': ''});
      expect(storage.backendSettings.kcppsMmprojPath, isNull);
    });

    test(
      'in a folder below or beside the engine folder is found too',
      () async {
        final engineDir = Directory(p.join(dir.path, 'engine'))..createSync();
        final below = model(p.join(engineDir.path, 'models', 'below.gguf'));
        await activate({'model_param': p.join('models', 'below.gguf')});
        expect(
          resolveKoboldLaunch(storage, engineDir: engineDir.path).modelPath,
          below,
        );

        final beside = model(p.join(dir.path, 'models', 'beside.gguf'));
        await activate({'model_param': p.join('..', 'models', 'beside.gguf')});
        expect(
          resolveKoboldLaunch(storage, engineDir: engineDir.path).modelPath,
          beside,
        );
      },
    );

    test(
      'that is not there falls back to the picked model, and says so',
      () async {
        final picked = model(p.join(dir.path, 'picked.gguf'));
        final preset = await activate({'model_param': 'gone.gguf'});

        final launch = resolveKoboldLaunch(
          storage,
          pickedModel: picked,
          engineDir: dir.path,
        );
        expect(launch.modelPath, picked);
        expect(launch.kcppsPath, preset);
        expect(launch.note, contains('gone.gguf'));
      },
    );

    test(
      'is started, and recorded as the model in use, by its full path',
      () async {
        final engineDir = Directory(p.join(dir.path, 'engine'))..createSync();
        final rel = model(p.join(engineDir.path, 'rel.gguf'));
        await activate({'model_param': 'rel.gguf'});
        final kobold = _Service(storage);
        addTearDown(kobold.dispose);

        final result = await kobold.launch(p.join(engineDir.path, 'koboldcpp'));

        expect(result.started, isTrue, reason: result.message);
        expect(kobold.startedModels, [rel]);
        expect(storage.backendSettings.lastUsedModelPath, rel);
      },
    );
  });
}
