// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/utils/utils.dart';

import 'kobold_app_config.dart';
import 'kobold_keeper_budget.dart';
import 'kobold_launch_config.dart';

/// Graphics memory a card is assumed to keep for the desktop, when it cannot
/// say how much is free: half a GB.
const int kKoboldDesktopReserveMb = 512;

/// The machine a model is fitted to, in MB.
class KoboldMachine {
  const KoboldMachine({
    required this.backend,
    required this.totalGraphicsMb,
    required this.totalSystemMb,
    this.freeGraphicsMb,
    this.freeSystemMb,
  });

  final KoboldMemoryBackend backend;
  final int totalGraphicsMb;
  final int totalSystemMb;

  /// Free before the model loads; null where the machine cannot say.
  final int? freeGraphicsMb;
  final int? freeSystemMb;

  /// Graphics memory a model can have: what is free, or the total less
  /// [kKoboldDesktopReserveMb] for the desktop when the card cannot say.
  int get graphicsMb =>
      freeGraphicsMb ??
      (totalGraphicsMb - kKoboldDesktopReserveMb).clamp(0, totalGraphicsMb);

  /// System memory free for the model and its slots: what is free, or most
  /// of the total when the system cannot say.
  int get systemMb => freeSystemMb ?? (totalSystemMb * 0.6).round();

  /// Apple Silicon: graphics and system memory are one pool.
  bool get unified => backend == KoboldMemoryBackend.metal;
}

/// One model with the settings that change how much memory it takes.
class KoboldFit {
  const KoboldFit({
    required this.info,
    required this.fileSizeBytes,
    required this.contextSize,
    required this.batchSize,
    required this.backend,
    this.kvQuant = KvQuant.f16,
    this.slidingWindowOn = false,
    this.flashAttention = true,
    this.extraCardMb = 0,
  });

  final GGUFModelInfo info;
  final int fileSizeBytes;
  final int contextSize;
  final int batchSize;
  final KoboldMemoryBackend backend;
  final KvQuant kvQuant;
  final bool slidingWindowOn;
  final bool flashAttention;

  /// Card memory something else loaded with it takes (a draft model).
  final int extraCardMb;

  /// A model with recurrent layers (newer Qwen, LFM).
  bool get recurrent => info.recurrentStateBytes > 0;

  KoboldLoad load({int? gpuLayers, int moeCpuBlocks = 0}) => koboldLoad(
    info: info,
    fileSizeBytes: fileSizeBytes,
    contextSize: contextSize,
    batchSize: batchSize,
    cacheSizeFactor: kvQuant.sizeFactor,
    slidingWindowOn: slidingWindowOn,
    flashAttention: flashAttention,
    backend: backend,
    gpuLayers: gpuLayers,
    moeCpuBlocks: moeCpuBlocks,
  );

  /// The most on the card within [budgetMb], as KoboldCpp's fit fills it.
  KoboldLoad mostThatFits(int budgetMb) => koboldMostThatFits(
    info: info,
    fileSizeBytes: fileSizeBytes,
    contextSize: contextSize,
    batchSize: batchSize,
    cacheSizeFactor: kvQuant.sizeFactor,
    slidingWindowOn: slidingWindowOn,
    flashAttention: flashAttention,
    backend: backend,
    budgetMb: budgetMb - extraCardMb,
  );

  /// The most a smart cache slot holds here: a chat that fills the context.
  int get slotMb => smartCacheSlotMb(
    info,
    contextSize: contextSize,
    sizeFactor: kvQuant.sizeFactor,
  );

  KoboldFit copyWith({
    int? contextSize,
    int? batchSize,
    KvQuant? kvQuant,
    int? extraCardMb,
  }) => KoboldFit(
    info: info,
    fileSizeBytes: fileSizeBytes,
    contextSize: contextSize ?? this.contextSize,
    batchSize: batchSize ?? this.batchSize,
    backend: backend,
    kvQuant: kvQuant ?? this.kvQuant,
    slidingWindowOn: slidingWindowOn,
    flashAttention: flashAttention,
    extraCardMb: extraCardMb ?? this.extraCardMb,
  );
}

/// System memory the model itself takes as it runs: what it reads from
/// there, or, where graphics and system memory are one pool, all of it.
int koboldModelSystemMb(KoboldLoad load, KoboldMachine machine) =>
    machine.unified ? load.cardMb + load.ramMb : load.ramMb;

/// What auto mode picks for this machine without asking: the batch, and
/// smart cache slots with context shift to match.
class KoboldAutoTuning {
  const KoboldAutoTuning({
    required this.batchSize,
    required this.load,
    required this.slots,
    required this.smartCache,
    this.chats = 0,
    this.recurrent = false,
  });

  final int batchSize;

  /// How the model lands with that batch.
  final KoboldLoad load;

  /// The slots that fit, and why that many.
  final ({int slots, SmartCacheLimit limit}) slots;

  /// What to write for them.
  final ({int asked, bool contextShift}) smartCache;

  /// Room for the slot keeper's chats beside the model ([koboldKeeperRoom]):
  /// up to the five KoboldCpp can save, as many as the free memory holds
  /// counting a full context for each; none for a model with recurrent
  /// layers. How many it keeps is [koboldKeeperChats] of this: the open chat
  /// at least, even with no room.
  final int chats;

  /// The model has recurrent layers: it stays with KoboldCpp's own smart
  /// cache, and the slot keeper keeps none of its chats.
  final bool recurrent;

  /// What to write for the chat cache: none of KoboldCpp's own smart cache
  /// when the slot keeper ([keeper]) looks after the model's chats, with
  /// context shift on, else [smartCache].
  ({int asked, bool contextShift}) cacheSetting({required bool keeper}) =>
      keeper && !recurrent ? (asked: 0, contextShift: true) : smartCache;
}

/// Physical batches auto mode runs: KoboldCpp's default and two larger ones,
/// which read a prompt faster on a card that is quick at them.
const List<int> kKoboldAutoBatches = [512, 1024, 2048];

/// The physical batch auto mode starts from, with nothing measured
/// (maintainer's ruling, 2026-10-06): 1,024 on an NVIDIA card, where even a
/// 6 GB card read faster at 1,024 than at 512; 512 everywhere else (ROCm,
/// Vulkan, Apple Silicon, no card). Memory still decides, see
/// [koboldAutoTuning].
int koboldStartBatch(KoboldMachine machine) =>
    machine.backend == KoboldMemoryBackend.cuda && machine.totalGraphicsMb > 0
    ? 1024
    : 512;

/// The smallest physical batch [fit] runs with here: 1,024 for a model with
/// recurrent layers on Vulkan, which writes garbage at 512 there (KoboldCpp
/// issue 2402), else 512.
int koboldBatchFloor(KoboldFit fit, KoboldMachine machine) =>
    fit.recurrent && machine.backend == KoboldMemoryBackend.vulkan ? 1024 : 512;

/// Graphics memory that must still be free beside the model at 2,048 for the
/// speed test to try it: twice the 1 GB KoboldCpp's own fit keeps spare.
const int kKoboldBatch2048SpareMb = 2048;

/// The physical batches the speed test tries for [fit] here: from the floor
/// ([koboldBatchFloor]) up, each that puts no less of the model on the card
/// than 512 does, and 2,048 only with plenty spare: the whole model on the
/// card and [kKoboldBatch2048SpareMb] still free beside it. Just the floor
/// without a card, where a batch is KoboldCpp's own.
List<int> koboldBatchCandidates(
  KoboldFit fit,
  KoboldMachine machine, {
  int paddingMb = kKoboldFitPaddingMb,
}) {
  final floor = koboldBatchFloor(fit, machine);
  if (machine.totalGraphicsMb <= 0) return [floor];
  final budget = _budget(machine, paddingMb);
  final base = _at(fit, machine, budget, 512);
  return [
    for (final b in kKoboldAutoBatches)
      if (b == floor ||
          (b > floor &&
              _noWorse(_at(fit, machine, budget, b), base, budget) &&
              (b < 2048 ||
                  _plentySpare(_at(fit, machine, budget, b), machine))))
        b,
  ];
}

bool _plentySpare(KoboldLoad l, KoboldMachine machine) =>
    l.allOnCard && machine.graphicsMb - l.cardMb >= kKoboldBatch2048SpareMb;

int _budget(KoboldMachine machine, int paddingMb) =>
    machine.unified ? machine.graphicsMb : machine.graphicsMb - paddingMb;

/// How [fit] lands at physical batch [b]: KoboldCpp's own fit within
/// [budget], or on Apple Silicon every layer on the graphics side.
KoboldLoad _at(KoboldFit fit, KoboldMachine machine, int budget, int b) =>
    machine.unified
    ? fit.copyWith(batchSize: b).load()
    : fit.copyWith(batchSize: b).mostThatFits(budget);

/// The kinds of prompt the app sends one engine: the chat, the judges and
/// one spare. Each gets a smart cache slot when memory allows.
const int _promptKinds = 3;

/// A model with recurrent layers is given KoboldCpp's own seven slots: one
/// of them also brings a regenerated reply back without reading the chat
/// again.
const int _recurrentPromptKinds = 7;

/// The physical batch auto mode runs, and the slots the free system memory
/// allows. The batch is [measured] (what the speed test found fastest for
/// this model here), else [koboldStartBatch], and either only while it puts
/// no less of the model on the card than 512 does: memory is a ceiling, and
/// a batch that would push layers or experts off the card falls back to
/// 512. Never below [koboldBatchFloor]. [batchSize] fixes the batch instead
/// (one the user chose, held to the floor). The fit keeps [paddingMb] spare:
/// KoboldCpp's own default unless the preset editor's "greedy" says less.
///
/// On Apple Silicon KoboldCpp puts every layer on the graphics side
/// whatever fits ("Auto GPU layers set to maximum"); there the ceiling is
/// the memory the graphics may use.
///
/// Slots: one for each kind of prompt the app sends (the chat, the judges
/// and one spare); for a model with recurrent layers KoboldCpp's own seven,
/// which also bring a regenerated reply back without reading the chat
/// again. Fewer when memory is short.
KoboldAutoTuning koboldAutoTuning(
  KoboldFit fit,
  KoboldMachine machine, {
  int paddingMb = kKoboldFitPaddingMb,
  int? batchSize,
  int? measured,
}) {
  final budget = _budget(machine, paddingMb);
  KoboldLoad at(int b) => _at(fit, machine, budget, b);
  final floor = koboldBatchFloor(fit, machine);
  final int batch;
  if (batchSize != null) {
    batch = batchSize < floor ? floor : batchSize;
  } else {
    final base = at(512);
    batch = [?measured, koboldStartBatch(machine)].firstWhere(
      (b) => b == floor || (b > floor && _noWorse(at(b), base, budget)),
      orElse: () => floor,
    );
  }
  final load = at(batch);
  final slots = suggestSmartCacheSlots(
    promptKinds: fit.recurrent ? _recurrentPromptKinds : _promptKinds,
    slotMb: fit.slotMb,
    freeRamMb: machine.systemMb,
    modelRamMb: koboldModelSystemMb(load, machine),
  );
  return KoboldAutoTuning(
    batchSize: batch,
    load: load,
    slots: slots,
    smartCache: koboldSmartCacheSetting(
      slots: slots.slots,
      recurrent: fit.recurrent,
    ),
    recurrent: fit.recurrent,
    chats: fit.recurrent
        ? 0
        : koboldKeeperRoom((
            slotMb: fit.slotMb,
            freeRamMb: machine.systemMb,
            modelRamMb: koboldModelSystemMb(load, machine),
          )),
  );
}

/// [l] fits, and keeps at least as much on the card as [base]. A larger
/// batch is never taken when it does not fit: that only makes it worse.
bool _noWorse(KoboldLoad l, KoboldLoad base, int budget) {
  if (l.cardMb > budget) return false;
  if (l.gpuLayers != base.gpuLayers) return l.gpuLayers > base.gpuLayers;
  return l.expertBlocksOnCard >= base.expertBlocksOnCard;
}

/// How the model lands as a launch places it: KoboldCpp's own fit as
/// [tuning] found it, or, with layers set by hand, [gpuLayers] on the card
/// and the experts of the first [moeCpuBlocks] blocks in system memory, at
/// the batch [tuning] chose (the launch tunes the batch either way).
KoboldLoad koboldPlacedLoad(
  KoboldFit fit,
  KoboldAutoTuning tuning, {
  int? gpuLayers,
  int moeCpuBlocks = 0,
}) => gpuLayers == null
    ? tuning.load
    : fit
          .copyWith(batchSize: tuning.batchSize)
          .load(gpuLayers: gpuLayers, moeCpuBlocks: moeCpuBlocks);
