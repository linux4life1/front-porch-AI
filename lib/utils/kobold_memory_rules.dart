// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// How much memory KoboldCpp sets aside for a model, rule by rule, as read
// from its source (1.117 to 1.122) and checked against real loads: a 16 GB
// AMD card on Vulkan and ROCm, Apple Silicon, and a 6 GB NVIDIA card's log.
// The figures quoted in the comments are those measurements, in MiB.

import 'gguf_model_info.dart';

/// The graphics backend a model runs on. The working memory and the memory
/// outside the listed buffers differ by backend.
enum KoboldMemoryBackend { cuda, rocm, vulkan, metal }

const int _mib = 1024 * 1024;

int _pad256(int n) => (n + 255) ~/ 256 * 256;

/// Cache cells for the whole context: KoboldCpp asks for 128 more than the
/// context, and the engine rounds up to 256 (16,384 becomes 16,640).
int koboldContextCells(int contextSize) => _pad256(contextSize + 128);

/// Cache cells of a sliding-window layer with sliding window on: the window
/// plus one batch rounded up to 256, then 128 more and KoboldCpp's extra
/// padding, never more than the whole context. Gemma 4 (window 1024):
/// 1,664 cells at batch 512, 2,176 at 1024.
int koboldWindowCells({
  required int contextSize,
  required int slidingWindow,
  required int batchSize,
  int swaPadding = 0,
}) {
  final full = koboldContextCells(contextSize);
  final window = _pad256((slidingWindow + batchSize).clamp(0, full));
  return (window + 128 + swaPadding).clamp(0, full);
}

/// The attention cache in bytes, layer by layer.
///
/// With flash attention off the engine stores the values transposed and
/// sizes every layer's values to the largest layer's: Gemma 4's full
/// layers then take 520 MiB of values beside 130 of keys at 16k.
double koboldKvCacheBytes({
  required List<GGUFKvLayer> layers,
  required int contextSize,
  required int batchSize,
  required double sizeFactor,
  required bool slidingWindowOn,
  required bool flashAttention,
  int slidingWindow = 0,
}) {
  final full = koboldContextCells(contextSize);
  final window = koboldWindowCells(
    contextSize: contextSize,
    slidingWindow: slidingWindow,
    batchSize: batchSize,
  );
  final vMax = layers.fold(
    0,
    (m, l) => l.vBytesPerCell > m ? l.vBytesPerCell : m,
  );
  var bytes = 0.0;
  for (final layer in layers) {
    final cells = slidingWindowOn && layer.sliding && slidingWindow > 0
        ? window
        : full;
    final v = flashAttention ? layer.vBytesPerCell : vMax;
    bytes += (layer.kBytesPerCell + v) * cells * sizeFactor;
  }
  return bytes;
}

/// The working (compute) buffer KoboldCpp reserves on the card.
///
/// Two parts of the work compete for it. The output: the scores for every
/// token of a batch over the whole vocabulary (`b * 4 * vocab`) plus a
/// little per embedding width. The layers: masks over the cache, the
/// feed-forward block and the attention queries for every token of the
/// batch. The larger part wins, except on Vulkan, which hands out memory in
/// blocks of 1 GiB: once the output alone reaches a block it gets its own
/// and cannot reuse the layers' space, so the two add up. Measured on
/// Vulkan, flash attention on: Gemma 4 12B 527.00 at batch 512 (the output
/// part exactly), 1331.04 at 1024 and 2662.08 at 2048 (output plus layers,
/// both exactly); Qwen3-14B 950.25 at 1536, 1740.05 at 2048.
///
/// With flash attention off, the layers also hold the full attention
/// scores for one layer (`4 * heads * cells * b`): Qwen3-14B at 16k takes
/// 1376.51 on ROCm against 306.75 with it on.
double koboldComputeBytes({
  required GGUFModelInfo info,
  required int contextSize,
  required int batchSize,
  required bool slidingWindowOn,
  required bool flashAttention,
  required KoboldMemoryBackend backend,
}) {
  final b = batchSize;
  final vocab = info.nVocab ?? 262144; // the largest in common use
  final embd = info.nEmbd;
  final logits = 4.0 * vocab * b;
  // A model that feeds each layer its own small embedding builds them all
  // for a batch up front: Gemma 4 E4B, 2272.00 MiB at batch 2048 on Metal,
  // which is the output part plus exactly this.
  final perLayer = info.perLayerInputDim ?? 0;
  final output =
      logits + 8.0 * embd * b + 4.0 * perLayer * (2 * info.nLayers + 8) * b;

  final full = koboldContextCells(contextSize);
  final sliding = info.hasSlidingWindow;
  final window = slidingWindowOn && sliding
      ? koboldWindowCells(
          contextSize: contextSize,
          slidingWindow: info.slidingWindow ?? 0,
          batchSize: b,
        )
      : full;
  // A model with sliding-window layers has a second mask for them.
  final masks = 2.0 * (full + (sliding ? window : 0));

  final heads = info.nHeads;
  final headDim = [
    info.keyLength ?? 0,
    info.swaHeadDim ?? 0,
    info.headDim,
  ].reduce((a, c) => a > c ? a : c);
  final perToken = masks + 4.0 * (_feedForwardFloats(info) + heads * headDim);
  var layers = perToken * b;
  if (!flashAttention) layers += 4.0 * heads * full * b;
  // Metal's attention needs working room that grows with the context, on
  // its own rather than beside the feed-forward block. It shows once it
  // outgrows the output part: Phi-4 216.00 MiB up to 20k, 257.04 at 32k,
  // 279.31 with an 8-bit cache (a smaller vocabulary than most, so its
  // output part is small). Read from those, not from the engine's source.
  final attention = backend == KoboldMemoryBackend.metal
      ? 18.0 * full * b
      : 0.0;

  final double bytes;
  if (backend == KoboldMemoryBackend.vulkan && logits >= 1024 * _mib) {
    // Exact to 0.1 MiB on Gemma 4; 1% covers the engine's alignment.
    bytes = (logits + layers) * 1.01;
  } else {
    // The output part is exact on Vulkan and Metal; a CUDA log showed 6.8%
    // more (1053.07 against 986), so it carries that margin everywhere.
    // With flash attention off a little more sits beside it (Gemma 4 E4B
    // on Metal: 616.01 against 568).
    final margin = flashAttention ? 1.08 : 1.15;
    bytes = [
      output * margin,
      layers,
      attention,
    ].reduce((a, c) => a > c ? a : c);
  }
  return bytes;
}

/// Floats per token the feed-forward block keeps at its peak: the gate, up
/// and product rows plus two rows of the embedding. A MoE layer keeps them
/// for each expert a token uses, every expert's output before they are
/// summed, the router's scores and any shared expert. Qwen3-30B-A3B at
/// batch 2048 took 1697.54 MiB; this gives 1719.
double _feedForwardFloats(GGUFModelInfo info) {
  final embd = info.nEmbd;
  final dense = 3.0 * (info.ffnDim ?? 4 * embd) + 2.0 * embd;
  if (!info.isMoe) return dense;
  final used = info.expertUsedCount ?? 8;
  final moe =
      3.0 * (info.expertFfnDim ?? 0) * used +
      2.0 * embd * used +
      2.0 * embd +
      3.0 * (info.expertCount ?? 0) +
      3.0 * (info.expertSharedFfnDim ?? 0);
  // Leading dense blocks (DeepSeek-style) use the plain block.
  final hasDense = (info.leadingDenseBlockCount ?? 0) > 0;
  return hasDense && dense > moe ? dense : moe;
}

/// Memory the engine uses beyond the buffers it lists, at load and while
/// replying. Vulkan: nothing at load, 48 to 77 MB more during a reply.
/// ROCm: 245 to 295 MB at load, then 17 to 20 MB (flash attention on) or
/// 180 to 222 MB (off) more. CUDA keeps its context there; no measurement
/// yet, so it gets the high end. Metal maps the file instead of copying it.
int koboldRuntimeOverheadMb(
  KoboldMemoryBackend backend, {
  required bool flashAttention,
}) => switch (backend) {
  KoboldMemoryBackend.vulkan => 80,
  KoboldMemoryBackend.rocm => 300 + (flashAttention ? 30 : 230),
  KoboldMemoryBackend.cuda => 500,
  KoboldMemoryBackend.metal => 100,
};

/// MiB, rounded up, so a figure is never below what was measured.
int toMibCeil(double bytes) => (bytes / _mib).ceil();
