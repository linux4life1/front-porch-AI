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
// The figures are from real loads:
//  - an RX 6900 XT (16 GB) on Linux, KoboldCpp 1.122.1 on Vulkan and the
//    1.121 ROCm build, for Qwen3-14B, the Qwen3-30B-A3B MoE and Gemma 4
//    12B, with flash attention on unless a case says otherwise;
//  - a GTX 1060 (6 GB) on Windows with CUDA, for the Qwen3.6-35B-A3B MoE.
// The model headers are in test/fixtures/gguf_headers (see its README).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/utils/utils.dart';

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
  KoboldMemoryBackend backend = KoboldMemoryBackend.vulkan,
  bool flashAttention = true,
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
    backend: backend,
    flashAttention: flashAttention,
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
          backend: KoboldMemoryBackend.cuda,
        ).computeBufMb,
        _atLeastButClose(1053.07),
      );
    });
  });

  group('working memory at larger batches, Vulkan', () {
    test('below 1 GiB of output scores it is the output part', () {
      // Qwen3-14B, batch 1536: 950.25 MiB, the output part exactly.
      expect(
        _estimate('Qwen3-14B', context: 16384, batch: 1536).computeBufMb,
        _atLeastButClose(950.25),
      );
    });

    test('from 1 GiB of output scores the output and the layers add up', () {
      expect(
        _estimate('Qwen3-14B', context: 16384, batch: 2048).computeBufMb,
        _atLeastButClose(1740.05),
      );
      expect(
        _estimate('Qwen3-30B-A3B', context: 16384, batch: 2048).computeBufMb,
        _atLeastButClose(1697.54),
      );
    });
  });

  group('flash attention off (the ROCm build, as the app launches it)', () {
    test('the working memory holds a layer\'s attention scores', () {
      expect(
        _estimate(
          'Qwen3-14B',
          context: 16384,
          backend: KoboldMemoryBackend.rocm,
          flashAttention: false,
        ).computeBufMb,
        _atLeastButClose(1376.51),
      );
      expect(
        _estimate(
          'Qwen3-30B-A3B',
          context: 16384,
          backend: KoboldMemoryBackend.rocm,
          flashAttention: false,
        ).computeBufMb,
        _atLeastButClose(1098.51),
      );
    });
  });

  group('Gemma 4 12B Q4_K_M (sliding window, tied output) on a 16 GB card', () {
    const gemma = 'gemma-4-12b-it';

    test('the card holds the blocks and a second copy of the embedding', () {
      // load_tensors: Vulkan0 model buffer size = 6776.84 MiB
      expect(_estimate(gemma, context: 16384).weightsMb, _exactly(6776.84));
    });

    test('sliding window off: every layer holds the whole context', () {
      // 260.00 (8 full layers) + 5200.00 (40 sliding layers, full size)
      expect(_estimate(gemma, context: 16384).kvCacheMb, _exactly(5460));
      // 8-bit cache at 32k: 274.12 + 5482.50
      expect(
        _estimate(gemma, context: 32768, quant: 'q8_0').kvCacheMb,
        _exactly(5756.62),
      );
    });

    test('sliding window on: the sliding layers hold the window and one '
        'batch', () {
      // 260.00 + 520.00 (1664 cells); 260.00 + 680.00 at batch 1024 (2176)
      expect(
        _estimate(gemma, context: 16384, slidingWindowOn: true).kvCacheMb,
        _exactly(780),
      );
      expect(
        _estimate(
          gemma,
          context: 16384,
          batch: 1024,
          slidingWindowOn: true,
        ).kvCacheMb,
        _exactly(940),
      );
      // 32k: the full layers grow (516.00), the window does not (520.00)
      expect(
        _estimate(gemma, context: 32768, slidingWindowOn: true).kvCacheMb,
        _exactly(1036),
      );
    });

    test('flash attention off sizes every layer\'s values to the largest', () {
      // 650.00 (K 130 + V 520) + 5200.00
      expect(
        _estimate(gemma, context: 16384, flashAttention: false).kvCacheMb,
        _exactly(5850),
      );
    });

    test('the working memory is never below what the engine reserved', () {
      expect(
        _estimate(gemma, context: 16384).computeBufMb,
        _atLeastButClose(527.00),
      );
      expect(
        _estimate(gemma, context: 16384, batch: 1024).computeBufMb,
        _atLeastButClose(1331.04),
      );
      expect(
        _estimate(gemma, context: 16384, batch: 2048).computeBufMb,
        _atLeastButClose(2662.08),
      );
      expect(
        _estimate(
          gemma,
          context: 16384,
          batch: 1024,
          slidingWindowOn: true,
        ).computeBufMb,
        _atLeastButClose(1302.79),
      );
      expect(
        _estimate(
          gemma,
          context: 16384,
          batch: 1536,
          slidingWindowOn: true,
        ).computeBufMb,
        _atLeastButClose(1955.68),
      );
      expect(
        _estimate(
          gemma,
          context: 16384,
          backend: KoboldMemoryBackend.rocm,
          flashAttention: false,
        ).computeBufMb,
        _atLeastButClose(648.01),
      );
    });
  });
}
