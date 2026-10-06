// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// KoboldCpp 1.122 split the batch in two: `batchsize` is the logical batch
// and `ubatchsize` the physical one, the tokens computed at once, which sets
// the working memory (measured on 1.122.1: 2,048 with `ubatchsize` 512 runs
// n_batch 2048 and n_ubatch 512, with the compute buffer of 512). Before
// 1.122 `batchsize` was the physical batch and `ubatchsize` did not exist.
// The two fixtures are configs KoboldCpp 1.122.1 itself wrote
// (`--exportconfig`), one with `--ubatchsize 512` and one without.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/hardware_info.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/services/kobold_launch_args.dart';
import 'package:front_porch_ai/services/storage_service.dart';

import '../kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

const _split = 'test/fixtures/kcpps/koboldcpp_1_122_1_split_export.kcpps';
const _single = 'test/fixtures/kcpps/koboldcpp_1_122_1_single_export.kcpps';
const _old = 'test/fixtures/kcpps/koboldcpp_1_117_1_export.kcpps';

Map<String, dynamic> _json(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as Map).cast<String, dynamic>();

KoboldLaunchConfig _read(String text) => (readKcpps(text) as KcppsOk).config;

void main() {
  group('reading', () {
    test('a split export: the physical batch apart from the logical one', () {
      final c = _read(File(_split).readAsStringSync());
      expect(c.batchSize, 512);
      expect(c.logicalBatchSize, 2048);
    });

    test('an export that matches the batch (-1) is one batch', () {
      final c = _read(File(_single).readAsStringSync());
      expect(c.batchSize, 1024);
      expect(c.logicalBatchSize, isNull);
    });

    test('a file from before the split is one batch', () {
      final raw = _json(_old);
      final c = _read(jsonEncode(raw));
      expect(c.batchSize, raw['batchsize'] ?? raw['blasbatchsize']);
      expect(c.logicalBatchSize, isNull);
    });

    test('a physical batch above the logical one is held to it, as the '
        'engine holds it', () {
      final c = _read(jsonEncode({'batchsize': 512, 'ubatchsize': 1024}));
      expect(c.batchSize, 512);
    });

    test('ubatchsize is not a setting the app leaves unmanaged', () {
      final read = readKcpps(File(_split).readAsStringSync()) as KcppsOk;
      expect(read.unmanagedKeys, isNot(contains('ubatchsize')));
    });
  });

  group('writing', () {
    test('with a logical batch: both spellings of batchsize hold it and '
        'ubatchsize holds the physical one', () {
      final map = kcppsMap(
        const KoboldLaunchConfig(batchSize: 1024, logicalBatchSize: 2048),
      );
      expect(map['batchsize'], 2048);
      expect(map['blasbatchsize'], 2048);
      expect(map['ubatchsize'], 1024);
    });

    test('without one: the physical batch is the one field, and there is no '
        'ubatchsize', () {
      final map = kcppsMap(const KoboldLaunchConfig(batchSize: 1024));
      expect(map['batchsize'], 1024);
      expect(map['blasbatchsize'], 1024);
      expect(map.containsKey('ubatchsize'), isFalse);
    });

    test('a logical batch below the physical one never cuts it down', () {
      expect(kcppsBatchKeys(4096, logical: 2048), {
        'batchsize': 4096,
        'blasbatchsize': 4096,
        'ubatchsize': 4096,
      });
    });

    test('the split export survives a read and a write: both batches, and '
        'every setting as KoboldCpp wrote it', () {
      final raw = _json(_split);
      final read = readKcpps(jsonEncode(raw)) as KcppsOk;
      final again = kcppsMap(read.config);
      final back = _read(encodeKcpps(again));
      expect(back.batchSize, 512);
      expect(back.logicalBatchSize, 2048);
      expect(again['ubatchsize'], raw['ubatchsize']);
      expect(again['batchsize'], raw['batchsize']);
      expect(read.unmanagedKeys, isNotEmpty);
      for (final key in read.unmanagedKeys) {
        expect(jsonEncode(again[key]), jsonEncode(raw[key]), reason: key);
      }
    });
  });

  group("the editor's save", () {
    test('a new physical batch on a split preset keeps it split', () {
      final raw = _json(_split);
      final draft = KcppsDraft.fromConfig('Split', _read(jsonEncode(raw)));
      final before = draft.toMap();
      final after = draft.copyWith(batchSize: 1024).toMap();
      final out = kcppsMergeEdits(raw, before, after);
      expect(out['ubatchsize'], 1024);
      expect(out['batchsize'], 2048);
      expect(_read(jsonEncode(out)).batchSize, 1024);
    });

    test('a one-field preset stays one field', () {
      final raw = _json(_single);
      final draft = KcppsDraft.fromConfig('Single', _read(jsonEncode(raw)));
      final out = kcppsMergeEdits(
        raw,
        draft.toMap(),
        draft.copyWith(batchSize: 512).toMap(),
      );
      expect(out['batchsize'], 512);
      expect(_read(jsonEncode(out)).logicalBatchSize, isNull);
    });
  });

  group('auto mode at launch', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupPathProviderMock();

    late StorageService storage;
    late Directory dir;

    setUp(() async {
      storage = await createStorageService();
      dir = Directory.systemTemp.createTempSync('fpai two knob batch');
    });

    tearDown(() => dir.deleteSync(recursive: true));

    /// A model file as big as the real one (sparse: nothing is written).
    Future<String> model(String fixture) async {
      const fx = 'test/fixtures/gguf_headers';
      final side =
          jsonDecode(File('$fx/$fixture.json').readAsStringSync()) as Map;
      final file = File(p.join(dir.path, '$fixture.gguf'));
      final raf = await file.open(mode: FileMode.write);
      await raf.writeFrom(File('$fx/$fixture.gguf').readAsBytesSync());
      await raf.setPosition((side['fixture_file_bytes'] as int) - 1);
      await raf.writeByte(0);
      await raf.close();
      return file.path;
    }

    /// The engine's own record of its version, as the app keeps it.
    Future<String> engine(String? version) async {
      final exe = File(p.join(dir.path, 'koboldcpp'))
        ..writeAsBytesSync(List.filled(64, 1));
      if (version != null) {
        await KoboldBinaryVersion.write(dir.path, version: version, size: 64);
      }
      return exe.path;
    }

    Future<Map<String, dynamic>> launch(String? version) async {
      final args = await buildKoboldLaunchArgs(
        storage: storage,
        executablePath: await engine(version),
        modelPath: await model('Qwen3-14B'),
        kcppsPath: null,
        mmprojPath: null,
        port: 5001,
        gpuLayers: 0,
        contextSize: 16384,
        useVulkan: false,
        useCublas: true,
        useMetal: false,
        useRocm: false,
        hardware: HardwareInfo(
          gpuName: 'NVIDIA GeForce RTX 4080',
          vramMb: 16384,
          ramMb: 32768,
          vendor: 'Nvidia',
          hasCuda: true,
        ),
        free: (graphics: 16000, system: 28000),
      );
      return _json(args[args.indexOf('--config') + 1]);
    }

    test('an engine from 1.122 gets the logical 2,048 and the physical batch '
        'auto mode chose', () async {
      final config = await launch('1.122.1');
      expect(config['batchsize'], kKoboldLogicalBatch);
      expect(config['blasbatchsize'], kKoboldLogicalBatch);
      expect(config['ubatchsize'], 1024, reason: 'an NVIDIA card starts there');
      expect(_read(jsonEncode(config)).batchSize, 1024);
    });

    test(
      'an engine before 1.122 gets the physical batch as the one field',
      () async {
        final config = await launch('1.117.1');
        expect(config['batchsize'], 1024);
        expect(config.containsKey('ubatchsize'), isFalse);
      },
    );

    test('an engine whose version is not known gets the one field, which '
        'every engine reads the same way', () async {
      final config = await launch(null);
      expect(config['batchsize'], 1024);
      expect(config.containsKey('ubatchsize'), isFalse);
    });
  });
}
