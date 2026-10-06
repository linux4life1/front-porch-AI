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
  /// counting a full context for each. None for a model with recurrent
  /// layers, which stays with KoboldCpp's own smart cache, and none without
  /// room. How many it keeps is [koboldKeeperChats] of this.
  final int chats;

  /// What to write for the chat cache: none of KoboldCpp's own smart cache
  /// when the slot keeper ([keeper]) looks after at least a chat, with
  /// context shift on, else [smartCache].
  ({int asked, bool contextShift}) cacheSetting({required bool keeper}) =>
      keeper && chats > 0 ? (asked: 0, contextShift: true) : smartCache;
}

/// Batches auto mode tries: KoboldCpp's default and two larger ones, which
/// read a prompt faster when they fit.
const List<int> kKoboldAutoBatches = [512, 1024, 2048];

/// The kinds of prompt the app sends one engine: the chat, the judges and
/// one spare. Each gets a smart cache slot when memory allows.
const int _promptKinds = 3;

/// A model with recurrent layers is given KoboldCpp's own seven slots: one
/// of them also brings a regenerated reply back without reading the chat
/// again.
const int _recurrentPromptKinds = 7;

/// The largest batch that puts no less of the model on the card than 512
/// does, and the slots the free system memory allows. [batchSize] fixes
/// the batch instead (one the user chose). The fit keeps [paddingMb] spare:
/// KoboldCpp's own default unless the preset editor's "greedy" says less.
///
/// On Apple Silicon KoboldCpp puts every layer on the graphics side
/// whatever fits ("Auto GPU layers set to maximum"); there the batch is the
/// largest that keeps the whole within the memory the graphics may use.
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
}) {
  final budget = machine.unified
      ? machine.graphicsMb
      : machine.graphicsMb - paddingMb;
  KoboldLoad at(int b) => machine.unified
      ? fit.copyWith(batchSize: b).load()
      : fit.copyWith(batchSize: b).mostThatFits(budget);
  var batch = batchSize ?? kKoboldAutoBatches.first;
  var load = at(batch);
  if (batchSize == null) {
    for (final b in kKoboldAutoBatches.skip(1)) {
      final l = at(b);
      if (_noWorse(l, load, budget)) {
        batch = b;
        load = l;
      }
    }
  }
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
