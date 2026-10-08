// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/utils/utils.dart';

// Changed 2026-10-04: the five estimateFromArchitecture cache cases pinned
// a formula KoboldCpp does not use (sliding layers at "context / 4 +
// window / 8" cells, and Qwen's recurrent layers counted as sliding-window
// layers with a 32,768 window). They now pin the engine's own rules, read
// from its source and matched to the MiB on real loads (Gemma 4 12B on a
// 16 GB card: 260 + 520 MiB with sliding window on at 16k, 260 + 5200 with
// it off; a Qwen 3.6 MoE's 10 attention layers: 325.00 MiB). The real
// models are pinned in vram_estimator_real_engine_test.dart.
//
// Changed 2026-10-05: VramEstimator.estimateFromArchitecture, a wrapper
// that only these tests called, is gone. The same cases now call the
// estimate it wrapped, koboldLoad, with the same inputs (an f16 cache is a
// size factor of 1, the experts in system memory are those of every
// block), and assert the same figures: the cache is koboldLoad's cacheMb,
// the weights on the card its modelMb plus expertsMb, the total its cardMb.

void main() {
  group('VramEstimator', () {
    group('estimateVramNeeded', () {
      test('calculates VRAM for a 7B Q4 model with default context', () {
        // ~4GB file for a 7B Q4_K_M model
        final fileSize = 4 * 1024 * 1024 * 1024; // 4 GB

        final vramMb = VramEstimator.estimateVramNeeded(
          fileSizeBytes: fileSize,
          paramCountB: 7.0,
        );

        // Should be around 4GB weights + ~12MB KV cache + 5% overhead
        expect(vramMb, greaterThan(4000));
        expect(vramMb, lessThan(5000));
      });

      test('calculates VRAM with explicit KV bytes per token', () {
        final fileSize = 2 * 1024 * 1024 * 1024; // 2 GB
        final kvBytes = 1024; // 1KB per token
        final contextSize = 8192;

        final vramMb = VramEstimator.estimateVramNeeded(
          fileSizeBytes: fileSize,
          contextSize: contextSize,
          kvBytesPerToken: kvBytes,
        );

        // 2GB + (1024 * 8192 = 8MB) + 5% overhead ~ 2110 MB
        expect(vramMb, closeTo(2110, 50));
      });

      test('larger context increases VRAM estimate', () {
        final fileSize = 4 * 1024 * 1024 * 1024; // 4 GB

        final vramSmall = VramEstimator.estimateVramNeeded(
          fileSizeBytes: fileSize,
          contextSize: 4096,
          kvBytesPerToken: 1024,
        );

        final vramLarge = VramEstimator.estimateVramNeeded(
          fileSizeBytes: fileSize,
          contextSize: 32768,
          kvBytesPerToken: 1024,
        );

        expect(vramLarge, greaterThan(vramSmall));
      });
    });

    group('getFitStatus', () {
      test('returns fits when plenty of headroom', () {
        final status = VramEstimator.getFitStatus(
          neededMb: 4000,
          availableMb: 8192, // 8GB GPU
        );
        expect(status, equals(VramFitStatus.fits));
      });

      test('returns tight when less than 2GB headroom', () {
        final status = VramEstimator.getFitStatus(
          neededMb: 6500,
          availableMb: 8192, // Only ~1.7GB headroom
        );
        expect(status, equals(VramFitStatus.tight));
      });

      test('returns exceeds when model is too large', () {
        final status = VramEstimator.getFitStatus(
          neededMb: 10000,
          availableMb: 8192,
        );
        expect(status, equals(VramFitStatus.exceeds));
      });

      test('returns exceeds when available VRAM is zero', () {
        final status = VramEstimator.getFitStatus(
          neededMb: 4000,
          availableMb: 0,
        );
        expect(status, equals(VramFitStatus.exceeds));
      });

      test('boundary case exactly at 2GB threshold is tight', () {
        final status = VramEstimator.getFitStatus(
          neededMb: 6144, // 8192 - 2048 = exactly 2GB headroom
          availableMb: 8192,
        );
        // 2048 MB headroom is NOT less than 2048, so it should be fits
        expect(status, equals(VramFitStatus.fits));
      });

      test('1MB under threshold is tight', () {
        final status = VramEstimator.getFitStatus(
          neededMb: 6145, // 8192 - 2047 = 1MB under 2GB
          availableMb: 8192,
        );
        expect(status, equals(VramFitStatus.tight));
      });
    });

    group('VramFitStatus descriptions', () {
      test('fits shows headroom in GB', () {
        final desc = VramFitStatus.fits.description(4000, 8192);
        expect(desc, contains('GB free'));
      });

      test('tight shows warning', () {
        final desc = VramFitStatus.tight.description(7000, 8192);
        expect(desc, contains('tight'));
      });

      test('exceeds shows overage', () {
        final desc = VramFitStatus.exceeds.description(10000, 8192);
        expect(desc, contains('over'));
      });
    });

    group('formatVramEstimate', () {
      test('formats MB correctly', () {
        expect(VramEstimator.formatVramEstimate(512), equals('512 MB'));
      });

      test('formats GB correctly', () {
        expect(VramEstimator.formatVramEstimate(4096), equals('4.00 GB'));
      });
    });
  });

  group('QuantType', () {
    test('parses common quantization types from filenames', () {
      expect(
        QuantType.fromFilename('model-Q4_K_M.gguf'),
        equals(QuantType.q4K),
      );
      expect(
        QuantType.fromFilename('model-Q5_K_S.gguf'),
        equals(QuantType.q5K),
      );
      expect(QuantType.fromFilename('model-Q8_0.gguf'), equals(QuantType.q8_0));
      expect(QuantType.fromFilename('model-Q2_K.gguf'), equals(QuantType.q2K));
      expect(
        QuantType.fromFilename('model-IQ2_XXS.gguf'),
        equals(QuantType.iq2XXS),
      );
      expect(QuantType.fromFilename('model-FP16.gguf'), equals(QuantType.fp16));
    });

    test('returns unknown for unrecognized quantization', () {
      expect(
        QuantType.fromFilename('model-unknown.gguf'),
        equals(QuantType.unknown),
      );
    });

    test('provides correct bytes per param estimates', () {
      expect(QuantType.q4K.bytesPerParam, closeTo(0.56, 0.01));
      expect(QuantType.q8_0.bytesPerParam, closeTo(0.99, 0.01));
      expect(QuantType.fp16.bytesPerParam, closeTo(2.0, 0.01));
    });
  });

  group('GGUFModelInfo', () {
    group('gpuWeightRatioWhenOffloadingExperts', () {
      test('returns 1.0 for non-MoE models', () {
        final info = GGUFModelInfo(
          nLayers: 32,
          nHeads: 32,
          nKvHeads: 8,
          nEmbd: 4096,
          kvBytesPerToken: 8192,
        );
        expect(info.gpuWeightRatioWhenOffloadingExperts, equals(1.0));
      });

      GGUFModelInfo moe({int? nVocab}) => GGUFModelInfo(
        nLayers: 28,
        nHeads: 16,
        nKvHeads: 4,
        nEmbd: 2560,
        kvBytesPerToken: 3584,
        expertCount: 64,
        expertUsedCount: 4,
        expertFfnDim: 6912,
        nVocab: nVocab,
      );

      test('is higher when nVocab is large than with no vocabulary at all', () {
        // MoE model with large vocab — embeddings + lm_head add significant
        // always-on-GPU weight that lifts the ratio above the per-layer ratio
        // (the ratio with no vocabulary counted).
        final perLayer = moe().gpuWeightRatioWhenOffloadingExperts;
        final gpuRatio = moe(nVocab: 32768).gpuWeightRatioWhenOffloadingExperts;
        expect(gpuRatio, greaterThan(perLayer));
        expect(gpuRatio, greaterThan(0.06));
      });

      test('approaches the per-layer ratio when nVocab is small', () {
        // Tiny vocab means embeddings contribute negligibly
        GGUFModelInfo mixtral({int? nVocab}) => GGUFModelInfo(
          nLayers: 32,
          nHeads: 32,
          nKvHeads: 8,
          nEmbd: 4096,
          kvBytesPerToken: 8192,
          expertCount: 8,
          expertUsedCount: 2,
          expertFfnDim: 14336,
          nVocab: nVocab,
        );
        final perLayer = mixtral().gpuWeightRatioWhenOffloadingExperts;
        final gpuRatio = mixtral(
          nVocab: 100,
        ).gpuWeightRatioWhenOffloadingExperts;
        // 8 experts, 2 active: about a quarter of the expert params, plus the
        // attention and router that are always active.
        expect(perLayer, closeTo(0.272, 0.001));
        // Should be very close since embedding params are tiny relative to total
        expect(gpuRatio, closeTo(perLayer, 0.01));
      });
    });
  });

  group('koboldLoad', () {
    // A Gemma 4 26B-like layout: 25 sliding-window layers (8 cache heads of
    // 256) and 5 full layers (2 heads of 512), window 1024.
    final gemmaLayers = [
      ...List.filled(25, const GGUFKvLayer(4096, 4096, sliding: true)),
      ...List.filled(5, const GGUFKvLayer(2048, 2048)),
    ];
    GGUFModelInfo gemmaLike() => GGUFModelInfo(
      nLayers: 30,
      nHeads: 16,
      nKvHeads: 8,
      nEmbd: 2816,
      kvBytesPerToken: 46080,
      expertCount: 128,
      expertUsedCount: 8,
      expertFfnDim: 1792,
      slidingWindow: 1024,
      keyLength: 512,
      swaHeadDim: 256,
      kvLayers: gemmaLayers,
    );

    int kvMb(GGUFModelInfo info, {required int context, required bool swa}) =>
        koboldLoad(
          info: info,
          fileSizeBytes: 17 * 1024 * 1024 * 1024,
          contextSize: context,
          batchSize: 512,
          cacheSizeFactor: KvQuant.f16.sizeFactor,
          slidingWindowOn: swa,
          flashAttention: true,
          backend: KoboldMemoryBackend.cuda,
        ).cacheMb;

    test('sliding window on: sliding layers hold the window plus one batch '
        'and 128 cells; full layers hold the context plus 128, rounded up '
        'to 256', () {
      // 25 * 8192 B * 1664 cells + 5 * 4096 B * 8448 cells = 490.0 MiB.
      expect(kvMb(gemmaLike(), context: 8192, swa: true), 490);
    });

    test('sliding window off: every layer holds the whole context', () {
      // 25 * 8192 B * 8448 + 5 * 4096 B * 8448 = 1815.0 MiB.
      expect(kvMb(gemmaLike(), context: 8192, swa: false), 1815);
    });

    test('a longer context grows only the full layers when sliding window '
        'is on', () {
      // 25 * 8192 B * 1664 + 5 * 4096 B * 24832 = 810.0 MiB.
      expect(kvMb(gemmaLike(), context: 24576, swa: true), 810);
    });

    // A Qwen 3.6-like hybrid: of 24 layers, every 4th attends and keeps a
    // cache (4 heads of 128); the others are recurrent and keep none.
    GGUFModelInfo qwenHybrid() => GGUFModelInfo(
      nLayers: 24,
      nHeads: 16,
      nKvHeads: 4,
      nEmbd: 2560,
      kvBytesPerToken: 6 * 2048,
      expertCount: 64,
      expertUsedCount: 4,
      expertFfnDim: 5120,
      nVocab: 151936,
      keyLength: 128,
      kvLayers: List.filled(6, const GGUFKvLayer(1024, 1024)),
    );

    test('a hybrid model: only the attention layers keep a cache', () {
      // 6 * 2048 B * 8448 cells = 99.0 MiB.
      expect(kvMb(qwenHybrid(), context: 8192, swa: false), 99);
    });

    test('a hybrid model has no sliding window, so the setting changes '
        'nothing', () {
      expect(kvMb(qwenHybrid(), context: 8192, swa: true), 99);
    });

    test('uses gpuWeightRatioWhenOffloadingExperts when moeExpertsOnCpu', () {
      final info = GGUFModelInfo(
        nLayers: 28,
        nHeads: 16,
        nKvHeads: 4,
        nEmbd: 2560,
        kvBytesPerToken: 3584,
        expertCount: 64,
        expertUsedCount: 4,
        expertFfnDim: 6912,
        nVocab: 32768,
      );

      KoboldLoad load({required bool expertsOnCpu}) => koboldLoad(
        info: info,
        fileSizeBytes: 12 * 1024 * 1024 * 1024,
        contextSize: 8192,
        batchSize: 512,
        cacheSizeFactor: KvQuant.f16.sizeFactor,
        slidingWindowOn: false,
        flashAttention: true,
        backend: KoboldMemoryBackend.cuda,
        moeCpuBlocks: expertsOnCpu ? info.nLayers : 0,
      );
      int weightsOnCard(KoboldLoad l) => l.modelMb + l.expertsMb;

      final resultWithOffload = load(expertsOnCpu: true);
      final resultNoOffload = load(expertsOnCpu: false);

      // With offloading, weights should be lower
      expect(
        weightsOnCard(resultWithOffload),
        lessThan(weightsOnCard(resultNoOffload)),
      );
      expect(resultWithOffload.cardMb, lessThan(resultNoOffload.cardMb));
    });
  });

  group('DownloadTaskState', () {
    test('isActive returns correct values', () {
      expect(DownloadTaskState.downloading.isActive, isTrue);
      expect(DownloadTaskState.verifying.isActive, isTrue);
      expect(DownloadTaskState.pending.isActive, isFalse);
      expect(DownloadTaskState.paused.isActive, isFalse);
    });

    test('isTerminal returns correct values', () {
      expect(DownloadTaskState.completed.isTerminal, isTrue);
      expect(DownloadTaskState.failed.isTerminal, isTrue);
      expect(DownloadTaskState.cancelled.isTerminal, isTrue);
      expect(DownloadTaskState.downloading.isTerminal, isFalse);
    });

    test('canResume returns correct values', () {
      expect(DownloadTaskState.paused.canResume, isTrue);
      expect(DownloadTaskState.failed.canResume, isTrue);
      expect(DownloadTaskState.completed.canResume, isFalse);
      expect(DownloadTaskState.downloading.canResume, isFalse);
    });
  });
}
