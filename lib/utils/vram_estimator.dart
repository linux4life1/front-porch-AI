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

import 'package:front_porch_ai/models/hf_model.dart';
import 'package:front_porch_ai/utils/gguf_model_info.dart';

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
  static double _kvQuantFactor(String kvQuant) {
    switch (kvQuant) {
      case 'q8_0':
        return 0.5;
      case 'q4_0':
        return 0.25;
      default:
        return 1.0;
    }
  }

  /// Effective FFN dimension for compute buffer estimation.
  static int _ffnDimEffective(GGUFModelInfo info) {
    if (info.isMoe && info.expertFfnDim != null) {
      return info.expertFfnDim!;
    }
    return info.ffnDim ?? (4 * info.nEmbd); // fallback: 4× embd (typical gated FFN)
  }

  /// Estimate VRAM usage from detailed architecture metadata.
  ///
  /// Returns a breakdown of weights, KV cache, compute buffers, and overhead.
  /// Use [availableVramMb] to also compute fit status.
  static VramEstimateBreakdown estimateFromArchitecture({
    required GGUFModelInfo modelInfo,
    required int fileSizeBytes,
    required int contextSize,
    required int batchSize,
    required String kvQuant,
    required bool isSwa,
    required bool moeExpertsOnCpu,
    int fixedOverheadMb = defaultFixedOverheadMb,
  }) {
    final fileSizeMb = fileSizeBytes ~/ (1024 * 1024);

    // Weights on GPU
    final double weightRatio;
    if (modelInfo.isMoe && moeExpertsOnCpu) {
      // Use the GPU-resident ratio that includes non-layer tensors (embeddings, lm_head)
      weightRatio = modelInfo.gpuWeightRatioWhenOffloadingExperts;
    } else {
      weightRatio = 1.0;
    }
    const headerMb = 50; // conservative header / non-layer tensor allowance
    final weightsMb = ((fileSizeMb - headerMb).clamp(0, fileSizeMb) * weightRatio).round();

    // KV cache — handles mixed-attention models (e.g. Gemma 4 with per-layer kv heads)
    final kvFactor = _kvQuantFactor(kvQuant);
    final kvCacheMb = _estimateKvCache(
      modelInfo: modelInfo,
      contextSize: contextSize,
      kvFactor: kvFactor,
      isSwa: isSwa,
    );

    // Compute buffers (logits, attention intermediates, FFN intermediates, MoE routing)
    // Empirically 2x the simple formula to match KoboldCPP's actual sched_reserve
    // (flash attention scratch, MoE routing buffers, K+V separate projections).
    final nVocab = modelInfo.nVocab ?? 131072; // 128K fallback
    final ffnDimEff = _ffnDimEffective(modelInfo);
    final perTokenBatch = 2 * (nVocab * 2 + modelInfo.nEmbd * 8 + ffnDimEff * 4);
    final computeBufMb = (batchSize * perTokenBatch) ~/ (1024 * 1024);

    final totalMb = weightsMb + kvCacheMb + computeBufMb + fixedOverheadMb;

    return (
      weightsMb: weightsMb,
      kvCacheMb: kvCacheMb,
      computeBufMb: computeBufMb,
      overheadMb: fixedOverheadMb,
      totalMb: totalMb,
      activeWeightRatio: weightRatio,
    );
  }

  /// Estimates KV cache size with support for mixed-attention architectures.
  ///
  /// For models with per-layer `head_count_kv` arrays (e.g. Gemma 4, LFM),
  /// splits layers into full-attention (lower kv heads × key_length product) and
  /// SWA (higher kv heads × key_length product) groups. Full-attention layers use
  /// the full context; SWA layers use a compressed ISWA cache with
  /// `contextSize / 4 + slidingWindow / 8` cells and `keyLength / 2` head dim.
  ///
  /// For `full_attention_interval` patterns (Qwen), uses the same ISWA split.
  ///
  /// For uniform models, uses the simple `kvBytesPerToken * effectiveCtx` formula.
  static int _estimateKvCache({
    required GGUFModelInfo modelInfo,
    required int contextSize,
    required double kvFactor,
    required bool isSwa,
  }) {
    final perLayer = modelInfo.nKvHeadsPerLayer;
    final keyLen = modelInfo.keyLength ?? modelInfo.headDim;

    // ── Mixed-attention path (per-layer kv heads or full_attention_interval) ──
    final bool hasMixedHeads = perLayer != null &&
        perLayer.length == modelInfo.nLayers &&
        perLayer.toSet().length > 1;
    final bool hasInterval = modelInfo.fullAttentionInterval != null &&
        modelInfo.fullAttentionInterval! > 1 &&
        modelInfo.slidingWindow != null;

    if (hasMixedHeads || hasInterval) {
      final swWindow = modelInfo.slidingWindow ?? 4096;
      // ISWA compression: only applies when SWA mode is active.
      // In FastForwarding mode (isSwa=false), all layers use full context.
      final nonSwaCells = contextSize + swWindow ~/ 4;
      final swaCells = isSwa
          ? (contextSize < 8 * swWindow ? contextSize : 8 * swWindow) ~/ 4 + swWindow ~/ 8
          : nonSwaCells;
      final swaHeadDim = modelInfo.swaHeadDim ?? keyLen; // null → same as full

      int totalBytes = 0;
      for (var i = 0; i < modelInfo.nLayers; i++) {
        int nKv;
        bool isFullAttn;

        if (hasMixedHeads) {
          // Per-layer array: resolve 0 → head_count, then identify groups
          final kv = perLayer[i];
          nKv = kv > 0 ? kv : modelInfo.nHeads;
          // The group with smaller n_head_kv × key_length is full attention
          // (lower total KV dim per token = optimized for full context)
          final thisProd = nKv * keyLen;
          // Compare against the other distinct value
          final other = perLayer.firstWhere(
            (v) => (v > 0 ? v : modelInfo.nHeads) != nKv,
            orElse: () => nKv,
          );
          final otherKv = other > 0 ? other : modelInfo.nHeads;
          final otherProd = otherKv * keyLen;
          isFullAttn = thisProd < otherProd;
        } else {
          // full_attention_interval
          nKv = modelInfo.nKvHeads;
          isFullAttn = (i % modelInfo.fullAttentionInterval! == 0);
        }

        final headDim = isFullAttn ? keyLen : swaHeadDim;
        final cells = isFullAttn ? nonSwaCells : swaCells;
        totalBytes += (4 * nKv * headDim * cells * kvFactor).round();
      }
      return totalBytes ~/ (1024 * 1024);
    }

    // ── Uniform model: use the original formula ──
    final effectiveCtx = isSwa
        ? (modelInfo.slidingWindow != null
            ? contextSize.clamp(0, modelInfo.slidingWindow!)
            : contextSize.clamp(0, 4096))
        : contextSize;
    return ((modelInfo.kvBytesPerToken * effectiveCtx * kvFactor) ~/ (1024 * 1024));
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
      );
      if (est.totalMb + autofitpaddingMb <= availableVramMb) {
        return batch;
      }
    }
    return minBatch; // safe fallback
  }
}
