// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The Local model card with "Set layers myself" on (Advanced settings). It
// used to say "Set up for this computer automatically" and judge speed and
// context sizes as if KoboldCpp fitted the model, while the launch put the
// user's layer count on the card: an expert with 10 of 33 layers there was
// told replies come quickly and a long chat works. Now the card's facts
// use the real settings (the layer count, the memory lock, the experts kept
// in system memory as the launch writes them), the speed comes from that
// fixed layer count, and the card says "Set up by hand in Advanced
// settings." with no layer numbers. The phone reads the same facts.
//
// Real model headers (Llama 3.1 8B) on two real cards' figures.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';

import '../../golden/support/fakes_storage.dart';

final _rtx4090 = HardwareInfo(
  gpuName: 'NVIDIA GeForce RTX 4090',
  vramMb: 24564,
  ramMb: 65536,
  vendor: 'Nvidia',
  hasCuda: true,
);

final _gtx1060 = HardwareInfo(
  gpuName: 'NVIDIA GeForce GTX 1060 6GB',
  vramMb: 6144,
  ramMb: 16384,
  vendor: 'Nvidia',
  hasCuda: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The header of [name] with the real file's size, as a launch reads it.
  ({GGUFModelInfo info, int bytes}) model(String name) {
    final fx = 'test/fixtures/gguf_headers/$name';
    final bytes =
        (jsonDecode(File('$fx.json').readAsStringSync())
                as Map)['fixture_file_bytes']
            as int;
    final header = GGUFFileReader.parseHeaderBytes(
      File('$fx.gguf').readAsBytesSync(),
    )!;
    return (
      info: GGUFParser.modelInfoFromHeader(header, fileSize: bytes)!,
      bytes: bytes,
    );
  }

  /// The card's facts with layers set by hand ([layers]) or not (null).
  Future<KoboldStatusFacts> facts(
    HardwareInfo hw,
    FreeMemoryMb free, {
    int? layers,
    String name = 'Llama-3.1-8B',
  }) async {
    final (:info, :bytes) = model(name);
    final storage = FakeStorageService();
    final b = storage.backendSettings;
    await b.setContextSize(16384);
    await b.setGpuLayersManual(layers != null);
    await b.setGpuLayers(layers ?? 0);
    return KoboldStatusFacts.of(
      storage: storage,
      hardware: hw,
      free: free,
      info: info,
      bytes: bytes,
      unified: false,
    )!;
  }

  test('layers set by hand: the card says so, with no layer numbers, and '
      'the speed of what really runs', () async {
    const free = (graphics: 23000, system: 60000);
    final auto = await facts(_rtx4090, free);
    final byHand = await facts(_rtx4090, free, layers: 10);

    expect(
      auto.lines.first,
      'Set up for this computer automatically. The whole model fits on your '
      'graphics card, so replies come quickly.',
    );
    expect(
      byHand.lines.first,
      'Set up by hand in Advanced settings. Much of the model runs from '
      'system memory, so replies come slowly.',
    );
    expect(byHand.lines.first, isNot(matches(RegExp(r'\d'))));
  });

  test('the context verdicts are for the layer count set by hand', () async {
    const free = (graphics: 23000, system: 60000);
    final auto = await facts(_rtx4090, free);
    final byHand = await facts(_rtx4090, free, layers: 10);

    // Fitted by KoboldCpp the whole model is on the card: 128k works.
    expect(auto.verdicts[131072]!.outcome, KoboldContextOutcome.slower);
    expect(auto.largestGood, 131072);
    // With 10 layers on the card, every reply reads system memory.
    expect(byHand.verdicts[131072]!.outcome, KoboldContextOutcome.tooBig);
    expect(byHand.verdicts[131072]!.verySlow, isTrue);
    expect(byHand.largestGood, 65536);
  });

  test(
    'every layer on a 6 GB card by hand: it does not fit, the size in '
    'use included, since KoboldCpp does not fit layers set by hand',
    () async {
      const free = (graphics: 5222, system: 11063);
      final auto = await facts(_gtx1060, free);
      final byHand = await facts(_gtx1060, free, layers: 999);

      expect(auto.verdicts[16384]!.outcome, KoboldContextOutcome.likeNow);
      expect(
        byHand.lines.first,
        'Set up by hand in Advanced settings. As set, it does not fit on your '
        'graphics card, so it may not load.',
      );
      final now = byHand.verdicts[16384]!;
      expect(now.outcome, KoboldContextOutcome.tooBig);
      expect(now.outOfMemory, isTrue);
      expect(byHand.largestGood, isNull);
    },
  );

  test('a mixture-of-experts model by hand keeps its experts in system '
      'memory, as the launch writes it', () async {
    const free = (graphics: 23000, system: 60000);
    const moe = 'Qwen3-30B-A3B';
    final auto = await facts(_rtx4090, free, name: moe);
    final byHand = await facts(_rtx4090, free, layers: 999, name: moe);

    expect(auto.lines.first, endsWith('so replies come quickly.'));
    expect(
      byHand.lines.first,
      'Set up by hand in Advanced settings. Some of the model runs from '
      'system memory, so replies come at about reading pace.',
    );
  });
}
