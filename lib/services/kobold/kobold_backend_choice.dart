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

import 'dart:io';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/gpu_backend_resolver.dart';
import 'package:front_porch_ai/utils/kobold_memory_rules.dart';

import 'kobold_fit.dart';
import 'kobold_launch_config.dart';

/// The graphics path KoboldCpp runs a model on, and the memory rules the
/// estimate judges it by. [koboldBackendFor] is the one place either is
/// worked out: a launch, the Local model card (desktop and phone) and the
/// preset editor all take it from there, so what a card says about a model
/// is about the backend that runs it.
class KoboldBackendChoice {
  const KoboldBackendChoice({
    required this.backend,
    this.gpuId,
    this.rocm = false,
    this.unified = false,
  });

  /// What a config names: CUDA (the ROCm build is CUDA as KoboldCpp reads
  /// it), Vulkan, or neither.
  final KoboldGpuBackend backend;

  /// The card a config names; null leaves it to KoboldCpp.
  final int? gpuId;

  /// The ROCm build ([backend] is CUDA then).
  final bool rocm;

  /// Apple hardware: one pool of memory and every layer on the graphics
  /// side, whatever the switches say.
  final bool unified;

  /// Whether the model can go on a card (Apple Silicon counts).
  bool get onCard => unified || backend != KoboldGpuBackend.none;

  /// The memory rules the model follows here. With no card, CUDA's stand
  /// in: nothing is placed on a card then.
  KoboldMemoryBackend get memory => unified
      ? KoboldMemoryBackend.metal
      : backend == KoboldGpuBackend.vulkan
      ? KoboldMemoryBackend.vulkan
      : rocm
      ? KoboldMemoryBackend.rocm
      : KoboldMemoryBackend.cuda;

  /// The machine a model is fitted to: [hardware] with [free] memory
  /// (graphics memory is read for one card). [cards] is how many cards the
  /// model is spread over: each past the first counts as the smallest card
  /// seen (mixed cards never look bigger), less the half a GB a card is
  /// assumed to keep for itself.
  KoboldMachine machineFor(
    HardwareInfo hardware,
    FreeMemoryMb? free, {
    int cards = 1,
  }) {
    final small = hardware.smallestCardMb;
    final others = (cards - 1) * (small - 512).clamp(0, small);
    final freeGraphics = free?.graphics;
    return KoboldMachine(
      backend: memory,
      totalGraphicsMb: onCard ? hardware.vramMb + (cards - 1) * small : 0,
      totalSystemMb: hardware.ramMb,
      freeGraphicsMb: onCard
          ? (freeGraphics == null ? null : freeGraphics + others)
          : 0,
      freeSystemMb: free?.system,
    );
  }

  /// The batch auto mode holds the tuning to: KoboldCpp's own when nothing
  /// goes on a card, the one chosen in Settings when [automatic] is off,
  /// else null (the tuning picks the largest that fits).
  int? fixedBatch({required bool automatic, required int chosen}) => !onCard
      ? kKoboldAutoBatches.first
      : automatic
      ? null
      : chosen;
}

/// The graphics backend for this machine, by one rule for every caller.
///
/// A preset names its own backend: [preset] and [presetGpuId], which the
/// switches do not override. Otherwise the switches in Settings decide
/// ([cublas], [vulkan], [rocm] and [metal], null for never chosen, and
/// [gpuId] the card CUDA names), and with none chosen the detected card
/// does ([GpuBackendResolver]; "CPU only" is all four set to false).
///
/// [rocm] counts with a preset too: it says the engine is the ROCm build.
///
/// [unified] says the machine is Apple hardware, for a caller that knows;
/// null asks [hardware] (and the platform when that is not known yet).
KoboldBackendChoice koboldBackendFor({
  required HardwareInfo? hardware,
  bool? cublas,
  bool? vulkan,
  bool? rocm,
  bool? metal,
  int gpuId = 0,
  bool? unified,
  KoboldGpuBackend? preset,
  int? presetGpuId,
}) {
  final apple = unified ?? hardware?.hasMetal ?? Platform.isMacOS;
  if (preset != null) {
    return KoboldBackendChoice(
      backend: preset,
      gpuId: presetGpuId,
      rocm: rocm == true,
      unified: apple,
    );
  }
  final resolved = GpuBackendResolver.resolve(
    userCublas: cublas,
    userVulkan: vulkan,
    userRocm: rocm,
    userMetal: metal,
    hasCuda: hardware?.hasCuda ?? false,
    vendor: hardware?.vendor ?? 'Unknown',
    onMac: apple,
  );
  return switch (resolved) {
    // An explicit card id: card 0 can be the integrated chip on a laptop.
    GpuBackend.cuda => KoboldBackendChoice(
      backend: KoboldGpuBackend.cuda,
      gpuId: gpuId,
      unified: apple,
    ),
    GpuBackend.rocm => KoboldBackendChoice(
      backend: KoboldGpuBackend.cuda,
      gpuId: gpuId,
      rocm: true,
      unified: apple,
    ),
    GpuBackend.vulkan => KoboldBackendChoice(
      backend: KoboldGpuBackend.vulkan,
      unified: apple,
    ),
    // Metal is automatic on Apple hardware; CPU needs no setting either.
    GpuBackend.metal || GpuBackend.cpu => KoboldBackendChoice(
      backend: KoboldGpuBackend.none,
      unified: apple,
    ),
  };
}
