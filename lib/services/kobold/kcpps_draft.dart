// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/utils/utils.dart';

import 'kcpps_codec.dart';
import 'kobold_app_config.dart';
import 'kobold_launch_config.dart';

/// What the preset editor's form holds. [toConfig] turns it into the
/// preset written, by the same rules as every preset the app writes.
class KcppsDraft {
  const KcppsDraft({
    required this.name,
    this.modelPath = '',
    this.contextSize = 16384,
    this.kvQuant = KvQuant.f16,
    this.batchSize = 512,
    this.logicalBatchSize,
    this.flashAttention = true,
    this.mmq,
    this.greedy = false,
    this.manual = false,
    this.gpuLayers = 0,
    this.moeCpuLayers = 0,
    this.slots = 0,
    this.slidingWindow = false,
    this.swaLeftAsWritten,
    this.mmprojPath = '',
    this.mmprojOnCpu = false,
    this.draftModelPath = '',
    this.draftAmount,
    this.useMtp = false,
    this.threads,
    this.backend = KoboldGpuBackend.none,
    this.gpuId,
    this.moreGpuIds = const [],
    this.cudaOptions = const [],
    this.measured,
    this.extras = const {},
  });

  final String name;
  final String modelPath;
  final int contextSize;
  final KvQuant kvQuant;

  /// The physical batch (see [KoboldLaunchConfig.batchSize]); the batch field
  /// edits it. [logicalBatchSize] is kept as the preset has it.
  final int batchSize;
  final int? logicalBatchSize;
  final bool flashAttention;
  final bool? mmq;

  /// Keep 32 MB spare instead of 1 GB when KoboldCpp places the model.
  final bool greedy;

  /// The user places the model: [gpuLayers] on the card, the experts of the
  /// first [moeCpuLayers] blocks in system memory.
  final bool manual;
  final int gpuLayers;
  final int moeCpuLayers;

  /// Smart cache slots KoboldCpp should make, in all.
  final int slots;

  /// Sliding window on (fast forward off): only for a model that has it.
  final bool slidingWindow;

  /// Set when the preset says nothing about sliding window, so KoboldCpp's
  /// own default stands until the form answers it (a [copyWith] that sets
  /// [slidingWindow]). It holds what the file says about the settings that go
  /// with sliding window (fast forward, the window's padding), which [toMap]
  /// writes back as they were: saving other edits leaves the file's own
  /// answer alone, whatever model the form has.
  final Map<String, dynamic>? swaLeftAsWritten;

  /// Sliding window is left to KoboldCpp ([swaLeftAsWritten]).
  bool get slidingWindowLeft => swaLeftAsWritten != null;
  final String mmprojPath;
  final bool mmprojOnCpu;
  final String draftModelPath;

  /// Tokens drafted each step; null leaves it to KoboldCpp (4).
  final int? draftAmount;

  /// Draft with the model's own built-in draft heads.
  final bool useMtp;
  final int? threads;
  final KoboldGpuBackend backend;
  final int? gpuId;

  /// Vulkan cards after [gpuId], kept as the preset has them.
  final List<int> moreGpuIds;
  final List<String> cudaOptions;

  /// Where a speed test measured the preset (see [KoboldMeasured]).
  final KoboldMeasured? measured;
  final Map<String, dynamic> extras;

  /// The form for a preset read from a file. [recurrent]: the model has
  /// recurrent layers, which changes how many slots KoboldCpp makes. [raw]:
  /// the file as written, for what it leaves to KoboldCpp.
  factory KcppsDraft.fromConfig(
    String name,
    KoboldLaunchConfig c, {
    bool recurrent = false,
    Map<String, dynamic>? raw,
  }) {
    final swa = c.contextMode == ContextManagementMode.slidingWindowAttention;
    return KcppsDraft(
      name: name,
      modelPath: c.modelPath,
      contextSize: c.contextSize,
      kvQuant: c.kvQuant,
      batchSize: c.batchSize,
      logicalBatchSize: c.logicalBatchSize,
      flashAttention: c.flashAttention,
      mmq: c.mmq,
      greedy: koboldPaddingIsGreedy(c.autofitPaddingMb),
      manual: !c.layersAreAutomatic,
      gpuLayers: c.layersAreAutomatic ? 0 : c.gpuLayers,
      moeCpuLayers: c.moeExpertsOnCpu ? c.moeCpuLayers ?? 999 : 0,
      slots: swa
          ? 0
          : koboldSmartCacheSlots(
              asked: c.smartCacheSlots,
              recurrent: recurrent,
              fastForward: true,
              contextShift: c.contextShift,
            ),
      slidingWindow: swa,
      swaLeftAsWritten: raw != null && kcppsLeavesSwaToKobold(raw)
          ? {
              for (final k in _swaCompanions)
                if (raw.containsKey(k)) k: raw[k],
            }
          : null,
      mmprojPath: c.mmprojPath,
      mmprojOnCpu: c.mmprojOnCpu,
      draftModelPath: c.draftModelPath,
      draftAmount: c.draftAmount,
      useMtp: c.useMtp,
      threads: c.threads,
      backend: c.backend,
      gpuId: c.gpuId,
      moreGpuIds: c.moreGpuIds,
      cudaOptions: c.cudaOptions,
      measured: c.measured,
      extras: c.extras,
    );
  }

  /// The preset this form writes. [recurrent]: the model has recurrent
  /// layers (see [koboldSmartCacheSetting]); [rocm] and
  /// [rocmFlashAttentionFailed] as in Settings; [architecture] the model's.
  /// [hasSlidingWindow]: the model has one. Elsewhere [slidingWindow] does
  /// nothing and would still cost fast forward, so it is not written (as
  /// the app's own settings do, see [koboldAppConfig]).
  KoboldLaunchConfig toConfig({
    bool recurrent = false,
    bool rocm = false,
    bool rocmFlashAttentionFailed = false,
    String? architecture,
    bool hasSlidingWindow = false,
  }) {
    final swa = slidingWindow && hasSlidingWindow;
    final cache = koboldSmartCacheSetting(slots: slots, recurrent: recurrent);
    return koboldGeneratedPreset(
      modelPath: modelPath,
      contextSize: contextSize,
      batchSize: batchSize,
      threads: threads ?? 0,
      greedyAllocation: greedy,
      kvQuant: kvQuant,
      backend: backend,
      gpuId: gpuId,
      contextMode: swa
          ? ContextManagementMode.slidingWindowAttention
          : ContextManagementMode.fastForwardSmartCache,
      smartCacheSlots: swa ? 0 : cache.asked,
      contextShift: swa || cache.contextShift,
      mmprojPath: mmprojPath,
      architecture: architecture,
      flashAttention: flashAttention,
      rocm: rocm,
      rocmFlashAttentionFailed: rocmFlashAttentionFailed,
      manualLayers: manual ? gpuLayers : null,
      moeCpuLayers: manual ? moeCpuLayers : 0,
      mmq: mmq,
      draftModelPath: draftModelPath,
      draftAmount: draftAmount,
      useMtp: useMtp,
      cudaOptions: cudaOptions,
      extras: extras,
    ).copyWith(
      mmprojOnCpu: mmprojOnCpu,
      threads: threads,
      moreGpuIds: moreGpuIds,
      logicalBatchSize: logicalBatchSize,
      measured: measured,
    );
  }

  /// The `.kcpps` map, ready to save.
  Map<String, dynamic> toMap({
    bool recurrent = false,
    bool rocm = false,
    bool rocmFlashAttentionFailed = false,
    String? architecture,
    bool hasSlidingWindow = false,
  }) {
    final map = kcppsMap(
      toConfig(
        recurrent: recurrent,
        rocm: rocm,
        rocmFlashAttentionFailed: rocmFlashAttentionFailed,
        architecture: architecture,
        hasSlidingWindow: hasSlidingWindow,
      ),
    );
    // No thread count leaves it to KoboldCpp.
    if (threads == null) map.remove('threads');
    // Left to KoboldCpp: sliding window is not written either way, and the
    // settings that go with it stay as the file has them, on any model, until
    // the switch is answered. (A model without one shows no switch; the file
    // stays silent there too.)
    final left = swaLeftAsWritten;
    if (left != null) {
      for (final k in ['noswa', 'useswa', ..._swaCompanions]) {
        map.remove(k);
      }
      map.addAll(left);
    }
    return map;
  }

  /// [singleBatch] writes the batch as one field again (see
  /// [KoboldLaunchConfig.logicalBatchSize]).
  KcppsDraft copyWith({
    String? name,
    String? modelPath,
    int? contextSize,
    KvQuant? kvQuant,
    int? batchSize,
    int? logicalBatchSize,
    bool singleBatch = false,
    bool? flashAttention,
    bool? mmq,
    bool? greedy,
    bool? manual,
    int? gpuLayers,
    int? moeCpuLayers,
    int? slots,
    bool? slidingWindow,
    String? mmprojPath,
    bool? mmprojOnCpu,
    String? draftModelPath,
    int? draftAmount,
    bool clearDraftAmount = false,
    bool? useMtp,
    KoboldGpuBackend? backend,
    int? gpuId,
    KoboldMeasured? measured,
  }) => KcppsDraft(
    name: name ?? this.name,
    modelPath: modelPath ?? this.modelPath,
    contextSize: contextSize ?? this.contextSize,
    kvQuant: kvQuant ?? this.kvQuant,
    batchSize: batchSize ?? this.batchSize,
    logicalBatchSize: singleBatch
        ? null
        : logicalBatchSize ?? this.logicalBatchSize,
    flashAttention: flashAttention ?? this.flashAttention,
    mmq: mmq ?? this.mmq,
    greedy: greedy ?? this.greedy,
    manual: manual ?? this.manual,
    gpuLayers: gpuLayers ?? this.gpuLayers,
    moeCpuLayers: moeCpuLayers ?? this.moeCpuLayers,
    slots: slots ?? this.slots,
    slidingWindow: slidingWindow ?? this.slidingWindow,
    // Answering the switch ends it.
    swaLeftAsWritten: slidingWindow == null ? swaLeftAsWritten : null,
    mmprojPath: mmprojPath ?? this.mmprojPath,
    mmprojOnCpu: mmprojOnCpu ?? this.mmprojOnCpu,
    draftModelPath: draftModelPath ?? this.draftModelPath,
    draftAmount: clearDraftAmount ? null : draftAmount ?? this.draftAmount,
    useMtp: useMtp ?? this.useMtp,
    threads: threads,
    backend: backend ?? this.backend,
    gpuId: gpuId ?? this.gpuId,
    moreGpuIds: moreGpuIds,
    cudaOptions: cudaOptions,
    measured: measured ?? this.measured,
    extras: extras,
  );
}

/// The settings that go with sliding window, kept as a file has them while
/// it leaves sliding window to KoboldCpp ([KcppsDraft.swaLeftAsWritten]).
const List<String> _swaCompanions = ['nofastforward', 'swapadding'];
