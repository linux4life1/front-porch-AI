// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'gguf_weights.dart';

export 'gguf_weights.dart';

/// One layer that keeps an attention cache. A layer with no attention (a
/// recurrent or convolution layer) keeps none and is not listed.
class GGUFKvLayer {
  const GGUFKvLayer(
    this.kBytesPerCell,
    this.vBytesPerCell, {
    this.sliding = false,
    this.block,
  });

  /// Bytes one cached token's keys and values take in this layer,
  /// uncompressed (f16).
  final int kBytesPerCell;
  final int vBytesPerCell;

  int get bytesPerCell => kBytesPerCell + vBytesPerCell;

  /// A sliding-window layer. With sliding window on it holds only the
  /// window, not the whole context.
  final bool sliding;

  /// The block this cache belongs to. A block KoboldCpp keeps in system
  /// memory keeps its cache there too. Null for a layer built by hand.
  final int? block;
}

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

  /// Built-in draft heads (`nextn_predict_layers`): the last blocks, which
  /// guess ahead when KoboldCpp's `usemtp` is on. 0 for most models.
  final int draftHeads;

  // Attention head sizes (for mixed-attention models like Gemma 4)
  final int? keyLength;
  final int? swaHeadDim;
  final int? leadingDenseBlockCount;

  /// The exact size of the weights, from the file's tensor table. Null when
  /// the table could not be read (or the info was built by hand).
  final GGUFWeights? weights;

  /// Every layer that keeps an attention cache, as KoboldCpp will build it.
  /// Null when the info was built by hand.
  final List<GGUFKvLayer>? kvLayers;

  /// The fixed state the recurrent layers of a hybrid model keep (newer
  /// Qwen models). It does not grow with the context. 0 for other models.
  final int recurrentStateBytes;

  /// The file's `general.architecture` ("gemma4", "qwen3"...).
  final String? architecture;

  /// Gemma's smaller models feed every layer a small embedding of its own
  /// for each token (E4B: 256 numbers). Null for other models.
  final int? perLayerInputDim;

  /// The longest context the model was made for (`context_length`).
  final int? contextLength;

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
    this.draftHeads = 0,
    this.keyLength,
    this.swaHeadDim,
    this.leadingDenseBlockCount,
    this.weights,
    this.kvLayers,
    this.recurrentStateBytes = 0,
    this.perLayerInputDim,
    this.architecture,
    this.contextLength,
  });

  /// True when the model has sliding-window layers, so the sliding window
  /// setting changes how much cache it needs.
  bool get hasSlidingWindow =>
      (slidingWindow ?? 0) > 0 && (kvLayers?.any((l) => l.sliding) ?? true);

  bool get isMoe => (expertCount ?? 0) > 1;

  int get headDim => nHeads > 0 ? (nEmbd / nHeads).round() : 0;

  /// The share of a MoE model's weights that stay on the card when its
  /// experts are kept in system memory, worked out from the parameter
  /// counts. Only the fallback for a file whose tensor table could not be
  /// read: with the table, [weights] is exact.
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
    final weightsSize = (fileSizeBytes - headerOverhead).clamp(
      0,
      fileSizeBytes,
    );
    return (weightsSize / nLayers).round();
  }
}
