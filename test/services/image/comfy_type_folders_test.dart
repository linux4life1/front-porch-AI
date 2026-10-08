// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ComfyUI's extra_model_paths can send each kind of weight to its own folder.
// Those folders must not be collapsed into one models folder: a checkpoint
// goes where the config says checkpoints live. Every YAML and folder here is
// a temp file; discovery is given its own layout and no process list.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/image/comfy_model_paths.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/image/local_model_roots.dart';
import 'package:front_porch_ai/services/image/studio_model_roots.dart';

ComfyMachineLayout _layout(String home, List<String> yamls) {
  return ComfyMachineLayout(
    os: ComfyHostOs.linux,
    home: home,
    desktopConfigDirs: const [],
    extraModelConfigFiles: yamls,
    installSearchRoots: const [],
    webuiPackageRoots: const [],
  );
}

void main() {
  late Directory dir;
  late String models;
  late String bigDrive;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('comfy-kinds');
    addTearDown(() => dir.deleteSync(recursive: true));
    models = p.join(dir.path, 'data');
    bigDrive = p.join(dir.path, 'mnt', 'big');
  });

  String yaml() =>
      '''
comfyui:
  base_path: $models
  is_default: true
  checkpoints: $bigDrive/checkpoints/
  loras: loras/
  diffusion_models: |
    $bigDrive/unet
    $models/diffusion_models
  vae: vae/
''';

  group('one YAML block', () {
    test('each kind keeps its own folder', () {
      final block = parseComfyModelYaml(yaml()).single;
      final kinds = comfyTypeFolders(
        config: block,
        yamlDir: dir.path,
        home: dir.path,
      );
      expect(kinds['checkpoints'], p.join(bigDrive, 'checkpoints'));
      expect(kinds['loras'], p.join(models, 'loras'));
      expect(kinds['diffusion_models'], p.join(bigDrive, 'unet'));
      expect(kinds['vae'], p.join(models, 'vae'));
      expect(
        comfyModelsRoot(config: block, yamlDir: dir.path, home: dir.path),
        models,
      );
    });

    test(
      'Comfy\'s older names map to the same folders, the newer name wins',
      () {
        final block = parseComfyModelYaml('''
comfyui:
  base_path: $models
  unet: $bigDrive/old_unet
  diffusion_models: $bigDrive/new_unet
  clip: $bigDrive/clip
''').single;
        final kinds = comfyTypeFolders(
          config: block,
          yamlDir: dir.path,
          home: dir.path,
        );
        expect(kinds['diffusion_models'], p.join(bigDrive, 'new_unet'));
        expect(kinds['text_encoders'], p.join(bigDrive, 'clip'));
        expect(kinds.containsKey('unet'), isFalse);
        expect(kinds.containsKey('clip'), isFalse);
      },
    );

    test('a key that is not a kind of weight is ignored', () {
      final block = parseComfyModelYaml('''
comfyui:
  base_path: $models
  custom_nodes: custom_nodes/
  loras: loras/
''').single;
      expect(
        comfyTypeFolders(config: block, yamlDir: dir.path, home: dir.path).keys,
        ['loras'],
      );
    });
  });

  group('discovery', () {
    test('finds the kinds for the chosen models folder', () async {
      final file = File(p.join(dir.path, 'extra_model_paths.yaml'))
        ..writeAsStringSync(yaml());
      final kinds = await discoverComfyTypeFolders(
        models,
        layout: _layout(dir.path, [file.path]),
        scanMachine: false,
      );
      expect(kinds['checkpoints'], p.join(bigDrive, 'checkpoints'));
    });

    test('a YAML for a different models folder does not apply', () async {
      final file = File(p.join(dir.path, 'extra_model_paths.yaml'))
        ..writeAsStringSync(yaml());
      final kinds = await discoverComfyTypeFolders(
        p.join(dir.path, 'elsewhere'),
        layout: _layout(dir.path, [file.path]),
        scanMachine: false,
      );
      expect(kinds, isEmpty);
    });
  });

  group('where a download goes', () {
    test(
      'a checkpoint goes to the config\'s checkpoints folder, a LoRA under the models folder',
      () {
        final kinds = {'checkpoints': p.join(bigDrive, 'checkpoints')};
        expect(
          civitaiDownloadPath(
            root: models,
            folder: 'checkpoints',
            name: 'dreamshaper_8.safetensors',
            typeFolders: kinds,
          ),
          p.join(bigDrive, 'checkpoints', 'dreamshaper_8.safetensors'),
        );
        expect(
          civitaiDownloadPath(
            root: models,
            folder: 'loras',
            name: 'style.safetensors',
            typeFolders: kinds,
          ),
          p.join(models, 'loras', 'style.safetensors'),
        );
      },
    );

    test('an all-in-one checkpoint also goes to the checkpoints folder', () {
      expect(
        civitaiAllInOnePath(
          root: models,
          backend: 'comfyui',
          folder: 'diffusion_models',
          modelType: 'Checkpoint',
          name: 'flux.safetensors',
          typeFolders: {'checkpoints': p.join(bigDrive, 'checkpoints')},
        ),
        p.join(bigDrive, 'checkpoints', 'flux.safetensors'),
      );
    });

    test('a relative kind folder, or a name that escapes it, is refused', () {
      expect(
        civitaiDownloadPath(
          root: models,
          folder: 'checkpoints',
          name: 'a.safetensors',
          typeFolders: {'checkpoints': 'relative/ckpts'},
        ),
        isNull,
      );
      expect(
        civitaiDownloadPath(
          root: models,
          folder: 'checkpoints',
          name: '../../a.safetensors',
          typeFolders: {'checkpoints': p.join(bigDrive, 'checkpoints')},
        ),
        isNull,
      );
    });
  });

  test('installed files are read from each kind\'s own folder', () async {
    File(p.join(bigDrive, 'checkpoints', 'far.safetensors'))
      ..createSync(recursive: true)
      ..writeAsStringSync('w');
    File(p.join(models, 'checkpoints', 'near.safetensors'))
      ..createSync(recursive: true)
      ..writeAsStringSync('w');
    final names = await civitaiSlotNames(
      root: models,
      backend: 'comfyui',
      lora: false,
      typeFolders: {'checkpoints': p.join(bigDrive, 'checkpoints')},
    );
    expect(names, contains('far.safetensors'));
    expect(names, isNot(contains('near.safetensors')));
  });

  test(
    'stale partial downloads are cleared in each kind\'s own folder',
    () async {
      final part =
          File(
              civitaiPartPath(p.join(bigDrive, 'checkpoints', 'x.safetensors')),
            )
            ..createSync(recursive: true)
            ..setLastModifiedSync(
              DateTime.now().subtract(const Duration(hours: 3)),
            );
      Directory(models).createSync(recursive: true);
      expect(
        await sweepCivitaiParts(
          models,
          typeFolders: {'checkpoints': p.join(bigDrive, 'checkpoints')},
        ),
        1,
      );
      expect(part.existsSync(), isFalse);
    },
  );

  group('the desk asks discovery only for a local ComfyUI', () {
    Future<Map<String, String>> found(String root, int port) async => {
      'checkpoints': p.join(bigDrive, 'checkpoints'),
    };

    test('a local ComfyUI gets its kinds', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await studioModelTypeFolders('comfyui', models, discover: found), {
        'checkpoints': p.join(bigDrive, 'checkpoints'),
      });
    });

    test('another computer, another backend, or no folder gets none', () async {
      SharedPreferences.setMockInitialValues({
        'comfy_ui_url': 'http://192.0.2.4:8188',
      });
      expect(
        await studioModelTypeFolders('comfyui', models, discover: found),
        isEmpty,
      );
      SharedPreferences.setMockInitialValues({});
      expect(
        await studioModelTypeFolders('a1111', models, discover: found),
        isEmpty,
      );
      expect(
        await studioModelTypeFolders('comfyui', null, discover: found),
        isEmpty,
      );
    });
  });
}
