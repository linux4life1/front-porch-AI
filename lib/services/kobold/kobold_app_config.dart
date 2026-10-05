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

import 'kobold_launch_config.dart';

/// The app's own launch settings, as plain values. Built from stored
/// preferences by the caller so [koboldAppConfig] stays a pure function.
class KoboldAppSettings {
  const KoboldAppSettings({
    required this.contextSize,
    required this.batchSize,
    required this.layersManual,
    required this.manualLayers,
    required this.backend,
    required this.gpuId,
    required this.rocm,
    required this.flashAttention,
    required this.kvQuant,
    required this.mlock,
    this.rocmFlashAttentionFailed = false,
  });

  final int contextSize;
  final int batchSize;

  /// False = KoboldCpp fits the model to the card itself.
  final bool layersManual;
  final int manualLayers;
  final KoboldGpuBackend backend;
  final int? gpuId;

  /// The ROCm build: same backend setting as CUDA.
  final bool rocm;
  final bool flashAttention;
  final KvQuant kvQuant;
  final bool mlock;

  /// KoboldCpp on ROCm died on this machine with flash attention on.
  final bool rocmFlashAttentionFailed;
}

/// What is known about the model being launched.
class KoboldModelFacts {
  const KoboldModelFacts({
    this.isMoe = false,
    this.expertsShareGpuMemory = false,
    this.architecture,
  });

  final bool isMoe;

  /// The model file's `general.architecture` ("gemma4", "qwen3"...).
  final String? architecture;

  /// Apple Silicon: system and graphics memory are one pool, so keeping MoE
  /// experts "on the CPU" frees nothing and only slows generation.
  final bool expertsShareGpuMemory;
}

/// Whether KoboldCpp can run flash attention for this model here. Two
/// exceptions, both seen on real engines (2026-10-04): on Vulkan, KoboldCpp
/// 1.122.1 loads Gemma 4 and dies on its first prompt with it on (off, it
/// runs); and a ROCm machine where it already died with it on is not asked
/// again. ROCm is otherwise allowed: on an RX 6900 XT it ran every model
/// tested, faster and in less memory.
bool koboldFlashAttentionRuns({
  required KoboldGpuBackend backend,
  required bool rocm,
  String? architecture,
  bool rocmFailedBefore = false,
}) =>
    !(backend == KoboldGpuBackend.vulkan && architecture == 'gemma4') &&
    !(rocm && rocmFailedBefore);

/// Why [koboldFlashAttentionRuns] said no, in plain words, or null.
String? koboldFlashAttentionNote({
  required KoboldGpuBackend backend,
  required bool rocm,
  String? architecture,
  bool rocmFailedBefore = false,
}) {
  if (backend == KoboldGpuBackend.vulkan && architecture == 'gemma4') {
    return 'Flash attention is off for Gemma 4 on Vulkan: KoboldCpp stops on '
        'its first reply with it on. Cache compression needs it, so the '
        'cache is full size.';
  }
  if (rocm && rocmFailedBefore) {
    return 'Flash attention is off: KoboldCpp stopped on this machine with it '
        'on. Cache compression needs it, so the cache is full size.';
  }
  return null;
}

/// A compressed cache needs flash attention; without it the cache is full
/// size (f16). bf16 is not compression and is kept.
KvQuant _cacheWhere(bool flashAttentionRuns, KvQuant wanted) =>
    flashAttentionRuns || !wanted.needsFlashAttention ? wanted : KvQuant.f16;

/// The launch config for the app's own settings ("no preset").
///
/// Memory placement is KoboldCpp's unless the user set a layer count:
/// automatic layers, mmap on, memory lock off. Always the fast-forward
/// pairing, sliding window off: the other one is a choice in the preset
/// editor. What auto mode tunes for the machine (the batch, smart cache
/// slots, MMQ) is laid over this by the launch.
KoboldLaunchConfig koboldAppConfig({
  required String modelPath,
  required KoboldAppSettings settings,
  KoboldModelFacts model = const KoboldModelFacts(),
  String mmprojPath = '',
}) {
  final manual = settings.layersManual;
  final runs = koboldFlashAttentionRuns(
    backend: settings.backend,
    rocm: settings.rocm,
    architecture: model.architecture,
    rocmFailedBefore: settings.rocmFlashAttentionFailed,
  );
  final kvQuant = _cacheWhere(runs, settings.kvQuant);
  return KoboldLaunchConfig(
    modelPath: modelPath,
    contextSize: settings.contextSize,
    batchSize: settings.batchSize,
    gpuLayers: manual ? settings.manualLayers : KoboldLaunchConfig.autoLayers,
    // Locking pins the whole file in system memory. With automatic
    // fitting, or a MoE model whose experts stay off the card, that is the
    // "memory doubled, 0.2 tokens a second" case.
    useMlock: settings.mlock && manual && !model.isMoe,
    kvQuant: kvQuant,
    // A quantised cache needs flash attention to shrink both halves.
    flashAttention:
        runs && (settings.flashAttention || kvQuant.needsFlashAttention),
    backend: settings.backend,
    gpuId: settings.gpuId,
    mmprojPath: mmprojPath,
    moeExpertsOnCpu: manual && model.isMoe && !model.expertsShareGpuMemory,
  );
}

/// Graphics memory KoboldCpp's own fit leaves spare unless a preset forces
/// the fit with a figure of its own: 1 GB, its default `autofitpadding`.
/// Auto mode's guess of what fits counts on it, and so does the preset
/// editor's.
const int kKoboldFitPaddingMb = 1024;

/// What "greedy" asks a forced fit to leave spare instead: next to nothing.
const int kKoboldGreedyPaddingMb = 32;

/// A padding below this is greedy; this much or more is the usual spare.
const int kKoboldGreedyBelowMb = 512;

/// Whether a preset's `autofitpadding` ([paddingMb], null when it names
/// none) is the greedy kind.
bool koboldPaddingIsGreedy(int? paddingMb) =>
    (paddingMb ?? kKoboldFitPaddingMb) < kKoboldGreedyBelowMb;

/// Spare graphics memory a generated preset tells KoboldCpp's fit to leave
/// free: next to none when the user chose "greedy", KoboldCpp's own default
/// otherwise. The editor's guess of what fits uses the same figure.
int koboldAutofitPaddingMb({required bool greedy}) =>
    greedy ? kKoboldGreedyPaddingMb : kKoboldFitPaddingMb;

/// The preset the preset editor writes.
///
/// With automatic placement ([manualLayers] null) KoboldCpp fits the model
/// itself, and the editor GUESSES how that fit comes out so the user can
/// pick a context size, batch size and cache type that fit in what is left.
/// The guess only holds while KoboldCpp fits with the spare memory the
/// editor assumed. KoboldCpp keeps a preset's `autofitpadding` only when
/// the fit is FORCED (`autofit: true`). When it switches the fit on by
/// itself it puts the padding back to its own default (seen on a real
/// 1.117.1: a preset's 32 came back as 1024), and "greedy" then does
/// nothing while the editor still counts on it.
///
/// With [manualLayers] the user places the model: that many layers on the
/// card (the output layer and the last blocks) and, for a MoE model, the
/// experts of the first [moeCpuLayers] blocks in system memory. The fit is
/// then not forced: a forced fit ignores both.
KoboldLaunchConfig koboldGeneratedPreset({
  required String modelPath,
  required int contextSize,
  required int batchSize,
  required int threads,
  required bool greedyAllocation,
  required KvQuant kvQuant,
  required KoboldGpuBackend backend,
  required int? gpuId,
  required ContextManagementMode contextMode,
  required int smartCacheSlots,
  String mmprojPath = '',
  String? architecture,
  bool flashAttention = true,
  bool rocm = false,
  bool rocmFlashAttentionFailed = false,
  int? manualLayers,
  int moeCpuLayers = 0,
  bool? mmq,
  String draftModelPath = '',
  int? draftAmount,
  bool useMtp = false,
  bool contextShift = true,
  List<String> cudaOptions = const [],
  Map<String, dynamic> extras = const {},
}) {
  final runs = koboldFlashAttentionRuns(
    backend: backend,
    rocm: rocm,
    architecture: architecture,
    rocmFailedBefore: rocmFlashAttentionFailed,
  );
  final fa = runs && flashAttention;
  final manual = manualLayers != null;
  final moeCpu = manual && moeCpuLayers > 0;
  return KoboldLaunchConfig(
    modelPath: modelPath,
    contextSize: contextSize,
    batchSize: batchSize,
    threads: threads,
    gpuLayers: manualLayers ?? KoboldLaunchConfig.autoLayers,
    autofitPaddingMb: manual
        ? null
        : koboldAutofitPaddingMb(greedy: greedyAllocation),
    forceFit: !manual,
    flashAttention: fa,
    kvQuant: _cacheWhere(fa, kvQuant),
    backend: backend,
    gpuId: gpuId,
    contextMode: contextMode,
    smartCacheSlots: smartCacheSlots,
    mmprojPath: mmprojPath,
    moeExpertsOnCpu: moeCpu,
    moeCpuLayers: moeCpu ? moeCpuLayers : null,
    mmq: mmq,
    draftModelPath: draftModelPath,
    draftAmount: draftAmount,
    useMtp: useMtp,
    contextShift: contextShift,
    cudaOptions: cudaOptions,
    // A file's own forced-fit word gives way to the placement chosen here.
    extras: {...extras}..remove('autofit'),
  );
}
