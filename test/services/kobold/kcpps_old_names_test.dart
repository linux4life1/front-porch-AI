// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A preset saved by an older KoboldCpp names some settings the way KoboldCpp
// once did (`usecublas`, `blasbatchsize`, `flashattention`, `useswa`, and a
// few for the CPU, the AI Horde and image generation). KoboldCpp turns an old
// name into its current setting when it STARTS, and only when the current
// name is missing (`convert_invalid_args`, 1.122.1). A live reload fills in
// every missing setting from the running engine first, so the old name is not
// turned into anything and its setting is dropped without a word: the preset
// runs one way after Start and another after the first swap.
//
// So such a preset is refused wherever a preset reaches the engine, in plain
// words with the fix (open it in the preset editor and press Save, which
// writes the current names), exactly as a preset that would run a program is
// (kcpps_risky_preset_test). A file that also has the current name is not
// refused: KoboldCpp reads the current name and leaves the old one alone. The
// app's own writer writes both spellings of the card and the batch, and
// KoboldCpp's own export carries both names of everything.
//
// Every case here is a real file. Nothing starts an engine: the real service
// is asked to start and stops before it spawns anything.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/services/kobold_admin_swap.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:path/path.dart' as p;

import '../kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

const _fixture = 'test/fixtures/kcpps/koboldcpp_1_117_1_export.kcpps';

/// Every old name the refusal can name, in KoboldCpp's order.
const _allOld = [
  'usecublas',
  'blasbatchsize',
  'sdconfig',
  'hordeconfig',
  'noblas',
  'sdnotile',
  'sdclipl',
  'sdclipg',
  'sdgendefaults',
  'flashattention',
  'useswa',
  'sdclipgpu',
  'sdvaecpu',
];

typedef _Old = ({String why, Map<String, dynamic> preset, List<String> names});

final List<_Old> _refused = [
  (
    why: 'the card under its old name',
    preset: {
      'usecublas': ['normal', '1'],
    },
    names: ['usecublas'],
  ),
  (
    why: 'the batch under its old name',
    preset: {'blasbatchsize': 1024},
    names: ['blasbatchsize'],
  ),
  (
    why: 'flash attention off under its old name',
    preset: {'flashattention': false},
    names: ['flashattention'],
  ),
  // KoboldCpp turns any value of these into the current setting.
  (
    why: 'flash attention on under its old name',
    preset: {'flashattention': true},
    names: ['flashattention'],
  ),
  (
    why: 'sliding window off under its old name',
    preset: {'useswa': false},
    names: ['useswa'],
  ),
  (
    why: 'sliding window on under its old name, with fast forward off',
    preset: {'useswa': true, 'nofastforward': true},
    names: ['useswa'],
  ),
  (
    why: 'the processor only, under its old name',
    preset: {'noblas': true},
    names: ['noblas'],
  ),
  (
    why: 'an image model under the old combined setting',
    preset: {
      'sdconfig': ['sd.safetensors', 'clamped', '4', 'quant'],
    },
    names: ['sdconfig'],
  ),
  // A display name only: not a Horde key, so not refused as risky, but
  // still the old form.
  (
    why: 'the AI Horde display name under the old combined setting',
    preset: {
      'hordeconfig': ['My model', 120, 4096],
    },
    names: ['hordeconfig'],
  ),
  (
    why: 'no VAE tiling, under its old name',
    preset: {'sdnotile': true},
    names: ['sdnotile'],
  ),
  (
    why: 'the image settings KoboldCpp reads whatever they hold',
    preset: {
      'sdnotile': false,
      'sdclipl': '',
      'sdclipg': '',
      'sdgendefaults': false,
    },
    names: ['sdnotile', 'sdclipl', 'sdclipg', 'sdgendefaults'],
  ),
  (
    why: 'the first CLIP file under its old name',
    preset: {'sdclipl': 'clip_l.safetensors'},
    names: ['sdclipl'],
  ),
  (
    why: 'the second CLIP file under its old name',
    preset: {'sdclipg': 'clip_g.safetensors'},
    names: ['sdclipg'],
  ),
  (
    why: 'image generation defaults under their old name',
    preset: {'sdgendefaults': '{"width": 512}'},
    names: ['sdgendefaults'],
  ),
  (
    why: 'CLIP on the graphics card, under its old name',
    preset: {'sdclipgpu': true},
    names: ['sdclipgpu'],
  ),
  (
    why: 'the VAE on the processor, under its old name',
    preset: {'sdvaecpu': true},
    names: ['sdvaecpu'],
  ),
  // KoboldCpp counts a null device as missing.
  (
    why: 'an old CLIP setting beside a current device that says null',
    preset: {'sdclipgpu': false, 'sdclipdevice': null},
    names: ['sdclipgpu'],
  ),
  (
    why: 'old names among ordinary settings',
    preset: {
      'contextsize': 8192,
      'usecublas': ['normal', '0'],
      'blasbatchsize': 2048,
      'flashattention': false,
      'useswa': false,
      'gpulayers': 20,
    },
    names: ['usecublas', 'blasbatchsize', 'flashattention', 'useswa'],
  ),
  // The current name of ONE renamed setting does not cover another.
  (
    why: 'an old name beside the current name of a different setting',
    preset: {
      'usecublas': ['normal', '0'],
      'batchsize': 1024,
    },
    names: ['usecublas'],
  ),
];

typedef _Fine = ({String why, Map<String, dynamic> preset});

final List<_Fine> _fine = [
  (why: 'nothing old at all', preset: {'contextsize': 4096, 'noswa': true}),
  (
    why: 'the current names only',
    preset: {
      'usecuda': ['normal', '0'],
      'batchsize': 1024,
      'noflashattention': true,
      'noswa': false,
      'nofastforward': true,
      'usecpu': false,
      'sdtiledvae': 0,
      'sdclipdevice': -1,
    },
  ),
  (
    why: 'both spellings of the card and the batch, as the app writes them',
    preset: {
      'usecuda': ['normal', '1'],
      'usecublas': ['normal', '1'],
      'batchsize': 1536,
      'blasbatchsize': 1536,
    },
  ),
  (
    why: 'flash attention under both names',
    preset: {'flashattention': false, 'noflashattention': true},
  ),
  (
    why: 'sliding window under both names',
    preset: {'useswa': false, 'noswa': true},
  ),
  // KoboldCpp reads the current name when the key is there at all, even as
  // null, which is how a Vulkan export says it uses no CUDA.
  (
    why: 'an old card name beside a current one that says null',
    preset: {
      'usecublas': ['normal', '0'],
      'usecuda': null,
      'usevulkan': [0],
    },
  ),
  // KoboldCpp acts on these only when they are on.
  (
    why: 'old names KoboldCpp reads only when they are on, switched off',
    preset: {
      'usecublas': null,
      'blasbatchsize': 0,
      'noblas': false,
      'sdconfig': null,
      'hordeconfig': null,
    },
  ),
  (
    why: 'empty lists under the old names',
    preset: {
      'usecublas': <Object>[],
      'sdconfig': <Object>[],
      'hordeconfig': <Object>[],
    },
  ),
  (
    why: 'old Horde settings with no model name, which KoboldCpp skips',
    preset: {
      'hordeconfig': ['', 0, 0, '', ''],
    },
  ),
  (
    why: 'an old CLIP setting beside a current device',
    preset: {'sdclipgpu': true, 'sdclipdevice': 0},
  ),
  // The setting itself before 1.122.1: KoboldCpp 1.117.1 writes it alone.
  (
    why: 'the T5 file 1.117.1 still calls sdt5xxl',
    preset: {'sdt5xxl': 't5xxl.safetensors'},
  ),
];

/// [key] as a whole word: `sdclipg` is inside `sdclipgpu`.
Matcher _names(String key) =>
    matches(RegExp('(^|[^a-z0-9_])${RegExp.escape(key)}(\$|[^a-z0-9_])'));

/// The refusal: it says the preset is from an older KoboldCpp, names exactly
/// [names], and says what to do.
Matcher _refusalFor(List<String> names) => allOf([
  for (final old in _allOld)
    names.contains(old) ? _names(old) : isNot(_names(old)),
  contains('saved by an older KoboldCpp'),
  contains('updated once'),
  contains('KoboldCpp presets'),
  contains('press Save'),
  contains('pick another preset'),
]);

Map<String, dynamic> _launch(Map<String, dynamic> preset) =>
    kcppsPresetLaunchMap(preset, modelPath: '', mmprojPath: '');

/// The preset editor's Save on [raw] as it was opened, with nothing edited.
Map<String, dynamic> _save(Map<String, dynamic> raw) {
  final form = kcppsMap((readKcpps(jsonEncode(raw)) as KcppsOk).config);
  return kcppsMergeEdits(Map.of(raw), form, form);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  late StorageService storage;
  late KoboldService kobold;
  late Directory dir;
  late String engine;
  late String model;

  setUp(() async {
    storage = await createStorageService();
    kobold = KoboldService(storage);
    dir = Directory.systemTemp.createTempSync('fpai_old_names_');
    // Never created: nothing here gets as far as running it.
    engine = p.join(dir.path, 'koboldcpp');
    model = p.join(dir.path, 'model.gguf');
    File(model).writeAsBytesSync([...'GGUF'.codeUnits, 3, 0, 0, 0]);
    await storage.backendSettings.setLastUsedModelPath(model);
  });

  tearDown(() {
    kobold.dispose();
    final admin = koboldAdminDirFor(storage);
    if (FileSystemEntity.isFileSync(admin)) File(admin).deleteSync();
    dir.deleteSync(recursive: true);
  });

  /// [preset] written as a real preset file.
  String write(Map<String, dynamic> preset, [String name = 'Theirs']) => (File(
    p.join(dir.path, '$name.kcpps'),
  )..writeAsStringSync(jsonEncode(preset))).path;

  Future<String> activate(Map<String, dynamic> preset) async {
    final path = write(preset);
    await storage.backendSettings.setActiveKcppsPath(path);
    return path;
  }

  group('a preset with an old setting name and not its current one', () {
    for (final c in _refused) {
      test('${c.why}: the screens that start the engine are told, in plain '
          'words, from the file', () async {
        final problem = await koboldPresetProblem(write(c.preset));

        expect(problem, _refusalFor(c.names));
      });

      test('${c.why}: the launch map refuses it with the same words', () {
        expect(
          () => _launch(c.preset),
          throwsA(
            isA<KoboldPresetProblem>().having(
              (e) => e.message,
              'message',
              _refusalFor(c.names),
            ),
          ),
        );
      });
    }

    test(
      'Start is told before anything is stopped, in the same words',
      () async {
        await activate({'flashattention': false});

        expect(
          await koboldLaunchProblem(storage),
          _refusalFor(['flashattention']),
        );
      },
    );

    test('a real Start refuses it: nothing is staged for KoboldCpp and the '
        'next Start is not turned away', () async {
      await activate({
        'contextsize': 8192,
        'blasbatchsize': 1024,
        'flashattention': false,
      });

      final result = await kobold.launch(
        engine,
        pickedModel: model,
        port: 5999,
      );

      expect(result.started, isFalse);
      expect(result.message, _refusalFor(['blasbatchsize', 'flashattention']));
      expect(
        File(
          p.join(koboldAdminDirFor(storage), kStagedChatConfig),
        ).existsSync(),
        isFalse,
        reason: 'the file KoboldCpp would have read was never written',
      );
      expect(kobold.isStarting, isFalse);
    });

    test('a program-running preset that is also old-style is refused for '
        'that first: the more serious reason is the one said', () {
      final preset = {
        'mcpfile': 'https://example.com/servers.json',
        'usecublas': ['normal', '0'],
      };

      expect(
        () => _launch(preset),
        throwsA(
          isA<KoboldPresetProblem>().having(
            (e) => e.message,
            'message',
            allOf(contains('mcpfile'), isNot(contains('usecublas'))),
          ),
        ),
      );
    });
  });

  group('everything else launches as written', () {
    for (final c in _fine) {
      test('${c.why}: passes the screens and the launch map', () async {
        expect(await koboldPresetProblem(write(c.preset)), isNull);
        expect(_launch(c.preset)['jinja'], isTrue);
      });
    }

    test('a preset the app wrote itself passes, with the card and the batch '
        'under both names', () async {
      for (final config in [
        const KoboldLaunchConfig(
          backend: KoboldGpuBackend.cuda,
          gpuId: 1,
          batchSize: 1536,
          flashAttention: false,
          contextMode: ContextManagementMode.slidingWindowAttention,
        ),
        const KoboldLaunchConfig(backend: KoboldGpuBackend.vulkan, gpuId: 0),
        const KoboldLaunchConfig(),
      ]) {
        final written = kcppsMap(config);
        expect(written['blasbatchsize'], config.batchSize);

        expect(await koboldPresetProblem(write(written)), isNull);
        expect(() => _launch(written), returnsNormally);
      }
    });

    test(
      'a config saved by KoboldCpp 1.117.1 itself passes: its export '
      'carries every old name beside the current one, or switched off',
      () async {
        final text = File(_fixture).readAsStringSync();
        final raw = (readKcpps(text) as KcppsOk).raw;
        for (final old in [
          'flashattention',
          'useswa',
          'sdnotile',
          'sdgendefaults',
          'sdclipgpu',
          'sdvaecpu',
          'noblas',
          'hordeconfig',
          'sdconfig',
        ]) {
          expect(raw.containsKey(old), isTrue, reason: '$old is in the export');
        }

        File(p.join(dir.path, 'Exported.kcpps')).writeAsStringSync(text);

        expect(
          await koboldPresetProblem(p.join(dir.path, 'Exported.kcpps')),
          isNull,
        );
        expect(() => _launch(raw), returnsNormally);
      },
    );

    test('the same export with the current names taken out is refused: it '
        'is the current name that makes an old one harmless', () async {
      const current = [
        'noflashattention',
        'noswa',
        'sdtiledvae',
        'gendefaults',
        'sdclipdevice',
        'sdvaedevice',
      ];
      final raw = Map<String, dynamic>.of(
        (readKcpps(File(_fixture).readAsStringSync()) as KcppsOk).raw,
      )..removeWhere((k, _) => current.contains(k));

      expect(
        await koboldPresetProblem(write(raw)),
        _refusalFor([
          'sdnotile',
          'sdgendefaults',
          'flashattention',
          'useswa',
          'sdclipgpu',
          'sdvaecpu',
        ]),
      );
    });

    test('whatever an old setting holds, the check, the launch map and Save '
        'never throw, and after Save the file is no longer old', () async {
      const odd = <Object?>[
        null,
        true,
        false,
        0,
        7,
        2.5,
        '',
        'text',
        'abcdef',
        <Object?>[],
        [1, 'a', null, 2.5],
        ['x', '1', '2', 'quant', 'w'],
        <String, Object?>{},
        {'a': 1},
      ];
      for (final old in _allOld) {
        for (final value in odd) {
          final preset = {old: value};
          final why = jsonEncode(preset);
          expect(
            await koboldPresetProblem(write(preset)),
            anyOf(isNull, isA<String>()),
            reason: why,
          );
          try {
            _launch(preset);
          } on KoboldPresetProblem {
            // The typed refusal, and nothing else, may come out.
          }
          expect(
            await koboldPresetProblem(write(_save(preset))),
            anyOf(isNull, isNot(contains('saved by an older KoboldCpp'))),
            reason: why,
          );
        }
      }
    });
  });

  group('the preset editor', () {
    // An old-style file as KoboldCpp's launcher once wrote it.
    final oldFile = <String, dynamic>{
      'model_param': '/models/example.gguf',
      'contextsize': 8192,
      'usecublas': ['normal', '1'],
      'blasbatchsize': 2048,
      'flashattention': false,
      'useswa': false,
      'nofastforward': false,
      'noblas': false,
      'sdclipl': 'clip_l.safetensors',
    };
    const save = _save;

    test('reads the old names: the card, the batch, flash attention and '
        'sliding window are what the file says', () {
      final config = (readKcpps(jsonEncode(oldFile)) as KcppsOk).config;

      expect(config.backend, KoboldGpuBackend.cuda);
      expect(config.gpuId, 1);
      expect(config.batchSize, 2048);
      expect(config.flashAttention, isFalse);
      expect(
        config.contextMode,
        ContextManagementMode.fastForwardSmartCache,
        reason: '`useswa: false` is sliding window off',
      );
    });

    test('Save writes the current names, and what is written is no longer '
        'refused', () async {
      final saved = save(oldFile);

      expect(saved['usecuda'], ['normal', '1']);
      expect(saved['batchsize'], 2048);
      expect(saved['noflashattention'], isTrue);
      expect(saved['noswa'], isTrue);
      expect(saved['sdclip1'], 'clip_l.safetensors');
      for (final gone in ['flashattention', 'useswa', 'sdclipl']) {
        expect(saved.containsKey(gone), isFalse, reason: gone);
      }
      // Nothing else of the file moves. An old name KoboldCpp does not act
      // on (switched off) is left as it was.
      expect(saved['contextsize'], 8192);
      expect(saved['model_param'], '/models/example.gguf');
      expect(saved['noblas'], isFalse);
      expect(await koboldPresetProblem(write(saved)), isNull);
      expect(() => _launch(saved), returnsNormally);
    });

    test(
      'Save gives every old setting what KoboldCpp gives it at Start',
      () async {
        for (final (old, current)
            in <(Map<String, dynamic>, Map<String, dynamic>)>[
              (
                {
                  'usecublas': ['normal', '1'],
                },
                {
                  'usecuda': ['normal', '1'],
                  'usecublas': ['normal', '1'],
                },
              ),
              (
                {'blasbatchsize': 2048},
                {'batchsize': 2048, 'blasbatchsize': 2048},
              ),
              ({'flashattention': false}, {'noflashattention': true}),
              ({'flashattention': true}, {'noflashattention': false}),
              ({'useswa': true}, {'noswa': false}),
              ({'useswa': false}, {'noswa': true}),
              ({'noblas': true}, {'usecpu': true}),
              (
                {
                  'sdconfig': ['sd.safetensors', 'clamped', '4', 'quant'],
                },
                {
                  'sdmodel': 'sd.safetensors',
                  'sdclamped': 512,
                  'sdthreads': 4,
                  'sdquant': 2,
                },
              ),
              (
                {
                  'hordeconfig': ['My model', 120, 4096],
                },
                {
                  'hordemodelname': 'My model',
                  'hordegenlen': 120,
                  'hordemaxctx': 4096,
                },
              ),
              ({'sdnotile': true}, {'sdtiledvae': 0}),
              // Tiling as each engine has it by default: the setting is left out.
              ({'sdnotile': false}, <String, dynamic>{}),
              ({'sdclipl': 'l.safetensors'}, {'sdclip1': 'l.safetensors'}),
              ({'sdclipg': 'g.safetensors'}, {'sdclip2': 'g.safetensors'}),
              (
                {'sdgendefaults': '{"width": 512}'},
                {'gendefaults': '{"width": 512}'},
              ),
              ({'sdclipgpu': true}, {'sdclipdevice': -1}),
              ({'sdclipgpu': false}, {'sdclipdevice': -2}),
              ({'sdvaecpu': true}, {'sdvaedevice': -2}),
              ({'sdvaecpu': false}, {'sdvaedevice': -1}),
            ]) {
          final saved = save(old);

          expect(saved, current, reason: '$old');
          expect(
            await koboldPresetProblem(write(saved)),
            isNull,
            reason: '$old',
          );
        }
      },
    );

    test('Save of a real edit over an old-style file writes the current '
        'names too', () async {
      final raw = Map<String, dynamic>.of(oldFile);
      final before = kcppsMap((readKcpps(jsonEncode(raw)) as KcppsOk).config);
      final after = kcppsMap(
        (readKcpps(jsonEncode(raw)) as KcppsOk).config.copyWith(
          contextSize: 32768,
        ),
      );

      final saved = kcppsMergeEdits(raw, before, after);

      expect(saved['contextsize'], 32768);
      expect(await koboldPresetProblem(write(saved)), isNull);
    });

    test('Save of a file that is already current changes nothing', () {
      final raw = (readKcpps(File(_fixture).readAsStringSync()) as KcppsOk).raw;

      expect(save(raw), raw);
    });
  });
}
