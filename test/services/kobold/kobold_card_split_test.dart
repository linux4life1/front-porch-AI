// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A preset that spreads the model over several graphics cards keeps
// working, says so in plain words, and the editor's estimate counts every
// card it uses. There is no control to make a split: no machine here has
// two cards to test one on.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/kcpps_editor/kcpps_editor_controller.dart';
import 'package:front_porch_ai/utils/gguf_parser.dart';

import '../../golden/support/fakes_services.dart';
import '../../golden/support/fakes_storage.dart';

KoboldLaunchConfig _read(Map<String, Object?> map) =>
    (readKcpps(jsonEncode(map)) as KcppsOk).config;

class _Storage extends FakeStorageService {
  _Storage(this._bin);
  final Directory _bin;

  @override
  Directory get binDir => _bin;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('nvidia-smi lists the cards; detection counts them', () {
    final hw = HardwareService();
    addTearDown(hw.dispose);
    final two = hw.debugParseNvidiaSmi(
      'NVIDIA GeForce RTX 3090, 24576\nNVIDIA GeForce RTX 3060, 12288\n',
    );
    expect(two.cards, 2);
    expect(two.vramMb, 24576);
    expect(two.smallestMb, 12288);
    expect(
      hw.debugParseNvidiaSmi('NVIDIA GeForce GTX 1060 6GB, 6144').cards,
      1,
    );
  });

  test('the card count is kept with the rest of the hardware, and an older '
      'record is one card', () {
    final info = HardwareInfo(
      gpuName: 'NVIDIA GeForce RTX 3090',
      vramMb: 24576,
      ramMb: 65536,
      vendor: 'Nvidia',
      cardCount: 2,
    );
    expect(HardwareInfo.fromJson(info.toJson())!.cardCount, 2);
    expect(
      HardwareInfo.fromJson({'gpuName': 'x', 'vramMb': 8192})!.cardCount,
      1,
    );
  });

  test('every Vulkan card a preset names is kept', () {
    final c = _read({
      'usevulkan': [0, 1],
      'tensor_split': [3, 1],
    });
    expect(c.gpuId, 0);
    expect(c.moreGpuIds, [1]);
    expect(kcppsMap(c)['usevulkan'], [0, 1]);
    // The editor's form writes the same, so a save leaves the cards alone.
    final form = KcppsDraft.fromConfig('Two', c).toMap();
    expect(form['usevulkan'], [0, 1]);
  });

  test('in plain words', () {
    final vulkan = _read({
      'model_param': '/m/Big-70B-Q4_K_M.gguf',
      'usevulkan': [0, 1],
      'tensor_split': [3, 1],
    });
    expect(
      kcppsPlainWords(vulkan),
      contains('Spread over graphics cards 0 and 1, split 3 to 1.'),
    );
    final cudaAll = _read({
      'model_param': '/m/Big-70B-Q4_K_M.gguf',
      'usecuda': ['normal'],
    });
    expect(
      kcppsPlainWords(cudaAll, machineCards: 2),
      contains('Spread over all 2 graphics cards.'),
    );
    expect(kcppsPlainWords(cudaAll), isNot(contains('Spread over')));
    final one = _read({
      'model_param': '/m/Big-70B-Q4_K_M.gguf',
      'usecuda': ['normal', '0'],
    });
    expect(kcppsPlainWords(one, machineCards: 2), isNot(contains('Spread')));
  });

  test("the editor's estimate counts both cards, and working memory on "
      'each', () async {
    final bin = await Directory.systemTemp.createTemp('fpai card split');
    addTearDown(() => bin.delete(recursive: true));
    final info = await GGUFParser.getModelArchitectureInfo(
      'test/fixtures/gguf_headers/Qwen3-14B.gguf',
    );
    final c = KcppsEditorController(
      storage: _Storage(bin),
      hardware: FakeHardwareService(
        hardwareInfo: HardwareInfo(
          gpuName: 'AMD Radeon RX 6800',
          vramMb: 16384,
          ramMb: 65536,
          vendor: 'AMD',
          cardCount: 2,
        ),
      ),
      kobold: FakeKoboldService(),
      readFree: () async => (graphics: 15000, system: 60000),
      readModel: (_) async => (info: info, bytes: 9000000000),
      unified: false,
      threads: () async => 8,
    );
    addTearDown(c.dispose);
    await c.init();
    final file = File(p.join(bin.path, 'Two cards.kcpps'))
      ..writeAsStringSync(
        jsonEncode({
          'model_param': '/m/Qwen3-14B.gguf',
          'usevulkan': [0, 1],
          'contextsize': 16384,
        }),
      );
    await c.select(file.path);

    expect(c.cards, 2);
    expect(c.machine!.totalGraphicsMb, 2 * 16384);
    expect(c.machine!.freeGraphicsMb, 15000 + 16384 - 512);
    final fit = c.fit!;
    expect(fit.extraCardMb, fit.load().computeMb);
    expect(c.freeLine, '32 GB on 2 cards');
  });

  test('mixed cards: each card past the first counts as the smallest, so '
      'the estimate never looks bigger', () async {
    final bin = await Directory.systemTemp.createTemp('fpai card mixed');
    addTearDown(() => bin.delete(recursive: true));
    final info = await GGUFParser.getModelArchitectureInfo(
      'test/fixtures/gguf_headers/Qwen3-14B.gguf',
    );
    final c = KcppsEditorController(
      storage: _Storage(bin),
      hardware: FakeHardwareService(
        hardwareInfo: HardwareInfo(
          gpuName: 'NVIDIA GeForce RTX 3090',
          vramMb: 24576,
          ramMb: 65536,
          vendor: 'Nvidia',
          hasCuda: true,
          cardCount: 2,
          smallestCardMb: 12288,
        ),
      ),
      kobold: FakeKoboldService(),
      readFree: () async => (graphics: 23000, system: 60000),
      readModel: (_) async => (info: info, bytes: 9000000000),
      unified: false,
      threads: () async => 8,
    );
    addTearDown(c.dispose);
    await c.init();
    final file = File(p.join(bin.path, 'Every card.kcpps'))
      ..writeAsStringSync(
        jsonEncode({
          'model_param': '/m/Qwen3-14B.gguf',
          'usecuda': ['normal'],
          'contextsize': 16384,
        }),
      );
    await c.select(file.path);

    expect(c.cards, 2);
    expect(c.machine!.totalGraphicsMb, 24576 + 12288);
    expect(c.machine!.freeGraphicsMb, 23000 + 12288 - 512);
  });
}
