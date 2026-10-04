// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Guards for the KoboldCpp launch builder.
//
// The app launches KoboldCpp one way: from a config it writes into the admin
// folder. The command line carries only the port and the admin folder, which
// KoboldCpp will not take from a config. Every rule about memory, the
// graphics card, the cache and the vision file is therefore a rule about what
// that config says, and that is what these cases read back.
//
// Rewritten 2026-10-03 with the launch rewrite (docs/design/
// kobold-launch-rewrite.md). The earlier version of this file asserted
// individual command-line flags (`--gpulayers 33`, `--usemlock`,
// `--blasbatchsize`, a one-setting batch file); those flags are no longer
// sent, on purpose, so those assertions became false. Each rule that still
// holds has a case here in its new form.
//
// 2026-10-03: two cases added (a preset is staged as it was written; a
// preset that leaves sliding window to KoboldCpp). No existing case changed.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/hardware_info.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/services/kobold_admin_swap.dart';
import 'package:front_porch_ai/services/kobold_launch_args.dart';
import 'package:front_porch_ai/services/storage_service.dart';

// The path_provider mock + in-memory StorageService factory.
import 'kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

final _nvidia = HardwareInfo(
  gpuName: 'RTX 3060',
  vramMb: 12288,
  ramMb: 32768,
  vendor: 'Nvidia',
  hasCuda: true,
);

/// The header of a model file. With [slidingWindow], its metadata says the
/// model has sliding window.
List<int> _gguf({bool slidingWindow = false}) {
  List<int> u32(int v) => Uint8List(4)..buffer.asUint32List()[0] = v;
  List<int> u64(int v) => Uint8List(8)..buffer.asUint64List()[0] = v;
  final meta = {
    'general.architecture': 'gemma3',
    'gemma3.block_count': '4',
    'gemma3.attention.head_count': '4',
    'gemma3.embedding_length': '64',
    // The key real model files use. An earlier version of this helper
    // wrote `gemma3.sliding_window`, which no model has; the app read that
    // same wrong key, so sliding window was never seen on a real model.
    if (slidingWindow) 'gemma3.attention.sliding_window': '1024',
  };
  return [
    ...utf8.encode('GGUF'),
    ...u32(3),
    ...u64(0),
    ...u64(meta.length),
    for (final e in meta.entries) ...[
      ...u64(utf8.encode(e.key).length),
      ...utf8.encode(e.key),
      ...u32(8), // a string value
      ...u64(utf8.encode(e.value).length),
      ...utf8.encode(e.value),
    ],
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  late StorageService storage;
  late Directory binDir;

  setUp(() async {
    storage = await createStorageService();
    binDir = Directory.systemTemp.createTempSync('fpai_kobold_bin_');
  });

  tearDown(() {
    if (binDir.existsSync()) binDir.deleteSync(recursive: true);
  });

  Future<List<String>> build({
    String modelPath = '/models/mini-magnum-12b.gguf',
    String? kcppsPath,
    String? mmprojPath,
    int port = 5001,
    int gpuLayers = 33,
    int contextSize = 8192,
    bool useVulkan = false,
    bool useCublas = false,
    bool useMetal = false,
    bool useRocm = false,
    HardwareInfo? hardware,
    Future<HardwareInfo?> Function()? awaitHardware,
    void Function(String note)? onNote,
  }) => buildKoboldLaunchArgs(
    storage: storage,
    executablePath: '${binDir.path}/koboldcpp',
    modelPath: modelPath,
    kcppsPath: kcppsPath,
    mmprojPath: mmprojPath,
    port: port,
    gpuLayers: gpuLayers,
    contextSize: contextSize,
    useVulkan: useVulkan,
    useCublas: useCublas,
    useMetal: useMetal,
    useRocm: useRocm,
    hardware: hardware,
    awaitHardware: awaitHardware,
    onNote: onNote,
  );

  /// The config the launch will run, read back from where it was staged.
  Map<String, dynamic> staged(List<String> args) =>
      (jsonDecode(File(args[args.indexOf('--config') + 1]).readAsStringSync())
              as Map)
          .cast<String, dynamic>();

  File preset(Map<String, dynamic> content) =>
      File('${binDir.path}/mine.kcpps')..writeAsStringSync(jsonEncode(content));

  test('the command line is the staged config, the port and the admin '
      'folder, and nothing else', () async {
    final args = await build(port: 5002);
    final adminDir = koboldAdminDirFor(storage);
    expect(args, [
      '--config',
      '$adminDir/$kStagedChatConfig',
      '--port',
      '5002',
      '--admin',
      '--admindir',
      adminDir,
    ]);
    expect(Directory(adminDir).existsSync(), isTrue);
  });

  test('the app\'s own settings carry the model and context, and leave '
      'memory placement to KoboldCpp', () async {
    final config = staged(await build());
    expect(config['model_param'], '/models/mini-magnum-12b.gguf');
    expect(config['contextsize'], 8192);
    // The caller passed 33, but nobody chose "set layers myself".
    expect(config['gpulayers'], -1);
    expect(config.containsKey('autofit'), isFalse);
    expect(config['usemmap'], isTrue);
    expect(config['usemlock'], isFalse);
  });

  test('a layer count is sent only when the user chose to set it', () async {
    await storage.backendSettings.setGpuLayersManual(true);
    expect(staged(await build(gpuLayers: 33))['gpulayers'], 33);
  });

  test(
    'the chat template is on for both the app settings and a preset',
    () async {
      expect(staged(await build())['jinja'], isTrue);
      final file = preset({'model_param': '/m/a.gguf', 'jinja': false});
      expect(
        staged(await build(modelPath: '', kcppsPath: file.path))['jinja'],
        isTrue,
      );
    },
  );

  test('a preset keeps its own settings, including ones the app does not '
      'manage', () async {
    final file = preset({
      'model_param': '/m/preset-model.gguf',
      'contextsize': 12288,
      'gpulayers': 20,
      'defaultgenamt': 999,
      'noswa': true,
    });
    await storage.backendSettings.setGpuLayersManual(false);
    final config = staged(
      await build(modelPath: '', kcppsPath: file.path, contextSize: 8192),
    );
    expect(config['model_param'], '/m/preset-model.gguf');
    expect(config['contextsize'], 12288);
    expect(config['gpulayers'], 20);
    expect(config['defaultgenamt'], 999);
    // The user's file is read, never edited.
    expect(jsonDecode(file.readAsStringSync())['jinja'], isNull);
  });

  test(
    'a preset with no model of its own gets the one the app picked',
    () async {
      final file = preset({'contextsize': 4096});
      final config = staged(
        await build(modelPath: '/models/picked.gguf', kcppsPath: file.path),
      );
      expect(config['model_param'], '/models/picked.gguf');
    },
  );

  test('a preset that cannot be read stops the launch with a plain '
      'message', () async {
    final file = File('${binDir.path}/broken.kcpps')
      ..writeAsStringSync('{not json');
    await expectLater(
      build(modelPath: '', kcppsPath: file.path),
      throwsA(
        isA<KoboldPresetProblem>().having(
          (e) => e.message,
          'message',
          allOf(contains('broken.kcpps'), contains('can\'t be read')),
        ),
      ),
    );
  });

  test('a preset is staged as it was written: the staged file equals the '
      'original apart from the few settings the app lays over it', () async {
    // What the app may differ in: the model it resolved, the chat template,
    // the vision file, and sliding window when the file has it on together
    // with fast forward.
    const overlay = {'model_param', 'jinja', 'mmproj', 'noswa'};
    final proj = File('${binDir.path}/proj.gguf')..writeAsStringSync('x');

    for (final written in <Map<String, dynamic>>[
      // CUDA with its options.
      {
        'usecuda': ['normal', '1', 'nommq', 'rowsplit'],
      },
      {
        'usecuda': ['lowvram', '0', 'mmq'],
      },
      // Two graphics cards with a split between them.
      {
        'usevulkan': [0, 1],
        'tensor_split': [1, 1],
      },
      // A layer count with the MoE experts of 12 layers on the CPU.
      {'gpulayers': 48, 'moecpu': 12},
      // Sliding window with fast forward off, and sizes past the range the
      // app's own settings offer.
      {
        'noswa': false,
        'nofastforward': true,
        'swapadding': 512,
        'smartcache': 40,
      },
      // No context size: KoboldCpp's default must stay KoboldCpp's.
      {'model_param': '/m/own.gguf', 'batchsize': 1536},
    ]) {
      final config = staged(
        await build(
          modelPath: '/models/picked.gguf',
          kcppsPath: preset(written).path,
          mmprojPath: proj.path,
          contextSize: 8192,
        ),
      );
      expect(
        {...config}..removeWhere((key, _) => overlay.contains(key)),
        {...written}..removeWhere((key, _) => overlay.contains(key)),
        reason: 'nothing dropped, changed or filled in for $written',
      );
      expect(config['model_param'], '/models/picked.gguf');
      expect(config['jinja'], isTrue);
      expect(config['mmproj'], proj.path);
      // The file's own answer on sliding window stands whenever it is not
      // "on, with fast forward on".
      expect(config['noswa'], written['noswa'], reason: '$written');
      expect(config.containsKey('contextsize'), isFalse, reason: '$written');
    }

    // The one pairing the app changes: on in the file, with fast forward on.
    final unsafe = staged(
      await build(
        modelPath: '',
        kcppsPath: preset({'noswa': false, 'smartcache': 40}).path,
      ),
    );
    expect(unsafe, {'noswa': true, 'smartcache': 40, 'jinja': true});
  });

  test('a preset that leaves sliding window to KoboldCpp is run as written, '
      'and the log says what that means for a model that has it', () async {
    final withSwa = File('${binDir.path}/swa.gguf')
      ..writeAsBytesSync(_gguf(slidingWindow: true));
    final without = File('${binDir.path}/plain.gguf')
      ..writeAsBytesSync(_gguf());
    final silent = preset({'contextsize': 4096});

    final notes = <String>[];
    final config = staged(
      await build(
        modelPath: withSwa.path,
        kcppsPath: silent.path,
        onNote: notes.add,
      ),
    );
    expect(config.containsKey('noswa'), isFalse, reason: 'nothing changed');
    expect(notes.single, contains('does not say how to handle sliding'));
    expect(notes.single, contains('"noswa": true'));

    // A model without sliding window: nothing to say.
    notes.clear();
    await build(
      modelPath: without.path,
      kcppsPath: silent.path,
      onNote: notes.add,
    );
    expect(notes, isEmpty);

    // A preset that settles it, or has fast forward off: nothing to say.
    for (final settled in [
      {'noswa': true},
      {'nofastforward': true},
    ]) {
      await build(
        modelPath: withSwa.path,
        kcppsPath: preset(settled).path,
        onNote: notes.add,
      );
      expect(notes, isEmpty, reason: '$settled');
    }
  });

  test('CUDA names the chosen card, as text', () async {
    await storage.backendSettings.setGpuId(1);
    final config = staged(await build(useCublas: true));
    expect(config['usecublas'], ['normal', '1']);
  });

  test('ROCm names the card and always switches flash attention off, even '
      'with a compressed cache', () async {
    await storage.backendSettings.setKvQuant(KvQuant.q8_0);
    final config = staged(await build(useRocm: true));
    expect(config['usecublas'], ['normal', '0']);
    expect(config['noflashattention'], isTrue);
    expect(config['quantkv'], 'q8_0');
  });

  test('Vulkan lets KoboldCpp pick the device', () async {
    expect(staged(await build(useVulkan: true))['usevulkan'], isEmpty);
  });

  test('flash attention follows the setting, and a compressed cache turns '
      'it on regardless', () async {
    expect(staged(await build(useCublas: true))['noflashattention'], isFalse);
    await storage.backendSettings.setFlashAttentionEnabled(false);
    expect(staged(await build(useCublas: true))['noflashattention'], isTrue);
    await storage.backendSettings.setKvQuant(KvQuant.q4_0);
    final config = staged(await build(useCublas: true));
    expect(config['noflashattention'], isFalse);
    expect(config['quantkv'], 'q4_0');
  });

  test('the older stored cache level still counts until a level is picked '
      'by name', () async {
    await storage.backendSettings.setKvQuantizationLevel(2);
    expect(staged(await build())['quantkv'], 'q4_0');
    await storage.backendSettings.setKvQuant(KvQuant.q5_1);
    expect(staged(await build())['quantkv'], 'q5_1');
  });

  test('any batch size rides in the config; no extra file is written beside '
      'the engine', () async {
    expect(staged(await build())['batchsize'], 512);
    await storage.backendSettings.setBlasBatchSize(8192);
    expect(staged(await build())['batchsize'], 8192);
    expect(
      File('${binDir.path}/fpai_batch_override.kcpps').existsSync(),
      isFalse,
    );
  });

  test('the memory lock is off by default, and stays off while KoboldCpp '
      'is fitting the model itself', () async {
    expect(staged(await build())['usemlock'], isFalse);
    await storage.backendSettings.setMlockEnabled(true);
    expect(staged(await build())['usemlock'], isFalse);
    await storage.backendSettings.setGpuLayersManual(true);
    expect(staged(await build())['usemlock'], isTrue);
  });

  test(
    'a missing vision file is dropped rather than stopping the launch',
    () async {
      final config = staged(await build(mmprojPath: '/nope/proj.gguf'));
      expect(config.containsKey('mmproj'), isFalse);
    },
  );

  test('a vision file that exists is written for the app settings and for '
      'a preset', () async {
    final proj = File('${binDir.path}/proj.gguf')..writeAsStringSync('x');
    expect(staged(await build(mmprojPath: proj.path))['mmproj'], proj.path);
    final file = preset({'model_param': '/m/a.gguf'});
    final config = staged(
      await build(modelPath: '', kcppsPath: file.path, mmprojPath: proj.path),
    );
    expect(config['mmproj'], proj.path);
  });

  test('with no backend ever chosen, the detected card is used instead of '
      'the CPU', () async {
    final config = staged(await build(hardware: _nvidia));
    expect(config['usecublas'], ['normal', '0']);
    // Nothing detected yet: no backend setting, as before.
    final blind = staged(await build());
    expect(blind.containsKey('usecublas'), isFalse);
    expect(blind.containsKey('usevulkan'), isFalse);
  }, skip: Platform.isMacOS ? 'Metal needs no backend setting' : false);

  test('an explicit "CPU only" choice is respected', () async {
    final b = storage.backendSettings;
    await b.setUseCublas(false);
    await b.setUseVulkan(false);
    await b.setUseMetal(false);
    await b.setUseRocm(false);
    final config = staged(await build(hardware: _nvidia));
    expect(config.containsKey('usecublas'), isFalse);
    expect(config.containsKey('usevulkan'), isFalse);
  });

  test(
    'sliding window is not applied to a model that does not have it',
    () async {
      await storage.backendSettings.setKoboldContextMode(
        ContextManagementMode.slidingWindowAttention,
      );
      // The model path does not exist, so nothing says it has sliding window.
      final config = staged(await build());
      expect(config['noswa'], isTrue);
      expect(config['nofastforward'], isFalse);
      expect(config['noshift'], isFalse);
    },
  );

  group('a first run, before the hardware is known', () {
    test('with no backend ever chosen, the launch waits for detection and '
        'uses the card it finds', () async {
      var asked = 0;
      final config = staged(
        await build(
          awaitHardware: () async {
            asked++;
            return _nvidia;
          },
        ),
      );
      expect(asked, 1);
      expect(config['usecuda'], ['normal', '0']);
    }, skip: Platform.isMacOS ? 'Metal needs no backend setting' : false);

    test('detection that finds nothing leaves the launch on the CPU', () async {
      final config = staged(await build(awaitHardware: () async => null));
      expect(config.containsKey('usecuda'), isFalse);
      expect(config.containsKey('usevulkan'), isFalse);
    });

    test('nothing is waited for when the card is already known, or when a '
        'backend was chosen', () async {
      var asked = 0;
      Future<HardwareInfo?> ask() async {
        asked++;
        return _nvidia;
      }

      await build(hardware: _nvidia, awaitHardware: ask);
      await build(useVulkan: true, awaitHardware: ask);
      expect(asked, 0);
    });
  });

  group('a preset that cannot be launched from', () {
    test('is explained in plain words, for the screen that starts the '
        'engine', () async {
      expect(await koboldPresetProblem(null), isNull);
      expect(
        await koboldPresetProblem(preset({'contextsize': 4096}).path),
        isNull,
      );

      final broken = File('${binDir.path}/broken.kcpps')
        ..writeAsStringSync('{not a config');
      final problem = await koboldPresetProblem(broken.path);
      expect(problem, contains('broken.kcpps'));
      expect(problem, contains('can\'t be read'));
      expect(problem, contains('Settings'));

      expect(
        await koboldPresetProblem('${binDir.path}/gone.kcpps'),
        contains('could not be opened'),
      );
    });
  });

  test(
    'what the reader changed or noticed in a preset goes to the log',
    () async {
      final notes = <String>[];
      await build(
        kcppsPath: preset({
          // As KoboldCpp's launcher saves it: sliding window left on with
          // fast forward, and a forced fit over a layer count.
          'noswa': false,
          'nofastforward': false,
          'autofit': true,
          'gpulayers': 30,
        }).path,
        onNote: notes.add,
      );
      expect(notes, hasLength(2));
      expect(notes.join(' '), contains('sliding window is switched off'));
      expect(notes.join(' '), contains('forces automatic fit'));
    },
  );
}
