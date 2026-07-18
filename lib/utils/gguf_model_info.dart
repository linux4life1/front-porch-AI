// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Lightweight summary of key GGUF architecture values needed for VRAM/layer
/// calculations. Returned by [GGUFParser.getModelArchitectureInfo].
class GGUFModelInfo {
  final int nLayers;
  final int nHeads;
  final int nKvHeads;
  final int nEmbd;
  final int kvBytesPerToken;

  // MoE fields
  final int? expertCount;
  final int? expertUsedCount;
  final int? expertFfnDim;
  final int? expertSharedFfnDim;
  final int? ffnDim;
  final int? nVocab;
  final int? slidingWindow;

  // Per-layer attention fields (for mixed-attention models like Gemma 4)
  final List<int>? nKvHeadsPerLayer;
  final int? keyLength;
  final int? swaHeadDim;
  final int? fullAttentionInterval;
  final int? leadingDenseBlockCount;

  const GGUFModelInfo({
    required this.nLayers,
    required this.nHeads,
    required this.nKvHeads,
    required this.nEmbd,
    required this.kvBytesPerToken,
    this.expertCount,
    this.expertUsedCount,
    this.expertFfnDim,
    this.expertSharedFfnDim,
    this.ffnDim,
    this.nVocab,
    this.slidingWindow,
    this.nKvHeadsPerLayer,
    this.keyLength,
    this.swaHeadDim,
    this.fullAttentionInterval,
    this.leadingDenseBlockCount,
  });

  bool get isMoe => (expertCount ?? 0) > 1;

  int get headDim => nHeads > 0 ? (nEmbd / nHeads).round() : 0;

  /// Whether this model has mixed KV head counts across layers.
  bool get hasMixedKvHeads {
    final perLayer = nKvHeadsPerLayer;
    if (perLayer == null || perLayer.length != nLayers) return false;
    if (perLayer.length <= 1) return false;
    final first = perLayer.first;
    return perLayer.any((v) => v != first);
  }

  /// Ratio of active (attention + used experts) to total params per layer.
  double get activeWeightRatio {
    if (!isMoe) return 1.0;
    final e = nEmbd.toDouble();
    final h = nHeads.toDouble();
    final kh = nKvHeads.toDouble();
    final ec = expertCount!.toDouble();
    final eu = expertUsedCount!.toDouble();
    final ef = (expertFfnDim ?? 0).toDouble();
    final df = (ffnDim ?? 0).toDouble();
    final se = (expertSharedFfnDim ?? 0).toDouble();

    final attn = 2 * e * e * (1 + kh / h);
    final denseFfn = 3 * e * df;
    final sharedExp = 3 * e * se;
    final router = e * ec;
    final expFfn = 3 * e * ef;

    final total = attn + denseFfn + sharedExp + router + ec * expFfn;
    final active = attn + denseFfn + sharedExp + router + eu * expFfn;
    if (total <= 0) return 1.0;
    return active / total;
  }

  /// GPU-resident weight ratio when MoE experts are offloaded to CPU.
  double get gpuWeightRatioWhenOffloadingExperts {
    if (!isMoe) return 1.0;
    final e = nEmbd.toDouble();
    final h = nHeads.toDouble();
    final kh = nKvHeads.toDouble();
    final ec = expertCount!.toDouble();
    final eu = expertUsedCount!.toDouble();
    final ef = (expertFfnDim ?? 0).toDouble();
    final df = (ffnDim ?? 0).toDouble();
    final se = (expertSharedFfnDim ?? 0).toDouble();
    final v = (nVocab ?? 0).toDouble();

    final attn = 2 * e * e * (1 + kh / h);
    final denseFfn = 3 * e * df;
    final sharedExp = 3 * e * se;
    final router = e * ec;
    final expFfn = 3 * e * ef;

    final embeddingParams = 2 * v * e;

    final perLayerTotal = attn + denseFfn + sharedExp + router + ec * expFfn;
    final activePerLayer = attn + denseFfn + sharedExp + router + eu * expFfn;

    final total = nLayers * perLayerTotal + embeddingParams;
    final gpuResident = nLayers * activePerLayer + embeddingParams;

    if (total <= 0) return 1.0;
    return gpuResident / total;
  }

  /// Pragmatic approximation of bytes per layer for the model weights.
  int estimateBytesPerLayer(int fileSizeBytes) {
    if (nLayers <= 0) return 0;
    const int headerOverhead = 50 * 1024 * 1024;
    final weightsSize = (fileSizeBytes - headerOverhead).clamp(0, fileSizeBytes);
    return (weightsSize / nLayers).round();
  }
}
