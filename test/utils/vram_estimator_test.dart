// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/utils/vram_estimator.dart';
import 'package:front_porch_ai/utils/gguf_parser.dart';
import 'package:front_porch_ai/models/hf_model.dart';
import 'package:front_porch_ai/models/download_task.dart';

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

    group('estimateBreakdown', () {
      test('returns readable breakdown string', () {
        final breakdown = VramEstimator.estimateBreakdown(
          fileSizeBytes: 4 * 1024 * 1024 * 1024,
          paramCountB: 8.0,
        );

        expect(breakdown, contains('Weights'));
        expect(breakdown, contains('KV Cache'));
        expect(breakdown, contains('Total'));
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
    group('activeWeightRatio', () {
      test('returns 1.0 for non-MoE models', () {
        final info = GGUFModelInfo(
          nLayers: 32,
          nHeads: 32,
          nKvHeads: 8,
          nEmbd: 4096,
          kvBytesPerToken: 8192,
        );
        expect(info.activeWeightRatio, equals(1.0));
      });

      test('returns < 1.0 for MoE models with expert_count > expert_used_count',
          () {
        final info = GGUFModelInfo(
          nLayers: 28,
          nHeads: 32,
          nKvHeads: 8,
          nEmbd: 4096,
          kvBytesPerToken: 7168,
          expertCount: 64,
          expertUsedCount: 8,
          expertFfnDim: 14336,
        );
        expect(info.activeWeightRatio, lessThan(1.0));
        expect(info.activeWeightRatio, greaterThan(0.05));
      });

      test('returns correct ratio for Mixtral-like 8x7B', () {
        final info = GGUFModelInfo(
          nLayers: 32,
          nHeads: 32,
          nKvHeads: 8,
          nEmbd: 4096,
          kvBytesPerToken: 8192,
          expertCount: 8,
          expertUsedCount: 2,
          expertFfnDim: 14336,
        );
        // 8 experts, 2 active: ~25% of expert params active
        // plus attention + router + shared expert (always active)
        expect(info.activeWeightRatio, greaterThan(0.20));
        expect(info.activeWeightRatio, lessThan(0.40));
      });
    });

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

      test('is higher than activeWeightRatio when nVocab is large', () {
        // MoE model with large vocab — embeddings + lm_head add significant
        // always-on-GPU weight that lifts the ratio above the per-layer ratio
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
        final activeRatio = info.activeWeightRatio;
        final gpuRatio = info.gpuWeightRatioWhenOffloadingExperts;
        expect(gpuRatio, greaterThan(activeRatio));
        expect(gpuRatio, greaterThan(0.06));
      });

      test('approaches activeWeightRatio when nVocab is small', () {
        // Tiny vocab means embeddings contribute negligibly
        final info = GGUFModelInfo(
          nLayers: 32,
          nHeads: 32,
          nKvHeads: 8,
          nEmbd: 4096,
          kvBytesPerToken: 8192,
          expertCount: 8,
          expertUsedCount: 2,
          expertFfnDim: 14336,
          nVocab: 100,
        );
        final activeRatio = info.activeWeightRatio;
        final gpuRatio = info.gpuWeightRatioWhenOffloadingExperts;
        // Should be very close since embedding params are tiny relative to total
        expect(gpuRatio, closeTo(activeRatio, 0.01));
      });
    });

    group('hasMixedKvHeads', () {
      test('returns false when nKvHeadsPerLayer is null', () {
        final info = GGUFModelInfo(
          nLayers: 30,
          nHeads: 16,
          nKvHeads: 8,
          nEmbd: 2816,
          kvBytesPerToken: 46080,
        );
        expect(info.hasMixedKvHeads, isFalse);
      });

      test('returns true for Gemma 4 style (25×8 + 5×2)', () {
        final perLayer = [...List.filled(25, 8), ...List.filled(5, 2)];
        final info = GGUFModelInfo(
          nLayers: 30,
          nHeads: 16,
          nKvHeads: 8,
          nEmbd: 2816,
          kvBytesPerToken: 46080,
          nKvHeadsPerLayer: perLayer,
        );
        expect(info.hasMixedKvHeads, isTrue);
      });

      test('returns false when all layers have same kv heads', () {
        final perLayer = List.filled(32, 8);
        final info = GGUFModelInfo(
          nLayers: 32,
          nHeads: 32,
          nKvHeads: 8,
          nEmbd: 4096,
          kvBytesPerToken: 8192,
          nKvHeadsPerLayer: perLayer,
        );
        expect(info.hasMixedKvHeads, isFalse);
      });

      test('handles LFM-style per-layer with 0 = default', () {
        // LFM: per-layer array with 0 meaning "use head_count"
        final perLayer = [0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
        final info = GGUFModelInfo(
          nLayers: 16,
          nHeads: 32,
          nKvHeads: 32,
          nEmbd: 2560,
          kvBytesPerToken: 20480,
          nKvHeadsPerLayer: perLayer,
        );
        expect(info.hasMixedKvHeads, isTrue);
      });
    });
  });

  group('estimateFromArchitecture', () {
    test('handles mixed kv heads per layer (Gemma 4, SWA mode)', () {
      // Simulate Gemma 4 26B with per-layer kv heads, ISWA compression active.
      // 25 layers with n_kv_heads=8 (SWA), 5 layers with n_kv_heads=2 (full)
      // SWA: head_dim=256 (keyLength/2), cells=8192/4+1024/8=2176
      // Full: head_dim=512 (keyLength), cells=8192+1024/4=8448
      // Expected KV: 25*4*8*256*2176 + 5*4*2*512*8448 = 590 MB
      final perLayer = [...List.filled(25, 8), ...List.filled(5, 2)];
      final info = GGUFModelInfo(
        nLayers: 30,
        nHeads: 16,
        nKvHeads: 8,
        nEmbd: 2816,
        kvBytesPerToken: 46080,
        expertCount: 128,
        expertUsedCount: 8,
        expertFfnDim: 1792,
        slidingWindow: 1024,
        nKvHeadsPerLayer: perLayer,
        keyLength: 512,
        swaHeadDim: 256, // gemma4: SWA head_dim = key_length / 2
      );

      final result = VramEstimator.estimateFromArchitecture(
        modelInfo: info,
        fileSizeBytes: 17 * 1024 * 1024 * 1024, // ~17 GB
        contextSize: 8192,
        batchSize: 512,
        kvQuant: 'f16',
        isSwa: true, // ISWA compression active
        moeExpertsOnCpu: false,
      );

      // KV cache should be exactly 590 MB (matches actual KoboldCPP SWA behavior)
      expect(result.kvCacheMb, equals(590));
      // With moeExpertsOnCpu=false, all weights go to GPU
      expect(result.weightsMb, greaterThan(17000));
    });

    test('handles mixed kv heads per layer (Gemma 4, FastForwarding mode)', () {
      // FastForwarding mode: ISWA compression is disabled, all layers use
      // full context cells = 8192 + 1024/4 = 8448
      // Full-attn (5): 5 * 4 * 2 * 512 * 8448 / 1M = 165 MB
      // SWA (25): 25 * 4 * 8 * 256 * 8448 / 1M = 1650 MB
      // Total: 1815 MB
      final perLayer = [...List.filled(25, 8), ...List.filled(5, 2)];
      final info = GGUFModelInfo(
        nLayers: 30,
        nHeads: 16,
        nKvHeads: 8,
        nEmbd: 2816,
        kvBytesPerToken: 46080,
        expertCount: 128,
        expertUsedCount: 8,
        expertFfnDim: 1792,
        slidingWindow: 1024,
        nKvHeadsPerLayer: perLayer,
        keyLength: 512,
        swaHeadDim: 256,
      );

      final result = VramEstimator.estimateFromArchitecture(
        modelInfo: info,
        fileSizeBytes: 17 * 1024 * 1024 * 1024,
        contextSize: 8192,
        batchSize: 512,
        kvQuant: 'f16',
        isSwa: false, // FastForwarding — no compression
        moeExpertsOnCpu: false,
      );

      expect(result.kvCacheMb, equals(1815));
    });

    test('mixed kv heads per layer capped SWA at large context (Gemma 4)', () {
      // Context=24576 with sw=1024: SWA cells cap at 8×swWindow=8192 when ISWA active.
      // nonSwaCells = 24576 + 1024/4 = 24832
      // swaCells = min(24576, 8192)/4 + 1024/8 = 2048 + 128 = 2176
      // Full (5): 5 * 4 * 2 * 512 * 24832 / 1M = 485 MB
      // SWA (25): 25 * 4 * 8 * 256 * 2176 / 1M = 425 MB
      // Total: 910 MB
      final perLayer = [...List.filled(25, 8), ...List.filled(5, 2)];
      final info = GGUFModelInfo(
        nLayers: 30,
        nHeads: 16,
        nKvHeads: 8,
        nEmbd: 2816,
        kvBytesPerToken: 46080,
        expertCount: 128,
        expertUsedCount: 8,
        expertFfnDim: 1792,
        slidingWindow: 1024,
        nKvHeadsPerLayer: perLayer,
        keyLength: 512,
        swaHeadDim: 256,
      );

      final result = VramEstimator.estimateFromArchitecture(
        modelInfo: info,
        fileSizeBytes: 17 * 1024 * 1024 * 1024,
        contextSize: 24576,
        batchSize: 512,
        kvQuant: 'f16',
        isSwa: true, // ISWA active — caps SWA cells at 8×swWindow
        moeExpertsOnCpu: false,
      );

      expect(result.kvCacheMb, equals(910));
    });

    test('full_attention_interval pattern (Qwen family)', () {
      // Simulate Qwen3 MoE with full_attention_interval=4, slidingWindow=32768
      // Every 4th layer gets full context, others use SWA.
      // With isSwa=false (FastForwarding), all layers use the same cells.
      // nonSwaCells = 8192 + 32768/4 = 16384
      // Full attn (6): 6 * 4 * 4 * 128 * 16384 / 1M = 192 MB
      // SWA (18): 18 * 4 * 4 * 128 * 16384 / 1M = 576 MB
      // Total: 768 MB
      final info = GGUFModelInfo(
        nLayers: 24,
        nHeads: 16,
        nKvHeads: 4,
        nEmbd: 2560,
        kvBytesPerToken: 6144,
        expertCount: 64,
        expertUsedCount: 4,
        expertFfnDim: 5120,
        nVocab: 151936,
        slidingWindow: 32768,
        keyLength: 128,
        fullAttentionInterval: 4,
      );

      final result = VramEstimator.estimateFromArchitecture(
        modelInfo: info,
        fileSizeBytes: 20 * 1024 * 1024 * 1024,
        contextSize: 8192,
        batchSize: 512,
        kvQuant: 'f16',
        isSwa: false, // FastForwarding — no compression
        moeExpertsOnCpu: false,
      );

      // All layers use full cells in FastForwarding mode
      expect(result.kvCacheMb, equals(768));
    });

    test('full_attention_interval pattern (Qwen, SWA mode)', () {
      // With isSwa=true, SWA layers get compressed cells.
      // nonSwaCells = 8192 + 32768/4 = 16384
      // swaCells = min(8192, 8*32768)/4 + 32768/8 = 2048 + 4096 = 6144
      // Full attn (6): 6 * 4 * 4 * 128 * 16384 / 1M = 192 MB
      // SWA (18): 18 * 4 * 4 * 128 * 6144 / 1M = 216 MB (swaHeadDim=null → keyLen=128)
      // Total: 408 MB
      final info = GGUFModelInfo(
        nLayers: 24,
        nHeads: 16,
        nKvHeads: 4,
        nEmbd: 2560,
        kvBytesPerToken: 6144,
        expertCount: 64,
        expertUsedCount: 4,
        expertFfnDim: 5120,
        nVocab: 151936,
        slidingWindow: 32768,
        keyLength: 128,
        fullAttentionInterval: 4,
      );

      final result = VramEstimator.estimateFromArchitecture(
        modelInfo: info,
        fileSizeBytes: 20 * 1024 * 1024 * 1024,
        contextSize: 8192,
        batchSize: 512,
        kvQuant: 'f16',
        isSwa: true, // ISWA compression active
        moeExpertsOnCpu: false,
      );

      expect(result.kvCacheMb, equals(408));
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

      final resultWithOffload = VramEstimator.estimateFromArchitecture(
        modelInfo: info,
        fileSizeBytes: 12 * 1024 * 1024 * 1024,
        contextSize: 8192,
        batchSize: 512,
        kvQuant: 'f16',
        isSwa: false,
        moeExpertsOnCpu: true,
      );

      final resultNoOffload = VramEstimator.estimateFromArchitecture(
        modelInfo: info,
        fileSizeBytes: 12 * 1024 * 1024 * 1024,
        contextSize: 8192,
        batchSize: 512,
        kvQuant: 'f16',
        isSwa: false,
        moeExpertsOnCpu: false,
      );

      // With offloading, weights should be lower
      expect(resultWithOffload.weightsMb, lessThan(resultNoOffload.weightsMb));
      expect(resultWithOffload.activeWeightRatio,
          lessThan(resultNoOffload.activeWeightRatio));
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
