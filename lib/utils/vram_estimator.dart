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

// The leaf, not kobold.dart: the barrel pulls in the launch services, which
// import utils.dart back.
import 'package:front_porch_ai/services/kobold/kobold_launch_config.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/utils/gguf_model_info.dart';
import 'package:front_porch_ai/utils/kobold_memory_rules.dart';
import 'package:front_porch_ai/utils/kobold_placement.dart';

export 'package:front_porch_ai/utils/kobold_memory_rules.dart'
    show KoboldMemoryBackend;

/// Return type for [VramEstimator.estimateFromArchitecture].
typedef VramEstimateBreakdown = ({
  int weightsMb,
  int kvCacheMb,
  int computeBufMb,
  int overheadMb,
  int totalMb,
});

/// Default context size used for VRAM estimation when none is specified.
const int defaultContextSize = 16384;

/// Threshold (in MB) below which a model is considered "tight" fit.
/// If available VRAM - needed VRAM < this value, status is "tight" (yellow).
const int tightThresholdMb = 2048; // 2 GB

/// Utility class for estimating VRAM requirements and fit status.
///
/// The rough estimate (for a model in a list, before there is a file to
/// read):
/// - Model weights: file size (GGUF files are already quantized)
/// - KV cache: kvBytesPerToken * contextSize
/// - Overhead: ~5% for runtime buffers
///
/// Total = fileSize + kvCache + overhead
///
/// What the preset editor, the Local model card and a launch use is
/// `KoboldFit`, over the model file's own header. [estimateFromArchitecture]
/// is that same figure, kept for the tests that check it against real loads.
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

  /// Returns a human-readable VRAM estimate string.
  static String formatVramEstimate(int mb) {
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(2)} GB';
    }
    return '$mb MB';
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

  // ── Architecture-based estimation (uses GGUFModelInfo) ──

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
    // Every layer on the card; the experts in system memory when asked.
    // The file's own tensor table gives the weights exactly (seen on a real
    // card: 784.42 MiB reported, 784 predicted). The cache includes the
    // small fixed state of a hybrid model's recurrent layers.
    final expertsOnCpu = modelInfo.isMoe && moeExpertsOnCpu;
    final load = koboldLoad(
      info: modelInfo,
      fileSizeBytes: fileSizeBytes,
      contextSize: contextSize,
      batchSize: batchSize,
      cacheSizeFactor: _kvQuantFactor(kvQuant),
      slidingWindowOn: isSwa,
      flashAttention: flashAttention,
      backend: backend,
      moeCpuBlocks: expertsOnCpu ? modelInfo.nLayers : 0,
    );
    return (
      weightsMb: load.modelMb + load.expertsMb,
      kvCacheMb: load.cacheMb,
      computeBufMb: load.computeMb,
      overheadMb: load.overheadMb,
      totalMb: load.cardMb,
    );
  }
}
