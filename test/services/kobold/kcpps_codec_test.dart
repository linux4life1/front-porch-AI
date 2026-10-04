// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The `.kcpps` reader and writer against a config file written by
// KoboldCpp 1.117.1 itself (`--exportconfig`, model path replaced), and
// against the forms KoboldCpp's own source accepts.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';

const _fixture = 'test/fixtures/kcpps/koboldcpp_1_117_1_export.kcpps';

void main() {
  group('reading a config KoboldCpp wrote', () {
    late KcppsOk read;
    late Map<String, dynamic> original;

    setUp(() {
      final text = File(_fixture).readAsStringSync();
      original = (jsonDecode(text) as Map).cast<String, dynamic>();
      read = readKcpps(text) as KcppsOk;
    });

    test('the settings the app manages are understood', () {
      final c = read.config;
      expect(c.modelPath, '/models/example-model.gguf');
      expect(c.contextSize, 4096);
      expect(c.gpuLayers, 20);
      expect(c.threads, 6);
      expect(c.kvQuant, KvQuant.q8_0);
      expect(c.backend, KoboldGpuBackend.cuda);
      expect(c.gpuId, 1, reason: 'KoboldCpp stores the card as the text "1"');
      expect(c.smartCacheSlots, 3);
      expect(c.flashAttention, isTrue);
    });

    test('every setting the app does not manage survives a round trip', () {
      expect(read.unmanagedKeys.length, greaterThan(100));
      final back = kcppsMap(read.config);
      for (final key in read.unmanagedKeys) {
        expect(back[key], original[key], reason: key);
      }
      // KoboldCpp's forced automatic fit is left as the file had it.
      expect(back['autofit'], isFalse);
    });

    test('sliding window left on with fast forward is made safe, and the '
        'reader says so', () {
      // The export has noswa:false and nofastforward:false.
      expect(original['noswa'], isFalse);
      expect(original['nofastforward'], isFalse);
      expect(
        read.config.contextMode,
        ContextManagementMode.fastForwardSmartCache,
      );
      expect(read.notes.single, contains('was left on'));
      expect(kcppsMap(read.config)['noswa'], isTrue);
    });
  });

  test('sliding-window mode never has fast forward or context shift', () {
    final map = kcppsMap(
      const KoboldLaunchConfig(
        contextMode: ContextManagementMode.slidingWindowAttention,
        smartCacheSlots: 5,
      ),
    );
    expect(map['noswa'], isFalse);
    expect(map['nofastforward'], isTrue);
    expect(map['noshift'], isTrue);
    expect(map.containsKey('smartcache'), isFalse);

    // And a file in that shape reads back as sliding-window mode.
    final back = readKcpps(jsonEncode(map)) as KcppsOk;
    expect(
      back.config.contextMode,
      ContextManagementMode.slidingWindowAttention,
    );
    expect(back.notes, isEmpty);
  });

  test('fast-forward mode switches sliding window off', () {
    final map = kcppsMap(const KoboldLaunchConfig(smartCacheSlots: 5));
    expect(map['noswa'], isTrue);
    expect(map['nofastforward'], isFalse);
    expect(map['noshift'], isFalse);
    expect(map['smartcache'], 5);
  });

  test('the graphics card is written as text, and an old numeric id is '
      'still read', () {
    final map = kcppsMap(
      const KoboldLaunchConfig(backend: KoboldGpuBackend.cuda, gpuId: 1),
    );
    expect(map['usecuda'], ['normal', '1']);
    expect((map['usecuda'] as List)[1], isA<String>());

    // What this app's generator used to write: a number KoboldCpp ignores.
    final old = readKcpps('{"usecublas": ["normal", 0]}') as KcppsOk;
    expect(old.config.backend, KoboldGpuBackend.cuda);
    expect(old.config.gpuId, 0);
    expect(kcppsMap(old.config)['usecuda'], ['normal', '0']);
  });

  test('a renamed key is written under both names, so the setting holds on '
      'an old engine and across a live reload of a current one', () {
    final map = kcppsMap(
      const KoboldLaunchConfig(
        backend: KoboldGpuBackend.cuda,
        gpuId: 1,
        batchSize: 1536,
      ),
    );
    expect(map['usecuda'], ['normal', '1']);
    expect(map['usecublas'], map['usecuda']);
    expect(map['batchsize'], 1536);
    expect(map['blasbatchsize'], 1536);

    // `usehipblas` is a command-line alias, not a config key: a ROCm
    // preset that used it is read, and written back under the real names.
    final rocm = readKcpps('{"usehipblas": ["normal", "0"]}') as KcppsOk;
    final back = kcppsMap(rocm.config);
    expect(back['usecuda'], ['normal', '0']);
    expect(back.containsKey('usehipblas'), isFalse);

    // No card chosen: neither name is written, so nothing claims a GPU.
    final cpu = kcppsMap(const KoboldLaunchConfig());
    expect(cpu.containsKey('usecuda'), isFalse);
    expect(cpu.containsKey('usecublas'), isFalse);
  });

  test('a preset that does not mention sliding window says what current '
      'KoboldCpp would do with it', () {
    final read = readKcpps('{"contextsize": 4096}') as KcppsOk;
    expect(read.notes.single, contains('does not say'));
    expect(kcppsMap(read.config)['noswa'], isTrue);
    // One that settles it either way has nothing to say.
    expect((readKcpps('{"noswa": true}') as KcppsOk).notes, isEmpty);
  });

  test('a forced automatic fit that overrides the preset\'s own layer count '
      'or MoE setting is pointed out', () {
    String? note(String json) => (readKcpps(json) as KcppsOk).notes
        .where((n) => n.contains('automatic fit'))
        .firstOrNull;
    expect(
      note('{"noswa": true, "autofit": true, "gpulayers": 30}'),
      isNotNull,
    );
    expect(note('{"noswa": true, "autofit": true, "moecpu": 999}'), isNotNull);
    expect(note('{"noswa": true, "autofit": true, "gpulayers": -1}'), isNull);
    expect(note('{"noswa": true, "autofit": false, "gpulayers": 30}'), isNull);
  });

  test('Vulkan with no card named lets KoboldCpp choose', () {
    final auto = kcppsMap(
      const KoboldLaunchConfig(backend: KoboldGpuBackend.vulkan),
    );
    expect(auto['usevulkan'], isEmpty);
    final picked = kcppsMap(
      const KoboldLaunchConfig(backend: KoboldGpuBackend.vulkan, gpuId: 0),
    );
    expect(picked['usevulkan'], [0]);
  });

  test('all five cache types are written by name', () {
    expect(KvQuant.values.map((q) => q.wire), [
      'f16',
      'bf16',
      'q8_0',
      'q5_1',
      'q4_0',
    ]);
    for (final q in KvQuant.values) {
      expect(kcppsMap(KoboldLaunchConfig(kvQuant: q))['quantkv'], q.wire);
      expect(KvQuant.parse(q.wire), q);
    }
    // KoboldCpp's own legacy indexes: 0 f16, 1 q8_0, 2 q4_0, 3 bf16.
    expect(KvQuant.parse(1), KvQuant.q8_0);
    expect(KvQuant.parse('2'), KvQuant.q4_0);
    expect(KvQuant.parse('3'), KvQuant.bf16);
  });

  test('an engine older than 1.112 gets the index, not the name', () {
    final old = KoboldCapabilities.forVersion('1.111.2');
    expect(old.quantKvAsText, isFalse);
    final map = kcppsMap(
      const KoboldLaunchConfig(kvQuant: KvQuant.q8_0),
      caps: old,
    );
    expect(map['quantkv'], '1');
    expect(KoboldCapabilities.forVersion('1.117.1').quantKvAsText, isTrue);
    expect(KoboldCapabilities.forVersion('1.111.0').moeCpu, isFalse);
    expect(KoboldCapabilities.forVersion('1.111.1').moeCpu, isTrue);
    // No version file yet: the app downloads the newest engine.
    expect(KoboldCapabilities.forVersion(null).quantKvAsText, isTrue);
  });

  test('automatic layers by default, with no forced automatic fit', () {
    final map = kcppsMap(const KoboldLaunchConfig(modelPath: '/m/a.gguf'));
    expect(map['gpulayers'], -1);
    expect(map.containsKey('autofit'), isFalse);
    expect(map['usemmap'], isTrue);
    expect(map['usemlock'], isFalse);
    expect(map['jinja'], isTrue);
  });

  test('MoE experts stay in system memory only with a manual layer '
      'count', () {
    const moe = KoboldLaunchConfig(moeExpertsOnCpu: true);
    expect(kcppsMap(moe).containsKey('moecpu'), isFalse);
    expect(kcppsMap(moe.copyWith(gpuLayers: 30))['moecpu'], 999);
    final old = kcppsMap(
      moe.copyWith(gpuLayers: 30),
      caps: KoboldCapabilities.forVersion('1.110'),
    );
    expect(old.containsKey('moecpu'), isFalse);
  });

  test('the vision file travels in the preset', () {
    final map = kcppsMap(const KoboldLaunchConfig(mmprojPath: '/m/proj.gguf'));
    expect(map['mmproj'], '/m/proj.gguf');
    final back = readKcpps(jsonEncode(map)) as KcppsOk;
    expect(back.config.mmprojPath, '/m/proj.gguf');
  });

  test('a file that is not a config is reported as broken, not as empty', () {
    expect(readKcpps('{not json'), isA<KcppsBroken>());
    expect(readKcpps('[1, 2]'), isA<KcppsBroken>());
    expect((readKcpps('') as KcppsBroken).reason, contains('not valid'));
  });

  test('an older file that names the model under "model" is read', () {
    final read =
        readKcpps('{"model": ["/m/b.gguf"], "blasbatchsize": 1024}') as KcppsOk;
    expect(read.config.modelPath, '/m/b.gguf');
    expect(read.config.batchSize, 1024);
  });
}
