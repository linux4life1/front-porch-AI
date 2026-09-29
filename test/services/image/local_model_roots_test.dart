import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/civitai_download.dart';
import 'package:front_porch_ai/services/image/comfy_gguf_city96.dart';
import 'package:front_porch_ai/services/image/comfy_model_paths.dart';
import 'package:front_porch_ai/services/image/local_model_roots.dart';
import 'package:path/path.dart' as p;

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

  test('stock City96 loader source gains the Qwen-Image path', () {
    final patched = patchCity96Loader(_kStockLoader);
    expect(patched.recognized, isTrue);
    expect(patched.changed, isTrue);
    expect(patched.source, contains('arch_str = "qwen_image"'));
    expect(patched.source, contains('def _qwen3vl_vision('));
    expect(patched.source, contains('arch == "qwen3vl"'));
    expect(patched.source, contains('model.visual.deepstack_merger_list'));
    final again = patchCity96Loader(patched.source);
    expect(again.changed, isFalse);
    expect(again.source, patched.source);
  });

  test('a CRLF City96 loader stays CRLF', () {
    final patched = patchCity96Loader(_kStockLoader.replaceAll('\n', '\r\n'));
    expect(patched.source, contains('\r\n'));
    expect(patched.source, isNot(contains('\r\r\n')));
    expect(patched.source, contains('arch == "qwen3vl"'));
  });

  test('Qwen GGUF writes the loader and asks for a restart', () async {
    final dir = await Directory.systemTemp.createTemp('fpai-gguf');
    addTearDown(() => dir.delete(recursive: true));
    final loader = File('${dir.path}/loader.py')
      ..writeAsStringSync(_kStockLoader);
    final quiet = await ensureCity96QwenImage(
      comfyUrl: 'http://127.0.0.1:8188',
      filenames: const ['qwen-image-2.1-Q2_K.gguf'],
      loaders: [loader],
      serverRunning: false,
    );
    expect(quiet.message, isNull);
    expect(quiet.wrote, isTrue);
    expect(loader.readAsStringSync(), contains('arch_str = "qwen_image"'));

    final fresh = File('${dir.path}/loader2.py')
      ..writeAsStringSync(_kStockLoader);
    final restart = await ensureCity96QwenImage(
      comfyUrl: 'http://127.0.0.1:8189',
      filenames: const ['Qwen3-VL-8B-Instruct-Q2_K.gguf'],
      loaders: [fresh],
      serverRunning: true,
    );
    expect(restart.wrote, isTrue);
    expect(restart.message, contains('Restart ComfyUI'));

    final remote = File('${dir.path}/loader3.py')
      ..writeAsStringSync(_kStockLoader);
    final away = await ensureCity96QwenImage(
      comfyUrl: 'http://203.0.113.9:8188',
      filenames: const ['qwen-image.gguf'],
      loaders: [remote],
      serverRunning: true,
    );
    expect(away.message, contains('another computer'));
    expect(remote.readAsStringSync(), _kStockLoader);

    final skipped = await ensureCity96QwenImage(
      comfyUrl: 'http://127.0.0.1:8188',
      filenames: const ['flux1-schnell-Q2_K.gguf'],
      loaders: [remote],
      serverRunning: true,
    );
    expect(skipped.message, isNull);
    expect(skipped.wrote, isFalse);
  });

  test(
    'an installed City96 loader is left unchanged when it already reads Qwen-Image',
    () async {
      final home =
          Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (home == null || home.isEmpty) return;
      final loader = File(
        p.join(
          home,
          'ComfyUI-Installs',
          'ComfyUI',
          'ComfyUI',
          'custom_nodes',
          'ComfyUI-GGUF',
          'loader.py',
        ),
      );
      if (!await loader.exists()) return;
      final original = await loader.readAsString();
      final patch = patchCity96Loader(original);
      expect(patch.recognized, isTrue);
      expect(patch.changed, isFalse);
      expect(patch.source, original);
    },
  );

  test(
    'this computer uses its Comfy model folder when one is configured',
    () async {
      final layout = currentComfyMachineLayout();
      final configured = layout.desktopConfigDirs.any(
        (dir) => Directory(dir).existsSync(),
      );
      if (!configured) return;
      final root = await discoverComfyModelsRoot();
      expect(root, isNotNull);
      final loras = Directory(p.join(root!, 'loras'));
      final diffusion = Directory(p.join(root, 'diffusion_models'));
      expect(loras.existsSync() || diffusion.existsSync(), isTrue);
    },
  );
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

const _kStockLoader = '''
def gguf_sd_loader(path, handle_prefix="model.diffusion_model.", is_text_model=False):
        compat = "sd.cpp" if arch_str is None else arch_str
        # import here to avoid changes to convert.py breaking regular models
        from .tools.convert import detect_arch
        try:
            arch_str = detect_arch(set(val[0] for val in tensors)).arch
        except Exception as e:
            raise ValueError(f"This model is not currently supported - ({e})")
    elif arch_str not in TXT_ARCH_LIST and is_text_model:
        pass

def gguf_clip_loader(path):
        if arch == "qwen2vl":
            vsd = gguf_mmproj_loader(path)
            sd.update(vsd)
    else:
        pass
    return sd
''';
