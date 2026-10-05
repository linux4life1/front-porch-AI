// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Placing layers and experts, against what a real KoboldCpp did: 1.122.1 on
// Vulkan, an RX 6900 XT with 16 GB (the driver showed 36 MB in use with
// nothing loaded, so 16,332 free). Figures in MiB, as the engine printed
// them. Headers in test/fixtures/gguf_headers.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/utils/gguf_parser.dart';
import 'package:front_porch_ai/utils/gguf_reader.dart';
import 'package:front_porch_ai/utils/kobold_memory_rules.dart';
import 'package:front_porch_ai/utils/kobold_placement.dart';

const _dir = 'test/fixtures/gguf_headers';
const _free = 16332;

({GGUFModelInfo info, int bytes}) _model(String name) {
  final side = (jsonDecode(File('$_dir/$name.json').readAsStringSync()) as Map)
      .cast<String, dynamic>();
  final header = GGUFFileReader.parseHeaderBytes(
    File('$_dir/$name.gguf').readAsBytesSync(),
  )!;
  final bytes = side['fixture_file_bytes'] as int;
  return (
    info: GGUFParser.modelInfoFromHeader(header, fileSize: bytes)!,
    bytes: bytes,
  );
}

KoboldLoad _load(
  String name, {
  required int context,
  int? layers,
  int moeCpu = 0,
}) {
  final m = _model(name);
  return koboldLoad(
    info: m.info,
    fileSizeBytes: m.bytes,
    contextSize: context,
    batchSize: 512,
    cacheSizeFactor: 1.0,
    slidingWindowOn: false,
    flashAttention: true,
    backend: KoboldMemoryBackend.vulkan,
    gpuLayers: layers,
    moeCpuBlocks: moeCpu,
  );
}

KoboldLoad _fit(
  String name, {
  required int context,
  required int padding,
  double cache = 1.0,
}) {
  final m = _model(name);
  return koboldMostThatFits(
    info: m.info,
    fileSizeBytes: m.bytes,
    contextSize: context,
    batchSize: 512,
    cacheSizeFactor: cache,
    slidingWindowOn: false,
    flashAttention: true,
    backend: KoboldMemoryBackend.vulkan,
    budgetMb: _free - padding,
  );
}

void main() {
  group('a layer count puts the output and the LAST blocks on the card', () {
    test('Qwen3-14B, 20 of 41 layers at 64k', () {
      // Blocks 21 to 39 and the output layer. load_tensors: Vulkan0 model
      // buffer 4843.57, CPU 5178; cache Vulkan0 4883.00, CPU 5397.00.
      final l = _load('Qwen3-14B', context: 65536, layers: 20);
      expect(l.modelMb, 4843.57.ceil());
      expect(l.expertsMb, 0);
      expect(l.cacheMb, 4883);
      expect(l.ramCacheMb, 5397);
      expect(l.ramWeightsMb, closeTo(5178, 1));
    });

    test('with blocks in system memory the working buffer grows, and the '
        'estimate stays at or just above it', () {
      // 479.75 with 19 or 29 blocks on the card; 316.75 with all 40.
      final split = _load('Qwen3-14B', context: 65536, layers: 20);
      expect(split.computeMb, greaterThanOrEqualTo(480));
      expect(split.computeMb, lessThanOrEqualTo((479.75 * 1.05).ceil()));
      final whole = _load('Qwen3-14B', context: 16384);
      expect(whole.computeMb, lessThan(split.computeMb));
    });
  });

  test('moecpu keeps the experts of the first blocks in system memory', () {
    // Qwen3-30B-A3B, every block's experts there: 784.42 on the card.
    final all = _load('Qwen3-30B-A3B', context: 16384, moeCpu: 999);
    expect(all.modelMb, 784.42.ceil());
    expect(all.expertsMb, 0);
    expect(all.expertBlocksOnCard, 0);
    expect(all.cacheMb, 1560);

    // The first 40 of 48 (KoboldCpp: "the MoE weights of the first N
    // layers"): blocks 40 to 47 keep theirs on the card, 324.00 MiB for
    // block 40 and 373.50 for each of the other seven. The first eight
    // blocks would make 2889.00.
    final some = _load('Qwen3-30B-A3B', context: 16384, moeCpu: 40);
    expect(some.expertBlocksOnCard, 8);
    expect(some.modelMb, all.modelMb);
    expect(some.modelMb + some.expertsMb, (784.42 + 324.0 + 7 * 373.5).ceil());
    expect(some.ramWeightsMb, lessThan(all.ramWeightsMb));
  });

  group('the most that fits is what KoboldCpp\'s own fit chose', () {
    test('Qwen3-14B at 64k: 30 of 41 layers, at 32k: all of them', () {
      // Unforced fit, so KoboldCpp kept its own 1,024 spare.
      final at64k = _fit('Qwen3-14B', context: 65536, padding: 1024);
      expect(at64k.gpuLayers, 30);
      expect(at64k.modelMb, 7045.45.ceil());
      expect(at64k.cacheMb, 7453);
      expect(_fit('Qwen3-14B', context: 32768, padding: 1024).allOnCard, true);
    });

    test('Qwen3-30B-A3B: every layer on the card, and as many experts as '
        'fit, never more than the engine placed', () {
      // Model buffer on the card: 13347.42 with 1,024 spare (16k f16 and
      // 32k 8-bit), 14368.92 with 32 spare. The engine also splits the
      // last block's experts; the estimate counts whole blocks, so it may
      // come out up to one block (373.5) lower.
      void check(KoboldLoad l, double engine) {
        expect(l.gpuLayers, l.layerCount);
        final onCard = l.modelMb + l.expertsMb;
        expect(onCard, lessThanOrEqualTo(engine.ceil()));
        expect(onCard, greaterThan(engine - 373.5));
      }

      check(_fit('Qwen3-30B-A3B', context: 16384, padding: 1024), 13347.42);
      check(
        _fit('Qwen3-30B-A3B', context: 32768, padding: 1024, cache: 0.53125),
        13347.42,
      );
      check(_fit('Qwen3-30B-A3B', context: 16384, padding: 32), 14368.92);
    });
  });
}
