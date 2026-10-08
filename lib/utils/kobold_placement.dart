// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Where KoboldCpp puts a model's parts for a layer count and a MoE setting,
// and what that takes on the card and in system memory. The rules are the
// engine's; these cases were checked on a real 16 GB card (KoboldCpp
// 1.122.1, Vulkan), in MiB:
//  - A layer count of N puts the output layer on the card first, then the
//    LAST N - 1 blocks. Qwen3-14B at 20 of 41: blocks 21 to 39 and the
//    output, 4843.57, the file's own sizes for those exactly.
//  - `moecpu M` keeps the expert weights of the FIRST M blocks in system
//    memory. Qwen3-30B-A3B with all of them there: 784.42 on the card,
//    exactly its weights that are not experts.
//  - A block in system memory keeps its chat memory there: Qwen3-14B at
//    64k, 19 blocks' cache on the card and 21 in system memory, 4883 and
//    5397.

import 'gguf_model_info.dart';
import 'kobold_memory_rules.dart';

const double _mib = 1024 * 1024;

/// Where a model's parts land, in MiB.
class KoboldLoad {
  const KoboldLoad({
    required this.gpuLayers,
    required this.layerCount,
    required this.moeCpuBlocks,
    required this.expertBlocks,
    required this.expertBlocksOnCard,
    required this.modelMb,
    required this.expertsMb,
    required this.cacheMb,
    required this.computeMb,
    required this.overheadMb,
    required this.ramWeightsMb,
    required this.ramCacheMb,
    this.ramExpertsMb = 0,
  });

  /// Layers on the card, the output layer counting as one, of [layerCount]:
  /// the blocks plus the output layer.
  final int gpuLayers;
  final int layerCount;

  /// The first blocks whose experts stay in system memory.
  final int moeCpuBlocks;

  /// Blocks that have experts, and how many of those keep them on the card.
  final int expertBlocks;
  final int expertBlocksOnCard;

  /// Weights on the card other than expert weights.
  final int modelMb;

  /// Expert weights on the card.
  final int expertsMb;
  final int cacheMb;
  final int computeMb;
  final int overheadMb;

  /// System memory the model reads from as it runs: weights (the input
  /// embedding always among them) and the cache of blocks kept there.
  final int ramWeightsMb;
  final int ramCacheMb;

  /// The expert weights among [ramWeightsMb].
  final int ramExpertsMb;

  int get cardMb => modelMb + expertsMb + cacheMb + computeMb + overheadMb;
  int get ramMb => ramWeightsMb + ramCacheMb;

  /// Every layer, and every expert, on the card.
  bool get allOnCard =>
      gpuLayers >= layerCount && expertBlocksOnCard >= expertBlocks;
}

/// The load for [gpuLayers] (null: every layer) with the experts of the
/// first [moeCpuBlocks] blocks in system memory.
///
/// On Apple Silicon the whole file is mapped into memory the graphics
/// reads directly, so the weights count in full wherever the layers run.
KoboldLoad koboldLoad({
  required GGUFModelInfo info,
  required int fileSizeBytes,
  required int contextSize,
  required int batchSize,
  required double cacheSizeFactor,
  required bool slidingWindowOn,
  required bool flashAttention,
  required KoboldMemoryBackend backend,
  int? gpuLayers,
  int moeCpuBlocks = 0,
}) {
  final blocks = info.nLayers;
  final layerCount = blocks + 1;
  final layers = (gpuLayers ?? layerCount).clamp(0, layerCount);
  final firstOnCard = blocks - (layers - 1).clamp(0, blocks);
  final moeCpu = info.isMoe ? moeCpuBlocks.clamp(0, blocks) : 0;
  final weights = _placeWeights(
    info: info,
    fileSizeBytes: fileSizeBytes,
    firstOnCard: firstOnCard,
    outputOnCard: layers >= 1,
    moeCpu: moeCpu,
    metal: backend == KoboldMemoryBackend.metal,
  );

  final cacheLayers =
      info.kvLayers ??
      [
        GGUFKvLayer(
          info.kvBytesPerToken ~/ 2,
          info.kvBytesPerToken - info.kvBytesPerToken ~/ 2,
        ),
      ];
  bool onCard(GGUFKvLayer l) => l.block == null || l.block! >= firstOnCard;
  double cache(bool Function(GGUFKvLayer) include) => koboldKvCacheBytes(
    layers: cacheLayers,
    contextSize: contextSize,
    batchSize: batchSize,
    sizeFactor: cacheSizeFactor,
    slidingWindowOn: slidingWindowOn,
    flashAttention: flashAttention,
    slidingWindow: info.slidingWindow ?? 0,
    include: include,
  );

  return KoboldLoad(
    gpuLayers: layers,
    layerCount: layerCount,
    moeCpuBlocks: moeCpu,
    expertBlocks: weights.expertBlocks,
    expertBlocksOnCard: weights.expertBlocksOnCard,
    modelMb: weights.modelMb,
    expertsMb: weights.expertsMb,
    // A hybrid model's small recurrent state is counted on the card.
    cacheMb: toMibCeil(cache(onCard) + info.recurrentStateBytes),
    computeMb: toMibCeil(
      koboldComputeBytes(
        info: info,
        contextSize: contextSize,
        batchSize: batchSize,
        slidingWindowOn: slidingWindowOn,
        flashAttention: flashAttention,
        backend: backend,
        split: firstOnCard > 0,
      ),
    ),
    overheadMb: koboldRuntimeOverheadMb(
      backend,
      flashAttention: flashAttention,
    ),
    ramWeightsMb: weights.ramMb,
    ramExpertsMb: weights.ramExpertsMb,
    ramCacheMb: toMibCeil(cache((l) => !onCard(l))),
  );
}

/// The weights' share of [koboldLoad].
({
  int modelMb,
  int expertsMb,
  int ramMb,
  int ramExpertsMb,
  int expertBlocks,
  int expertBlocksOnCard,
})
_placeWeights({
  required GGUFModelInfo info,
  required int fileSizeBytes,
  required int firstOnCard,
  required bool outputOnCard,
  required int moeCpu,
  required bool metal,
}) {
  final blocks = info.nLayers;
  final w = info.weights;
  final exact = w != null && w.total > 0;
  var expertBlocks = 0, expertBlocksOnCard = 0;
  for (var i = 0; i < blocks; i++) {
    final hasExperts = exact
        ? i < w.perBlockExperts.length && w.perBlockExperts[i] > 0
        : info.isMoe;
    if (!hasExperts) continue;
    expertBlocks++;
    if (i >= firstOnCard && i >= moeCpu) expertBlocksOnCard++;
  }
  final counts = (
    expertBlocks: expertBlocks,
    expertBlocksOnCard: expertBlocksOnCard,
  );

  if (metal) {
    return (
      modelMb: fileSizeBytes ~/ _mib,
      expertsMb: 0,
      ramMb: 0,
      ramExpertsMb: 0,
      expertBlocks: counts.expertBlocks,
      expertBlocksOnCard: counts.expertBlocksOnCard,
    );
  }

  if (!exact) {
    // No tensor table: the share the architecture numbers give, spread
    // evenly over the blocks.
    final fileMb = fileSizeBytes ~/ _mib;
    final body = (fileMb - 50).clamp(0, fileMb).toDouble();
    final expertShare = info.isMoe
        ? 1 - info.gpuWeightRatioWhenOffloadingExperts
        : 0.0;
    final perBlock = blocks > 0 ? body / blocks : 0.0;
    final cardBlocks = blocks - firstOnCard;
    final model = perBlock * cardBlocks * (1 - expertShare);
    final experts = perBlock * expertShare * counts.expertBlocksOnCard;
    final card = (model + experts).round();
    final ramExperts =
        perBlock *
        expertShare *
        (counts.expertBlocks - counts.expertBlocksOnCard);
    return (
      modelMb: model.round().clamp(0, card),
      expertsMb: card - model.round().clamp(0, card),
      ramMb: (fileMb - card).clamp(0, fileMb),
      ramExpertsMb: ramExperts.round(),
      expertBlocks: counts.expertBlocks,
      expertBlocksOnCard: counts.expertBlocksOnCard,
    );
  }

  var model = 0.0, experts = 0.0, ram = w.tokenEmbedding.toDouble();
  var ramExperts = 0.0;
  for (var i = 0; i < w.perBlock.length; i++) {
    final own = i < w.perBlockExperts.length ? w.perBlockExperts[i] : 0;
    if (i < firstOnCard) {
      ram += w.perBlock[i];
      ramExperts += own;
      continue;
    }
    model += w.perBlock[i] - own;
    if (i >= moeCpu) {
      experts += own;
    } else {
      ram += own;
      ramExperts += own;
    }
  }
  // A tied model's output layer is a second copy of the input embedding,
  // made on the card; the first stays in system memory.
  if (outputOnCard) {
    model += (w.tiedOutput ? w.tokenEmbedding : w.output) + w.other;
  } else {
    ram += w.output + w.other;
  }
  final card = toMibCeil(model + experts);
  final modelMb = toMibCeil(model).clamp(0, card);
  return (
    modelMb: modelMb,
    expertsMb: card - modelMb,
    ramMb: toMibCeil(ram),
    ramExpertsMb: toMibCeil(ramExperts),
    expertBlocks: counts.expertBlocks,
    expertBlocksOnCard: counts.expertBlocksOnCard,
  );
}

/// The placement that puts the most on the card within [budgetMb]: every
/// layer when it all fits; else, for a MoE model, the experts of as few of
/// the first blocks as needed in system memory; else as many of the last
/// layers as fit, every expert in system memory. KoboldCpp's automatic fit
/// fills the card the same way (seen: every layer on the card and part of
/// the experts, for a MoE model bigger than the card).
///
/// When nothing fits, not even the output layer: no layers at all.
KoboldLoad koboldMostThatFits({
  required GGUFModelInfo info,
  required int fileSizeBytes,
  required int contextSize,
  required int batchSize,
  required double cacheSizeFactor,
  required bool slidingWindowOn,
  required bool flashAttention,
  required KoboldMemoryBackend backend,
  required int budgetMb,
}) {
  KoboldLoad load(int layers, int moeCpu) => koboldLoad(
    info: info,
    fileSizeBytes: fileSizeBytes,
    contextSize: contextSize,
    batchSize: batchSize,
    cacheSizeFactor: cacheSizeFactor,
    slidingWindowOn: slidingWindowOn,
    flashAttention: flashAttention,
    backend: backend,
    gpuLayers: layers,
    moeCpuBlocks: moeCpu,
  );
  final blocks = info.nLayers;
  final all = blocks + 1;
  if (info.isMoe) {
    for (var m = 0; m <= blocks; m++) {
      final l = load(all, m);
      if (l.cardMb <= budgetMb) return l;
    }
  }
  final moeCpu = info.isMoe ? blocks : 0;
  for (var n = all; n > 0; n--) {
    final l = load(n, moeCpu);
    if (l.cardMb <= budgetMb) return l;
  }
  return load(0, moeCpu);
}
