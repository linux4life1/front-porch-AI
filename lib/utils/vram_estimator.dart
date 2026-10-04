// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:front_porch_ai/services/kobold/kobold_launch_config.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/utils/gguf_model_info.dart';
import 'package:front_porch_ai/utils/kobold_memory_rules.dart';

export 'package:front_porch_ai/utils/kobold_memory_rules.dart'
    show KoboldMemoryBackend;

/// Return type for [VramEstimator.estimateFromArchitecture].
typedef VramEstimateBreakdown = ({
  int weightsMb,
  int kvCacheMb,
  int computeBufMb,
  int overheadMb,
  int totalMb,
  double activeWeightRatio,
});

/// Default context size used for VRAM estimation when none is specified.
const int defaultContextSize = 16384;

/// Threshold (in MB) below which a model is considered "tight" fit.
/// If available VRAM - needed VRAM < this value, status is "tight" (yellow).
const int tightThresholdMb = 2048; // 2 GB

/// Utility class for estimating VRAM requirements and fit status.
///
/// VRAM estimation formula:
/// - Model weights: file size (GGUF files are already quantized)
/// - KV cache: kvBytesPerToken * contextSize
/// - Overhead: ~5% for runtime buffers
///
/// Total = fileSize + kvCache + overhead
class VramEstimator {
  /// Estimates total VRAM needed (in MB) to run a model.
  ///
  /// Parameters:
  /// - [fileSizeBytes]: Size of the GGUF file in bytes (the model weights).
  /// - [contextSize]: Number of tokens in the context window (default: 16384).
  /// - [kvBytesPerToken]: Bytes needed per token for KV cache. If null,
  ///   estimates based on [paramCountB].
  /// - [paramCountB]: Model parameter count in billions (for KV estimation).
  static int estimateVramNeeded({
    required int fileSizeBytes,
    int contextSize = defaultContextSize,
    int? kvBytesPerToken,
    double? paramCountB,
  }) {
    // Model weights (file size is already the quantized size)
    final weightsBytes = fileSizeBytes;

    // KV cache estimation
    final kvBytes = kvBytesPerToken ?? _estimateKvBytesPerToken(paramCountB);
    final kvCacheBytes = kvBytes * contextSize;

    // Total without overhead
    final totalBytes = weightsBytes + kvCacheBytes;

    // Add 5% overhead for runtime buffers, alignment, etc.
    final withOverhead = (totalBytes * 1.05).toInt();

    // Convert to MB
    return withOverhead ~/ (1024 * 1024);
  }

  /// Determines if a model will fit in the available VRAM.
  ///
  /// Returns:
  /// - [VramFitStatus.fits]: More than 2GB headroom remaining (green)
  /// - [VramFitStatus.tight]: Less than 2GB headroom (yellow)
  /// - [VramFitStatus.exceeds]: Model is too large (red)
  static VramFitStatus getFitStatus({
    required int neededMb,
    required int availableMb,
  }) {
    if (availableMb <= 0) return VramFitStatus.exceeds;

    final headroom = availableMb - neededMb;

    if (headroom < 0) {
      return VramFitStatus.exceeds;
    } else if (headroom < tightThresholdMb) {
      return VramFitStatus.tight;
    }
    return VramFitStatus.fits;
  }

  /// Estimates VRAM needed for a specific HuggingFace model file.
  static int estimateForHfFile({
    required HFModelFile file,
    int contextSize = defaultContextSize,
    int? kvBytesPerToken,
  }) {
    return estimateVramNeeded(
      fileSizeBytes: file.sizeBytes,
      contextSize: contextSize,
      kvBytesPerToken: kvBytesPerToken,
      paramCountB: file.paramCountB,
    );
  }

  /// Gets fit status for a specific HuggingFace model file.
  static VramFitStatus getFitForHfFile({
    required HFModelFile file,
    required int availableVramMb,
    int contextSize = defaultContextSize,
    int? kvBytesPerToken,
  }) {
    final needed = estimateForHfFile(
      file: file,
      contextSize: contextSize,
      kvBytesPerToken: kvBytesPerToken,
    );
    return getFitStatus(neededMb: needed, availableMb: availableVramMb);
  }

  /// Returns a human-readable VRAM estimate string.
  static String formatVramEstimate(int mb) {
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(2)} GB';
    }
    return '$mb MB';
  }

  /// Returns a detailed breakdown string for debugging/display.
  static String estimateBreakdown({
    required int fileSizeBytes,
    int contextSize = defaultContextSize,
    int? kvBytesPerToken,
    double? paramCountB,
  }) {
    final weightsMb = fileSizeBytes ~/ (1024 * 1024);
    final kvBytes = kvBytesPerToken ?? _estimateKvBytesPerToken(paramCountB);
    final kvCacheMb = (kvBytes * contextSize) ~/ (1024 * 1024);
    final total = estimateVramNeeded(
      fileSizeBytes: fileSizeBytes,
      contextSize: contextSize,
      kvBytesPerToken: kvBytesPerToken,
      paramCountB: paramCountB,
    );

    return 'Weights: ${weightsMb}MB | KV Cache: ${kvCacheMb}MB | Total: ${formatVramEstimate(total)}';
  }

  /// Estimates KV cache bytes per token based on model parameter count.
  ///
  /// These are FP16 estimates. Actual values depend on architecture
  /// and may be lower with KV quantization enabled.
  static int _estimateKvBytesPerToken(double? paramCountB) {
    if (paramCountB == null) return _defaultKvBytes;

    // Heuristic based on common architectures:
    // KV cache per token = 2 * layers * kvHeads * headDim * 2 (FP16)
    // Approximate by parameter class:
    if (paramCountB >= 128) {
      return 8192; // 128B+ class (e.g., Mixtral 8x22B, Command R+)
    }
    if (paramCountB >= 70) return 4096; // 70B class (e.g., Llama-3-70B)
    if (paramCountB >= 34) return 3072; // 34B class (e.g., Yi-34B)
    if (paramCountB >= 13) {
      return 2048; // 13B class (e.g., Mistral-7B-v3, Llama-2-13B)
    }
    if (paramCountB >= 8) return 1536; // 8B class (e.g., Llama-3-8B)
    if (paramCountB >= 3) return 1024; // 3B class (e.g., Phi-3)
    if (paramCountB >= 1) return 512; // 1-2B class
    return _defaultKvBytes; // <1B or unknown
  }

  /// Default KV bytes per token estimate for unknown models.
  /// Based on a typical 7B-class model (Llama/Mistral architecture).
  static const int _defaultKvBytes = 1024;

  /// ── Architecture-based estimation (uses GGUFModelInfo) ──

  /// Result of a full architecture-based VRAM estimate.
  static const int defaultFixedOverheadMb = 600;

  /// KV cache quantization byte-size factor (relative to f16).
  static double _kvQuantFactor(String kvQuant) =>
      KvQuant.parse(kvQuant).sizeFactor;

  /// Estimate VRAM usage from detailed architecture metadata.
  ///
  /// A guess of how KoboldCpp will load the model, never a setting: the
  /// weights on the card, the attention cache, the working buffer and what
  /// the engine uses beyond its listed buffers, each by the engine's own
  /// rules (see kobold_memory_rules.dart). [backend] and [flashAttention]
  /// change the working buffer and the extra memory.
  static VramEstimateBreakdown estimateFromArchitecture({
    required GGUFModelInfo modelInfo,
    required int fileSizeBytes,
    required int contextSize,
    required int batchSize,
    required String kvQuant,
    required bool isSwa,
    required bool moeExpertsOnCpu,
    KoboldMemoryBackend backend = KoboldMemoryBackend.cuda,
    bool flashAttention = true,
  }) {
    final fileSizeMb = fileSizeBytes ~/ (1024 * 1024);

    // Weights on the card. The file's own tensor table gives this exactly
    // (seen on a real card: 784.42 MiB reported, 784 predicted). The ratio
    // from the architecture numbers is the fallback for a file whose table
    // could not be read. On Metal the whole file is mapped, so it all
    // counts.
    final exact = modelInfo.weights;
    final expertsOnCpu = modelInfo.isMoe && moeExpertsOnCpu;
    final double weightRatio;
    final int weightsMb;
    if (backend == KoboldMemoryBackend.metal) {
      weightsMb = fileSizeMb;
      weightRatio = 1.0;
    } else if (exact != null && exact.total > 0) {
      final onCard = exact.gpuBytes(expertsOnCpu: expertsOnCpu);
      weightsMb = toMibCeil(onCard.toDouble());
      weightRatio = onCard / exact.total;
    } else {
      weightRatio = expertsOnCpu
          ? modelInfo.gpuWeightRatioWhenOffloadingExperts
          : 1.0;
      const headerMb = 50; // header / non-layer tensor allowance
      weightsMb = ((fileSizeMb - headerMb).clamp(0, fileSizeMb) * weightRatio)
          .round();
    }

    // The cache figure includes the small fixed state a hybrid model's
    // recurrent layers keep; it sits on the card beside the cache.
    final kvCacheMb = toMibCeil(
      koboldKvCacheBytes(
            layers: _cacheLayers(modelInfo),
            contextSize: contextSize,
            batchSize: batchSize,
            sizeFactor: _kvQuantFactor(kvQuant),
            slidingWindowOn: isSwa,
            flashAttention: flashAttention,
            slidingWindow: modelInfo.slidingWindow ?? 0,
          ) +
          modelInfo.recurrentStateBytes,
    );

    final computeBufMb = toMibCeil(
      koboldComputeBytes(
        info: modelInfo,
        contextSize: contextSize,
        batchSize: batchSize,
        slidingWindowOn: isSwa,
        flashAttention: flashAttention,
        backend: backend,
      ),
    );
    final overheadMb = koboldRuntimeOverheadMb(
      backend,
      flashAttention: flashAttention,
    );

    return (
      weightsMb: weightsMb,
      kvCacheMb: kvCacheMb,
      computeBufMb: computeBufMb,
      overheadMb: overheadMb,
      totalMb: weightsMb + kvCacheMb + computeBufMb + overheadMb,
      activeWeightRatio: weightRatio,
    );
  }

  /// The layers that keep a cache. A model read from a file lists them; one
  /// built by hand is taken as a single uniform block, the cautious reading.
  static List<GGUFKvLayer> _cacheLayers(GGUFModelInfo info) {
    final layers = info.kvLayers;
    if (layers != null) return layers;
    final half = info.kvBytesPerToken ~/ 2;
    return [GGUFKvLayer(half, info.kvBytesPerToken - half)];
  }

  /// Suggest a batch size that fits within [availableVramMb] given the margin.
  ///
  /// Picks the largest batch from a safe set of common values, falling back
  /// to 512 (KoboldCPP's own default) if nothing larger fits.
  static int suggestBatchSize({
    required GGUFModelInfo modelInfo,
    required int fileSizeBytes,
    required int contextSize,
    required String kvQuant,
    required bool isSwa,
    required bool moeExpertsOnCpu,
    required int availableVramMb,
    required int autofitpaddingMb,
    KoboldMemoryBackend backend = KoboldMemoryBackend.cuda,
    bool flashAttention = true,
    int minBatch = 512,
    int maxBatch = 8192,
  }) {
    // Candidate batch sizes: double until max, then clamp
    final candidates = <int>[];
    for (var b = minBatch; b <= maxBatch; b *= 2) {
      candidates.add(b);
    }
    if (candidates.last != maxBatch) candidates.add(maxBatch);

    // Try largest first, pick the first that fits
    for (final batch in candidates.reversed) {
      final est = estimateFromArchitecture(
        modelInfo: modelInfo,
        fileSizeBytes: fileSizeBytes,
        contextSize: contextSize,
        batchSize: batch,
        kvQuant: kvQuant,
        isSwa: isSwa,
        moeExpertsOnCpu: moeExpertsOnCpu,
        backend: backend,
        flashAttention: flashAttention,
      );
      if (est.totalMb + autofitpaddingMb <= availableVramMb) {
        return batch;
      }
    }
    return minBatch; // safe fallback
  }
}
