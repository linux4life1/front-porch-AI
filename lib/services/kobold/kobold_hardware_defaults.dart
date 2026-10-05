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

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/services/hardware_service.dart';

import 'kobold_launch_config.dart';

/// Physical CPU cores, asked of the operating system. Falls back to the
/// logical count when the OS tool is missing or its output is unreadable.
Future<int> detectPhysicalCpuCores() async {
  try {
    if (Platform.isWindows) {
      final r = await Process.run('wmic', ['cpu', 'get', 'NumberOfCores']);
      if (r.exitCode == 0) {
        for (final line in r.stdout.toString().split('\n')) {
          final cores = int.tryParse(line.trim());
          if (cores != null && cores > 0) return cores;
        }
      }
    } else if (Platform.isMacOS) {
      final r = await Process.run('sysctl', ['-n', 'hw.physicalcpu']);
      if (r.exitCode == 0) {
        final cores = int.tryParse(r.stdout.toString().trim());
        if (cores != null && cores > 0) return cores;
      }
    } else if (Platform.isLinux) {
      final r = await Process.run('lscpu', ['-p=core']);
      if (r.exitCode == 0) {
        final coreIds = <String>{};
        for (final line in r.stdout.toString().split('\n')) {
          if (line.startsWith('#') || line.trim().isEmpty) continue;
          final parts = line.trim().split(',');
          if (parts.length >= 2) coreIds.add(parts[1]);
        }
        if (coreIds.isNotEmpty) return coreIds.length;
      }
    }
  } catch (e) {
    debugPrint('[Kobold] physical core detection failed: $e');
  }
  return Platform.numberOfProcessors;
}

/// Threads to give KoboldCpp: the physical cores on a machine with
/// hyper-threading, otherwise one fewer than there are.
Future<int> suggestKoboldThreads() async {
  final logical = Platform.numberOfProcessors;
  final physical = await detectPhysicalCpuCores();
  if (logical > physical) return physical;
  return (logical - 1).clamp(1, logical);
}

/// The graphics backend a brand-new preset should name for this machine.
///
/// A default to start the editor from, not what a launch runs and not what
/// the Local model card judges: those honour the user's own switches (see
/// [koboldBackendFor]). A preset is a file, so this one never names ROCm.
///
/// [gpuId] is the card the user chose in Settings; it is used for CUDA so a
/// laptop with an integrated chip and a discrete card lands on the right one.
({KoboldGpuBackend backend, int? gpuId}) koboldGpuFor(
  HardwareInfo? hw, {
  required int gpuId,
}) {
  if (hw == null) return (backend: KoboldGpuBackend.none, gpuId: null);
  if (hw.hasCuda) return (backend: KoboldGpuBackend.cuda, gpuId: gpuId);
  // Metal is automatic on Apple hardware; no setting is needed.
  if (hw.hasMetal) return (backend: KoboldGpuBackend.none, gpuId: null);
  // Vulkan, never hipblas: a preset must also run on mainline KoboldCpp
  // builds, which on Windows have no hipblas at all.
  if (hw.vendor == 'AMD' || hw.vendor == 'Intel') {
    return (backend: KoboldGpuBackend.vulkan, gpuId: null);
  }
  if (Platform.isWindows) return (backend: KoboldGpuBackend.vulkan, gpuId: 0);
  return (backend: KoboldGpuBackend.none, gpuId: null);
}
