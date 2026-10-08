// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// From image-studio-rewrite. Its City96 cases moved to
// comfy_city96_patch_test.dart and comfy_city96_gate_test.dart. Two cases that
// read the ComfyUI install and config of the machine running the tests are
// not copied: tests never touch a real install.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/civitai_download.dart';
import 'package:front_porch_ai/services/image/comfy_model_paths.dart';
import 'package:front_porch_ai/services/image/local_model_roots.dart';

void main() {
  test('Desktop yaml base path is the models folder', () {
    final blocks = parseComfyModelYaml('''
comfy.desktop_0:
  base_path: '/models/shared'
  is_default: true
  'checkpoints': 'checkpoints/'
  'controlnet': |-
    controlnet/
    t2i_adapter/
  'loras': 'loras/'
  'diffusion_models': 'diffusion_models/'
''');
    expect(blocks, hasLength(1));
    expect(blocks.single.isDefault, isTrue);
    expect(
      comfyModelsRoot(config: blocks.single, yamlDir: '/cfg', home: '/home'),
      '/models/shared',
    );
  });

  test('an install extra yaml keeps weights under base_path/models', () {
    final blocks = parseComfyModelYaml('''
comfyui_desktop:
  is_default: "true"
  base_path: /install/comfy
  checkpoints: models/checkpoints/
  diffusion_models: models/diffusion_models/
  loras: models/loras/
''');
    expect(blocks.single.isDefault, isTrue);
    expect(
      comfyModelsRoot(
        config: blocks.single,
        yamlDir: '/install/comfy',
        home: '/home',
      ),
      '/install/comfy/models',
    );
  });

  test('Windows Desktop and install paths are discovered', () {
    final win = comfyMachineLayout(
      os: ComfyHostOs.windows,
      home: r'C:\Users\me',
    );
    expect(
      win.desktopConfigDirs.single,
      r'C:\Users\me\AppData\Roaming\Comfy Desktop\instance-model-paths',
    );
    expect(
      win.installSearchRoots,
      contains(r'C:\Users\me\AppData\Local\Comfy-Desktop\ComfyUI-Installs'),
    );
    expect(
      win.installSearchRoots,
      contains(r'C:\Users\me\ComfyUI_windows_portable'),
    );
    final blocks = parseComfyModelYaml('''
desktop:
  base_path: 'C:\\ComfyUI-Shared\\models'
  is_default: true
  loras: loras/
''');
    expect(
      comfyModelsRoot(
        config: blocks.single,
        yamlDir: r'C:\cfg',
        home: r'C:\Users\me',
      ),
      r'C:\ComfyUI-Shared\models',
    );
  });

  test('macOS and Linux read Comfy Desktop data dirs', () {
    final mac = comfyMachineLayout(os: ComfyHostOs.mac, home: '/Users/me');
    expect(
      mac.desktopConfigDirs.single,
      '/Users/me/Library/Application Support/Comfy Desktop/instance-model-paths',
    );
    final linux = comfyMachineLayout(os: ComfyHostOs.linux, home: '/home/me');
    expect(
      linux.desktopConfigDirs,
      contains('/home/me/.local/share/comfyui-desktop-2/instance-model-paths'),
    );
    expect(
      linux.desktopConfigDirs,
      contains('/home/me/.config/comfyui-desktop-2/instance-model-paths'),
    );
  });

  test('a Comfy command line names its port, yaml, and models directory', () {
    final desktop = comfyLaunchHints(
      'python main.py --listen 127.0.0.1 --port 8189 '
      '--extra-model-paths-config "/Users/me/Library/Application Support/Comfy Desktop/instance-model-paths/inst.yaml"',
      cwd: '/Users/me/ComfyUI',
    );
    expect(desktop.port, 8189);
    expect(
      desktop.extraYamls.single,
      '/Users/me/Library/Application Support/Comfy Desktop/instance-model-paths/inst.yaml',
    );
    expect(desktop.mainPyDir, '/Users/me/ComfyUI');

    final portable = comfyLaunchHints(
      r'C:\ComfyUI_windows_portable\python_embeded\python.exe -s ComfyUI\main.py --windows-standalone-build --models-directory D:\models',
      executable: r'C:\ComfyUI_windows_portable\python_embeded\python.exe',
    );
    expect(portable.port, 8188);
    expect(portable.modelsDirectory, r'D:\models');
    expect(portable.mainPyDir, r'C:\ComfyUI_windows_portable\ComfyUI');
  });

  test('the running server port wins over another Comfy', () async {
    final root = await Directory.systemTemp.createTemp('fpai-comfy-port');
    addTearDown(() => root.delete(recursive: true));
    final chosen = await _models(root, 'chosen');
    final other = await _models(root, 'other');
    final chosenYaml = File('${root.path}/chosen.yaml');
    final otherYaml = File('${root.path}/other.yaml');
    await chosenYaml.writeAsString('''
desk:
  is_default: true
  base_path: '${chosen.path}'
  loras: loras/
''');
    await otherYaml.writeAsString('''
desk:
  is_default: true
  base_path: '${other.path}'
  loras: loras/
''');
    final found = await discoverComfyModelsRoot(
      preferPort: 8189,
      layout: _layout(root.path),
      scanMachine: false,
      processes: [
        ComfyProcessSnapshot(
          command:
              'python main.py --port 8188 --extra-model-paths-config "${otherYaml.path}"',
          cwd: root.path,
        ),
        ComfyProcessSnapshot(
          command:
              'python main.py --port 8189 --extra-model-paths-config "${chosenYaml.path}"',
          cwd: root.path,
        ),
      ],
    );
    expect(found, chosen.path);
  });

  test('a yaml with weights beats an empty install models folder', () async {
    final root = await Directory.systemTemp.createTemp('fpai-comfy-yaml');
    addTearDown(() => root.delete(recursive: true));
    final shared = await _models(root, 'shared');
    final install = Directory('${root.path}/ComfyUI')..createSync();
    File('${install.path}/main.py').writeAsStringSync('# comfy\n');
    Directory(
      '${install.path}/models/diffusion_models',
    ).createSync(recursive: true);
    File(
      '${install.path}/models/diffusion_models/put_diffusion_model_files_here',
    ).writeAsStringSync('');
    File('${install.path}/extra_model_paths.yaml').writeAsStringSync('''
comfyui_desktop:
  is_default: "true"
  base_path: '${root.path}/shared'
  diffusion_models: diffusion_models/
  loras: loras/
''');
    final found = await discoverComfyModelsRoot(
      layout: _layout(root.path, installs: [install.path]),
      processes: const [],
      scanMachine: false,
    );
    expect(found, shared.path);
  });

  test(
    'a folder with weights beats an earlier empty one from a running Comfy',
    () async {
      final root = await Directory.systemTemp.createTemp('fpai-comfy-empty');
      addTearDown(() => root.delete(recursive: true));
      final shared = await _models(root, 'shared');
      final running = Directory('${root.path}/Running')..createSync();
      Directory('${running.path}/models/loras').createSync(recursive: true);
      final yaml = File('${root.path}/extra.yaml')
        ..writeAsStringSync("""
comfyui:
  base_path: '${shared.path}'
  loras: loras/
""");
      final found = await discoverComfyModelsRoot(
        layout: ComfyMachineLayout(
          os: ComfyHostOs.linux,
          home: root.path,
          desktopConfigDirs: const [],
          extraModelConfigFiles: [yaml.path],
          installSearchRoots: const [],
          webuiPackageRoots: const [],
        ),
        processes: [
          ComfyProcessSnapshot(
            command: 'python ${running.path}/main.py --port 8188',
            cwd: running.path,
          ),
        ],
        scanMachine: false,
      );
      expect(found, shared.path);
    },
  );

  test('Automatic1111 in the home directory is the webui root', () async {
    final home = await Directory.systemTemp.createTemp('fpai-a1111');
    addTearDown(() => home.delete(recursive: true));
    final lora = Directory('${home.path}/stable-diffusion-webui/models/Lora')
      ..createSync(recursive: true);
    expect(lora.existsSync(), isTrue);
    expect(
      await discoverAutomatic1111Root(
        home: home.path,
        packageRoots: const [],
        processes: const [],
        scanMachine: false,
      ),
      '${home.path}/stable-diffusion-webui',
    );
  });

  test('LoRAs and Qwen weights use Comfy subfolders', () {
    expect(
      civitaiSlotFolder(
        fromLoraSheet: true,
        civitaiType: 'LORA',
        filename: 'clothes.safetensors',
      ),
      'loras',
    );
    expect(
      civitaiSlotFolder(
        fromLoraSheet: false,
        civitaiType: 'Checkpoint',
        filename: 'qwen-image-2.1.safetensors',
      ),
      'diffusion_models',
    );
    expect(
      civitaiSlotFolder(
        fromLoraSheet: false,
        civitaiType: 'Checkpoint',
        filename: 'juggernautXL.safetensors',
      ),
      'checkpoints',
    );
  });
}

Future<Directory> _models(Directory root, String name) async {
  final dir = Directory('${root.path}/$name/loras')
    ..createSync(recursive: true);
  File(
    '${dir.path}/clothes.safetensors',
  ).writeAsStringSync('not a real weight');
  return Directory('${root.path}/$name');
}

ComfyMachineLayout _layout(String home, {List<String>? installs}) {
  return ComfyMachineLayout(
    os: ComfyHostOs.mac,
    home: home,
    desktopConfigDirs: const [],
    extraModelConfigFiles: const [],
    installSearchRoots: installs ?? const [],
    webuiPackageRoots: const [],
  );
}
