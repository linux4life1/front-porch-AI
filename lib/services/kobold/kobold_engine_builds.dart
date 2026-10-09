// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/services/gpu_backend_resolver.dart';

/// The no-AVX2 Linux build: the only one an older processor can run.
const kLinuxOldPcEngine = 'koboldcpp-linux-x64-oldpc';

/// What each Linux KoboldCpp build can run, from the libraries each one
/// carries (checked on the release files, 2026-10-09):
/// - `koboldcpp-linux-x64`: cublas, vulkan, default (CPU)
/// - `koboldcpp-linux-x64-rocm`: hipblas, vulkan, default
/// - `koboldcpp-linux-x64-nocuda`: vulkan, default
/// - `koboldcpp-linux-x64-oldpc`: cublas, vulkan (failsafe), failsafe CPU
/// In the order a spare is looked for.
const Map<String, Set<GpuBackend>> kLinuxEngineBuilds = {
  'koboldcpp-linux-x64': {GpuBackend.cuda, GpuBackend.vulkan, GpuBackend.cpu},
  'koboldcpp-linux-x64-rocm': {
    GpuBackend.rocm,
    GpuBackend.vulkan,
    GpuBackend.cpu,
  },
  'koboldcpp-linux-x64-nocuda': {GpuBackend.vulkan, GpuBackend.cpu},
  kLinuxOldPcEngine: {GpuBackend.cuda, GpuBackend.vulkan, GpuBackend.cpu},
};

/// The engine file among [onDisk] that a start for [backend] runs on Linux:
/// [wanted] (the build this machine downloads) when it is there, else a
/// build that carries [backend] and runs on this processor ([avx2] false:
/// only the oldpc build does), else null: [wanted] has to be downloaded.
/// A ROCm choice is never run on a build without ROCm.
String? linuxEngineFor({
  required String wanted,
  required GpuBackend backend,
  required Iterable<String> onDisk,
  required bool avx2,
}) {
  final present = onDisk.toSet();
  if (present.contains(wanted)) return wanted;
  for (final MapEntry(key: name, value: runs) in kLinuxEngineBuilds.entries) {
    if (!present.contains(name)) continue;
    if (!avx2 && name != kLinuxOldPcEngine) continue;
    if (runs.contains(backend)) return name;
  }
  return null;
}
