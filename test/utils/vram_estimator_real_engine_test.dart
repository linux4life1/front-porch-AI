// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The estimate against what a real KoboldCpp reported.
//
// The rule these cases hold the estimator to: be as close as the file
// allows, and never promise less memory than the engine really takes. So
// the parts the file gives exactly (the weights, the attention cache) must
// match the engine's own figures, and the part that cannot be known exactly
// (the compute buffer) must come out at or a little above them, never below.
//
// The figures are from real loads, with flash attention on:
//  - an RX 6900 XT (16 GB) on Linux with Vulkan, KoboldCpp 1.122.1, for
//    Qwen3-14B and the Qwen3-30B-A3B MoE;
//  - a GTX 1060 (6 GB) on Windows with CUDA, for the Qwen3.6-35B-A3B MoE.
// The model headers are in test/fixtures/gguf_headers (see its README).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/utils/gguf_parser.dart';
import 'package:front_porch_ai/utils/gguf_reader.dart';
import 'package:front_porch_ai/utils/vram_estimator.dart';

const _dir = 'test/fixtures/gguf_headers';

({GGUFModelInfo info, int fileBytes}) _model(String name) {
  final side = (jsonDecode(File('$_dir/$name.json').readAsStringSync()) as Map)
      .cast<String, dynamic>();
  final header = GGUFFileReader.parseHeaderBytes(
    File('$_dir/$name.gguf').readAsBytesSync(),
  )!;
  final fileBytes = side['fixture_file_bytes'] as int;
  return (
    info: GGUFParser.modelInfoFromHeader(header, fileSize: fileBytes)!,
    fileBytes: fileBytes,
  );
}

VramEstimateBreakdown _estimate(
  String name, {
  required int context,
  int batch = 512,
  String quant = 'f16',
  bool slidingWindowOn = false,
  bool expertsInSystemMemory = true,
}) {
  final m = _model(name);
  return VramEstimator.estimateFromArchitecture(
    modelInfo: m.info,
    fileSizeBytes: m.fileBytes,
    contextSize: context,
    batchSize: batch,
    kvQuant: quant,
    isSwa: slidingWindowOn,
    moeExpertsOnCpu: expertsInSystemMemory,
  );
}

/// The engine reports MiB to two decimals; the estimate is whole MiB,
/// rounded up.
Matcher _exactly(double engineMiB) => equals(engineMiB.ceil());

/// At or above what the engine reserved, and not more than a tenth over.
Matcher _atLeastButClose(double engineMiB) => allOf(
  greaterThanOrEqualTo(engineMiB.ceil()),
  lessThanOrEqualTo((engineMiB * 1.10).ceil()),
);

void main() {
  group('a dense model (Qwen3-14B Q5_K_M) on a 16 GB card', () {
    test('the weights on the card are what the engine put there', () {
      // load_tensors: Vulkan0 model buffer size = 9511.75 MiB; the input
      // embedding (510.04 MiB) stayed in system memory.
      expect(
        _estimate('Qwen3-14B', context: 16384).weightsMb,
        _exactly(9511.75),
      );
    });

    test('the attention cache matches at every context size and cache '
        'type that was loaded', () {
      // llama_kv_cache: Vulkan0 KV buffer size
      expect(_estimate('Qwen3-14B', context: 16384).kvCacheMb, _exactly(2600));
      expect(_estimate('Qwen3-14B', context: 32768).kvCacheMb, _exactly(5160));
      expect(_estimate('Qwen3-14B', context: 40960).kvCacheMb, _exactly(6440));
      expect(
        _estimate('Qwen3-14B', context: 65536, quant: 'q8_0').kvCacheMb,
        _exactly(5461.25),
      );
      expect(
        _estimate('Qwen3-14B', context: 65536, quant: 'q4_0').kvCacheMb,
        _exactly(2891.25),
      );
    });

    test('the compute buffer is never below what the engine reserved', () {
      // sched_reserve: Vulkan0 compute buffer size = 316.75 MiB
      expect(
        _estimate('Qwen3-14B', context: 16384).computeBufMb,
        _atLeastButClose(316.75),
      );
    });
  });

  group('a MoE model (Qwen3-30B-A3B Q4_K_M) on a 16 GB card', () {
    test('with the experts in system memory, the weights on the card are '
        'what the engine put there', () {
      // "Set layers myself" with every expert in system memory:
      // Vulkan0 model buffer size = 784.42 MiB.
      expect(
        _estimate('Qwen3-30B-A3B', context: 16384).weightsMb,
        _exactly(784.42),
      );
    });

    test('the attention cache matches', () {
      expect(
        _estimate('Qwen3-30B-A3B', context: 16384).kvCacheMb,
        _exactly(1560),
      );
      expect(
        _estimate('Qwen3-30B-A3B', context: 32768, quant: 'q8_0').kvCacheMb,
        _exactly(1644.75),
      );
      expect(
        _estimate('Qwen3-30B-A3B', context: 65536, quant: 'q4_0').kvCacheMb,
        _exactly(1734.75),
      );
    });

    test('the compute buffer is never below what the engine reserved', () {
      expect(
        _estimate('Qwen3-30B-A3B', context: 16384).computeBufMb,
        _atLeastButClose(300.75),
      );
    });
  });

  group('a hybrid MoE model (Qwen3.6-35B-A3B Q4_K_XL) on a 6 GB card', () {
    test('the weights that always sit on the card', () {
      // Everything except the expert weights and the input embedding.
      // (The engine then brought the experts of three blocks back onto the
      // card with the room that was left: 3523.60 MiB in all.)
      expect(
        _estimate('Qwen3.6-35B-A3B-Q4_K_XL', context: 16384).weightsMb,
        _exactly(2038.80),
      );
    });

    test('only one layer in four keeps a cache, and the recurrent layers '
        'keep a small fixed state beside it', () {
      // llama_kv_cache: CUDA0 KV buffer size = 325.00 MiB (16640 cells,
      // 10 layers); llama_memory_recurrent: CUDA0 RS buffer = 62.81 MiB.
      final info = _model('Qwen3.6-35B-A3B-Q4_K_XL').info;
      expect(info.kvLayers, hasLength(10));
      expect(info.recurrentStateBytes / (1024 * 1024), closeTo(62.81, 0.01));
      expect(
        _estimate('Qwen3.6-35B-A3B-Q4_K_XL', context: 16384).kvCacheMb,
        325 + 63,
      );
    });

    test('it has no sliding window, so that setting changes nothing', () {
      // The engine: "This model does not use SWA".
      final info = _model('Qwen3.6-35B-A3B-Q4_K_XL').info;
      expect(info.hasSlidingWindow, isFalse);
      expect(
        _estimate(
          'Qwen3.6-35B-A3B-Q4_K_XL',
          context: 16384,
          slidingWindowOn: true,
        ).kvCacheMb,
        _estimate('Qwen3.6-35B-A3B-Q4_K_XL', context: 16384).kvCacheMb,
      );
    });

    test('the compute buffer is never below what the engine reserved', () {
      // sched_reserve: CUDA0 compute buffer size = 1053.07 MiB at batch 1024
      expect(
        _estimate(
          'Qwen3.6-35B-A3B-Q4_K_XL',
          context: 16384,
          batch: 1024,
        ).computeBufMb,
        _atLeastButClose(1053.07),
      );
    });
  });
}
