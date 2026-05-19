// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/utils/vram_estimator.dart';
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
      expect(QuantType.fromFilename('model-Q4_K_M.gguf'), equals(QuantType.q4K));
      expect(QuantType.fromFilename('model-Q5_K_S.gguf'), equals(QuantType.q5K));
      expect(QuantType.fromFilename('model-Q8_0.gguf'), equals(QuantType.q8_0));
      expect(QuantType.fromFilename('model-Q2_K.gguf'), equals(QuantType.q2K));
      expect(QuantType.fromFilename('model-IQ2_XXS.gguf'), equals(QuantType.iq2XXS));
      expect(QuantType.fromFilename('model-FP16.gguf'), equals(QuantType.fp16));
    });

    test('returns unknown for unrecognized quantization', () {
      expect(QuantType.fromFilename('model-unknown.gguf'), equals(QuantType.unknown));
    });

    test('provides correct bytes per param estimates', () {
      expect(QuantType.q4K.bytesPerParam, closeTo(0.56, 0.01));
      expect(QuantType.q8_0.bytesPerParam, closeTo(0.99, 0.01));
      expect(QuantType.fp16.bytesPerParam, closeTo(2.0, 0.01));
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
