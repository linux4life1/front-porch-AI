// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The saved ComfyUI address can name a port nothing runs on (a stale one from
// testing, or ComfyUI Desktop picked another). The models folder and its
// per-kind folders still come from the ComfyUI that is running.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/image/comfy_model_paths.dart';
import 'package:front_porch_ai/services/image/local_model_roots.dart';

void main() {
  late Directory dir;
  late String models;
  late String bigDrive;
  late File yaml;
  late ComfyMachineLayout layout;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('comfy-stale-port');
    addTearDown(() => dir.deleteSync(recursive: true));
    models = p.join(dir.path, 'Documents', 'ComfyUI', 'models');
    bigDrive = p.join(dir.path, 'big');
    final loras = Directory(p.join(models, 'loras'))
      ..createSync(recursive: true);
    File(p.join(loras.path, 'style.safetensors')).writeAsStringSync('weights');
    yaml = File(p.join(dir.path, 'desktop', 'extra_models_config.yaml'))
      ..createSync(recursive: true)
      ..writeAsStringSync('''
comfyui_desktop:
  base_path: $models
  is_default: true
  checkpoints: $bigDrive/checkpoints/
  loras: loras/
''');
    // Nothing on the machine but the running server says where anything is.
    layout = ComfyMachineLayout(
      os: ComfyHostOs.linux,
      home: dir.path,
      desktopConfigDirs: const [],
      extraModelConfigFiles: const [],
      installSearchRoots: const [],
      webuiPackageRoots: const [],
    );
  });

  ComfyProcessSnapshot desktop() => ComfyProcessSnapshot(
    command:
        'python main.py --listen 127.0.0.1 --port 8188 '
        '--extra-model-paths-config "${yaml.path}"',
    cwd: dir.path,
  );

  test(
    'the models folder comes from the running ComfyUI on another port',
    () async {
      final found = await discoverComfyModelsRoot(
        preferPort: 8189,
        layout: layout,
        scanMachine: false,
        processes: [desktop()],
      );
      expect(found, models);
    },
  );

  test('so do the folders its config sends each kind to', () async {
    final kinds = await discoverComfyTypeFolders(
      models,
      preferPort: 8189,
      layout: layout,
      scanMachine: false,
      processes: [desktop()],
    );
    expect(kinds['checkpoints'], p.join(bigDrive, 'checkpoints'));
  });
}
