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

import 'package:front_porch_ai/utils/utils.dart';

/// Which GPU acceleration path KoboldCpp should use.
enum GpuBackend { cuda, rocm, vulkan, metal, cpu }

/// THE single source of truth for GPU backend selection — binary choice,
/// launch flags, .kcpps export, and the settings UI all resolve through
/// here (previously three independent detections could disagree).
///
/// Policy:
/// - Explicit user overrides always win (Settings → Advanced acceleration).
/// - Otherwise AUTOMATIC: Metal on macOS, CUDA when the NVIDIA driver
///   answers, **Vulkan for everything else with a GPU** (AMD and Intel),
///   CPU when no GPU is usable.
/// - **ROCm is never auto-selected.** The driver offering compute
///   (`/dev/kfd`) does not prove KoboldCpp's hipblas kernels support the
///   user's gfx architecture; consumer RDNA cards additionally need
///   HSA_OVERRIDE_GFX_VERSION. Vulkan is within a few percent of hipblas on
///   consumer cards with none of that fragility, so ROCm is an explicit
///   expert opt-in — and when opted in, [rocmEnvironment] supplies the HSA
///   override automatically.
class GpuBackendResolver {
  /// Resolves the active backend from user prefs (null = not set = auto)
  /// and detected hardware facts. [onMac] says whether the machine is Apple
  /// hardware when the caller knows better than the platform this runs on
  /// (null: this platform).
  static GpuBackend resolve({
    required bool? userCublas,
    required bool? userVulkan,
    required bool? userRocm,
    required bool? userMetal,
    required bool hasCuda,
    required String vendor,
    bool? onMac,
  }) {
    // Explicit choices win, most specific first.
    if (userRocm == true) return GpuBackend.rocm;
    if (userCublas == true) return GpuBackend.cuda;
    if (userVulkan == true) return GpuBackend.vulkan;
    if (userMetal == true) return GpuBackend.metal;
    // All-false is an explicit "CPU only" choice; all-null is automatic.
    if (userRocm == false &&
        userCublas == false &&
        userVulkan == false &&
        userMetal == false) {
      return GpuBackend.cpu;
    }
    return _auto(
      hasCuda: hasCuda,
      vendor: vendor,
      onMac: onMac ?? Platform.isMacOS,
    );
  }

  /// True when no acceleration pref has ever been touched.
  static bool isAutomatic({
    required bool? userCublas,
    required bool? userVulkan,
    required bool? userRocm,
    required bool? userMetal,
  }) =>
      userCublas == null &&
      userVulkan == null &&
      userRocm == null &&
      userMetal == null;

  static GpuBackend _auto({
    required bool hasCuda,
    required String vendor,
    required bool onMac,
  }) {
    if (onMac) return GpuBackend.metal;
    if (hasCuda) return GpuBackend.cuda;
    if (vendor == 'AMD' || vendor == 'Intel') return GpuBackend.vulkan;
    return GpuBackend.cpu;
  }

  /// Short human line for the settings UI, e.g.
  /// "Vulkan (AMD GPU detected)".
  static String describe(GpuBackend backend, String vendor) {
    switch (backend) {
      case GpuBackend.cuda:
        return 'CUDA (NVIDIA GPU detected)';
      case GpuBackend.vulkan:
        return 'Vulkan ($vendor GPU detected)';
      case GpuBackend.metal:
        return 'Metal (Apple Silicon)';
      case GpuBackend.rocm:
        return 'ROCm (expert override)';
      case GpuBackend.cpu:
        return 'CPU only';
    }
  }

  // ---- ROCm expert-path support ----

  /// HSA_OVERRIDE_GFX_VERSION for consumer gfx architectures that ROCm's
  /// prebuilt kernels don't target directly. The single most common cause
  /// of "ROCm installed but koboldcpp crashes at launch". Officially
  /// supported dGPU archs (gfx900/906/908/90a/942, gfx1030, gfx1100)
  /// return null — no override needed.
  static String? hsaOverrideForGfx(String gfx) {
    final name = gfx.trim().toLowerCase();
    if (!name.startsWith('gfx')) return null;
    const supported = {
      'gfx900', 'gfx906', 'gfx908', 'gfx90a', 'gfx942',
      'gfx1030', 'gfx1100', 'gfx1201', //
    };
    if (supported.contains(name)) return null;
    // RDNA2 family (gfx1031/1032/1033/1034/1035/1036) → 10.3.0
    if (RegExp(r'^gfx103[0-9]$').hasMatch(name)) return '10.3.0';
    // RDNA3 family (gfx1101/1102/1103/1150/1151) → 11.0.0
    if (RegExp(r'^gfx11[0-9][0-9]$').hasMatch(name)) return '11.0.0';
    // RDNA4 (gfx1200/1201) → 12.0.1
    if (RegExp(r'^gfx120[0-9]$').hasMatch(name)) return '12.0.1';
    return null; // unknown arch — don't guess, let ROCm report honestly
  }

  /// Parses a gfx arch out of `rocminfo` output, picking the HIGHEST gfx
  /// number when several agents exist. That is not guaranteed to be the
  /// dGPU (an RDNA3 iGPU sorts above an RDNA3 dGPU), but it doesn't need
  /// to be: the override value is family-level (all RDNA2 → 10.3.0, all
  /// RDNA3 → 11.0.0), and officially-supported archs return null from
  /// [hsaOverrideForGfx] — so within any realistic APU+dGPU mix the
  /// resulting env is correct for the card that actually runs inference.
  static String? gfxFromRocminfo(String output) {
    final matches = RegExp(
      r'Name:\s+(gfx[0-9a-f]+)',
    ).allMatches(output).map((m) => m.group(1)!).toSet().toList();
    if (matches.isEmpty) return null;
    matches.sort();
    return matches.last;
  }

  /// The gfx arch the driver's compute topology reports (each GPU node's
  /// `gfx_target_version` under [nodesRoot]), the highest when several, as
  /// [gfxFromRocminfo] picks. Null when the driver lists none.
  static Future<String?> gfxFromKfdTopology([
    String nodesRoot = '/sys/class/kfd/kfd/topology/nodes',
  ]) async {
    final nodes = Directory(nodesRoot);
    if (!await nodes.exists()) return null;
    final found = <String>{};
    await for (final node in nodes.list()) {
      final props = File('${node.path}/properties');
      if (!await props.exists()) continue;
      final v = kfdGfxTargetVersion(await props.readAsString());
      final gfx = v == null ? null : gfxFromKfdTargetVersion(v);
      if (gfx != null) found.add(gfx);
    }
    if (found.isEmpty) return null;
    return (found.toList()..sort()).last;
  }

  /// The gfx arch from rocminfo when it is installed, else from the
  /// driver's own topology: KoboldCpp's ROCm build carries its runtime, so
  /// most machines that run it have no rocminfo.
  static Future<String?> _detectGfx() async {
    try {
      final res = await Process.run('rocminfo', []);
      if (res.exitCode == 0) {
        final gfx = gfxFromRocminfo(res.stdout.toString());
        if (gfx != null) return gfx;
      }
    } on ProcessException {
      // Not installed: the topology below answers.
    }
    return gfxFromKfdTopology();
  }

  /// Environment additions for launching KoboldCpp with ROCm: finds the
  /// gfx arch and sets HSA_OVERRIDE_GFX_VERSION when the arch needs one.
  /// Never overrides a value the user already exported themselves. Returns
  /// {} on any failure — launching without the override is exactly what
  /// happened before.
  static Future<Map<String, String>> rocmEnvironment() async {
    if (!Platform.isLinux) return const {};
    if (Platform.environment.containsKey('HSA_OVERRIDE_GFX_VERSION')) {
      return const {};
    }
    try {
      final gfx = await _detectGfx();
      if (gfx == null) return const {};
      final override = hsaOverrideForGfx(gfx);
      if (override == null) return const {};
      // ignore: avoid_print
      print('[ROCm] $gfx needs HSA_OVERRIDE_GFX_VERSION=$override — set');
      return {'HSA_OVERRIDE_GFX_VERSION': override};
    } catch (e) {
      // ignore: avoid_print
      print('[ROCm] gfx arch not read, launching without an override: $e');
      return const {};
    }
  }
}
