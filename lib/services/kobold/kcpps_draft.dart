// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/utils/smart_cache_estimate.dart';

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
    this.flashAttention = true,
    this.mmq,
    this.greedy = false,
    this.manual = false,
    this.gpuLayers = 0,
    this.moeCpuLayers = 0,
    this.slots = 0,
    this.slidingWindow = false,
    this.mmprojPath = '',
    this.mmprojOnCpu = false,
    this.draftModelPath = '',
    this.draftAmount,
    this.useMtp = false,
    this.threads,
    this.backend = KoboldGpuBackend.none,
    this.gpuId,
    this.cudaOptions = const [],
    this.extras = const {},
  });

  final String name;
  final String modelPath;
  final int contextSize;
  final KvQuant kvQuant;
  final int batchSize;
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
  final List<String> cudaOptions;
  final Map<String, dynamic> extras;

  /// The form for a preset read from a file. [recurrent]: the model has
  /// recurrent layers, which changes how many slots KoboldCpp makes.
  factory KcppsDraft.fromConfig(
    String name,
    KoboldLaunchConfig c, {
    bool recurrent = false,
  }) {
    final swa = c.contextMode == ContextManagementMode.slidingWindowAttention;
    return KcppsDraft(
      name: name,
      modelPath: c.modelPath,
      contextSize: c.contextSize,
      kvQuant: c.kvQuant,
      batchSize: c.batchSize,
      flashAttention: c.flashAttention,
      mmq: c.mmq,
      greedy: (c.autofitPaddingMb ?? 1024) < 512,
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
      mmprojPath: c.mmprojPath,
      mmprojOnCpu: c.mmprojOnCpu,
      draftModelPath: c.draftModelPath,
      draftAmount: c.draftAmount,
      useMtp: c.useMtp,
      threads: c.threads,
      backend: c.backend,
      gpuId: c.gpuId,
      cudaOptions: c.cudaOptions,
      extras: c.extras,
    );
  }

  /// The preset this form writes. [recurrent]: the model has recurrent
  /// layers (see [koboldSmartCacheSetting]); [rocm] and
  /// [rocmFlashAttentionFailed] as in Settings; [architecture] the model's.
  KoboldLaunchConfig toConfig({
    bool recurrent = false,
    bool rocm = false,
    bool rocmFlashAttentionFailed = false,
    String? architecture,
  }) {
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
      contextMode: slidingWindow
          ? ContextManagementMode.slidingWindowAttention
          : ContextManagementMode.fastForwardSmartCache,
      smartCacheSlots: slidingWindow ? 0 : cache.asked,
      contextShift: slidingWindow || cache.contextShift,
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
    ).copyWith(mmprojOnCpu: mmprojOnCpu, threads: threads);
  }

  /// The `.kcpps` map, ready to save.
  Map<String, dynamic> toMap({
    bool recurrent = false,
    bool rocm = false,
    bool rocmFlashAttentionFailed = false,
    String? architecture,
  }) {
    final map = kcppsMap(
      toConfig(
        recurrent: recurrent,
        rocm: rocm,
        rocmFlashAttentionFailed: rocmFlashAttentionFailed,
        architecture: architecture,
      ),
    );
    // No thread count leaves it to KoboldCpp.
    if (threads == null) map.remove('threads');
    return map;
  }

  KcppsDraft copyWith({
    String? name,
    String? modelPath,
    int? contextSize,
    KvQuant? kvQuant,
    int? batchSize,
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
  }) => KcppsDraft(
    name: name ?? this.name,
    modelPath: modelPath ?? this.modelPath,
    contextSize: contextSize ?? this.contextSize,
    kvQuant: kvQuant ?? this.kvQuant,
    batchSize: batchSize ?? this.batchSize,
    flashAttention: flashAttention ?? this.flashAttention,
    mmq: mmq ?? this.mmq,
    greedy: greedy ?? this.greedy,
    manual: manual ?? this.manual,
    gpuLayers: gpuLayers ?? this.gpuLayers,
    moeCpuLayers: moeCpuLayers ?? this.moeCpuLayers,
    slots: slots ?? this.slots,
    slidingWindow: slidingWindow ?? this.slidingWindow,
    mmprojPath: mmprojPath ?? this.mmprojPath,
    mmprojOnCpu: mmprojOnCpu ?? this.mmprojOnCpu,
    draftModelPath: draftModelPath ?? this.draftModelPath,
    draftAmount: clearDraftAmount ? null : draftAmount ?? this.draftAmount,
    useMtp: useMtp ?? this.useMtp,
    threads: threads,
    backend: backend ?? this.backend,
    gpuId: gpuId ?? this.gpuId,
    cudaOptions: cudaOptions,
    extras: extras,
  );
}
