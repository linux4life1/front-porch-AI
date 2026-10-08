// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Which measured preset auto mode runs for a model (the maintainer's ruling,
// 2026-10-06): the one the Local model card's speed test saved for it, on
// this card through this backend. A preset measured elsewhere, one the editor
// timed (the user's own), and one that loads another model are not used.
// Picking the model again keeps auto mode for the speed test's own preset;
// any other linked preset is picked as before. The presets are written by the
// app's own writer, as the test saves them.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/services/storage_service.dart';

import '../kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

const _card = 'NVIDIA GeForce RTX 4090';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;
  late String model;

  setUp(() async {
    // A folder of its own for each case: a preset saved under the test's own
    // name would otherwise be found by the next case.
    setupPathProviderMock();
    storage = await createStorageService();
    await storage.binDir.create(recursive: true);
    model = p.join(storage.binDir.path, '..', 'Qwen3-14B-Q4_K_M.gguf');
    model = p.normalize(model);
    File(model).writeAsStringSync('GGUF');
  });

  /// A preset as the speed test saves it: a whole config with the measured
  /// settings and its stamp.
  Future<String> save(
    String name, {
    String card = _card,
    String backend = 'cuda',
    bool auto = true,
    String? forModel,
    bool link = true,
  }) async {
    final path = await KcppsLibrary(storage.binDir.path).write(
      name,
      kcppsMap(
        KoboldLaunchConfig(
          modelPath: forModel ?? model,
          batchSize: 2048,
          logicalBatchSize: kKoboldLogicalBatch,
          mmq: false,
          backend: KoboldGpuBackend.cuda,
          gpuId: 0,
          measured: KoboldMeasured(
            card: card,
            backend: backend,
            engine: '1.122.1',
            on: '2026-10-06',
            auto: auto,
          ),
        ).copyWith(useMmap: false),
      ),
    );
    if (link) await storage.presetSettings.setModelPreset(model, path);
    return path;
  }

  Future<KoboldKnobs?> knobs({String card = _card, String backend = 'cuda'}) =>
      koboldMeasuredKnobs(storage, model: model, card: card, backend: backend);

  group('auto mode runs', () {
    test("the speed test's preset for the model, measured here", () async {
      await save(koboldMeasuredPresetName(model, _card));
      final k = await knobs();
      expect(k, isNotNull);
      expect(k!.batch, 2048);
      expect(k.mmq, isFalse);
      expect(k.mmap, isFalse);
    });

    test('it under its own name when the link was cleared', () async {
      await save(koboldMeasuredPresetName(model, _card), link: false);
      expect(await knobs(), isNotNull);
    });

    test(
      'nothing measured on another card, or through another backend',
      () async {
        await save('Measured elsewhere', card: 'NVIDIA GeForce RTX 3060');
        expect(await knobs(), isNull);
        await save('Measured through Vulkan', backend: 'vulkan');
        expect(await knobs(), isNull);
      },
    );

    test('nothing from a preset the editor timed: it is the user\'s', () async {
      await save('My own', auto: false);
      expect(await knobs(), isNull);
    });

    test('nothing from a preset that loads another model', () async {
      await save(
        'Another model',
        forModel: p.join(storage.binDir.path, 'other.gguf'),
      );
      expect(await knobs(), isNull);
    });
  });

  group('picking the model again', () {
    test("keeps auto mode for the speed test's own preset", () async {
      await save(koboldMeasuredPresetName(model, _card));
      await storage.backendSettings.setActiveKcppsPath(null);
      await selectKoboldModel(storage, model);
      expect(storage.backendSettings.activeKcppsPath, isNull);
    });

    test('picks it in custom mode, as any linked preset', () async {
      final path = await save(koboldMeasuredPresetName(model, _card));
      final mine = await KcppsLibrary(
        storage.binDir.path,
      ).write('Mine', kcppsMap(KoboldLaunchConfig(modelPath: model)));
      await storage.backendSettings.setActiveKcppsPath(mine);
      await selectKoboldModel(storage, model);
      expect(storage.backendSettings.activeKcppsPath, path);
    });

    test('picks any other linked preset as before, in auto mode too', () async {
      final path = await save('My own', auto: false);
      await storage.backendSettings.setActiveKcppsPath(null);
      await selectKoboldModel(storage, model);
      expect(storage.backendSettings.activeKcppsPath, path);
    });
  });

  group('the words', () {
    test('the name says the model file and the card, never a setting; two '
        'quants of one model get two names', () {
      expect(
        koboldMeasuredPresetName('/m/Qwen3-14B-Q4_K_M.gguf', _card),
        'Qwen3-14B-Q4_K_M (measured on GeForce RTX 4090)',
      );
      expect(
        koboldMeasuredPresetName('/m/Qwen3-14B-Q5_K_M.gguf', _card),
        'Qwen3-14B-Q5_K_M (measured on GeForce RTX 4090)',
      );
      expect(
        koboldMeasuredPresetName('/m/Qwen3-14B-Q4_K_M.gguf', ''),
        'Qwen3-14B-Q4_K_M (measured on this computer)',
      );
      expect(
        koboldMeasuredPresetName('/m/a.gguf', 'Card: A/B'),
        isNot(matches(RegExp(r'[\\/:*?"<>|]'))),
      );
    });

    test("the editor's line about the batch", () {
      const here = KoboldLaunchConfig(
        batchSize: 1024,
        measured: KoboldMeasured(card: _card, backend: 'cuda'),
      );
      expect(
        koboldMeasuredWords(here, card: _card, backend: 'cuda'),
        'Batch 1,024, measured on this card.',
      );
      expect(
        koboldMeasuredWords(here, card: 'Another', backend: 'cuda'),
        'Not measured on this card yet.',
      );
      expect(
        koboldMeasuredWords(
          const KoboldLaunchConfig(),
          card: _card,
          backend: 'cuda',
        ),
        'Not measured on this card yet.',
      );
    });
  });
}
