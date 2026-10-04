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
    required this.contextMode,
  });

  final int contextSize;
  final int batchSize;

  /// False = KoboldCpp fits the model to the card itself.
  final bool layersManual;
  final int manualLayers;
  final KoboldGpuBackend backend;
  final int? gpuId;

  /// The ROCm fork: same backend setting as CUDA, but its flash attention
  /// kernel crashes on many AMD cards.
  final bool rocm;
  final bool flashAttention;
  final KvQuant kvQuant;
  final bool mlock;
  final ContextManagementMode contextMode;
}

/// What is known about the model being launched.
class KoboldModelFacts {
  const KoboldModelFacts({
    this.isMoe = false,
    this.hasSlidingWindow = false,
    this.expertsShareGpuMemory = false,
  });

  final bool isMoe;
  final bool hasSlidingWindow;

  /// Apple Silicon: system and graphics memory are one pool, so keeping MoE
  /// experts "on the CPU" frees nothing and only slows generation.
  final bool expertsShareGpuMemory;
}

/// The launch config for the app's own settings ("no preset").
///
/// Memory placement is KoboldCpp's unless the user set a layer count:
/// automatic layers, mmap on, memory lock off.
KoboldLaunchConfig koboldAppConfig({
  required String modelPath,
  required KoboldAppSettings settings,
  KoboldModelFacts model = const KoboldModelFacts(),
  String mmprojPath = '',
}) {
  final manual = settings.layersManual;
  final quantised =
      settings.kvQuant != KvQuant.f16 && settings.kvQuant != KvQuant.bf16;
  return KoboldLaunchConfig(
    modelPath: modelPath,
    contextSize: settings.contextSize,
    batchSize: settings.batchSize,
    gpuLayers: manual ? settings.manualLayers : KoboldLaunchConfig.autoLayers,
    // Locking pins the whole file in system memory. With automatic
    // fitting, or a MoE model whose experts stay off the card, that is the
    // "memory doubled, 0.2 tokens a second" case.
    useMlock: settings.mlock && manual && !model.isMoe,
    kvQuant: settings.kvQuant,
    // A quantised cache needs flash attention to shrink both halves.
    flashAttention: !settings.rocm && (settings.flashAttention || quantised),
    backend: settings.backend,
    gpuId: settings.gpuId,
    // Sliding window only where the model has it; elsewhere the setting
    // does nothing and would still cost fast forward.
    contextMode: model.hasSlidingWindow
        ? settings.contextMode
        : ContextManagementMode.fastForwardSmartCache,
    mmprojPath: mmprojPath,
    moeExpertsOnCpu: manual && model.isMoe && !model.expertsShareGpuMemory,
  );
}

/// A user preset made ready to launch: the model the app resolved, the chat
/// template on, and the vision file, whatever the file itself said.
KoboldLaunchConfig koboldPresetConfig(
  KoboldLaunchConfig preset, {
  required String modelPath,
  required String mmprojPath,
}) => preset.copyWith(
  modelPath: modelPath.isNotEmpty ? modelPath : null,
  jinja: true,
  mmprojPath: mmprojPath.isNotEmpty ? mmprojPath : null,
);
