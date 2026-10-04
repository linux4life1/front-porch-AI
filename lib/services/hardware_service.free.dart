// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'hardware_service.dart';

extension HardwareServiceFreeMemory on HardwareService {
  /// Free graphics and system memory now. Graphics is read on NVIDIA cards
  /// (nvidia-smi), AMD cards on Linux (the driver's counters) and Apple
  /// Silicon (the share the graphics may use, as far as memory is free).
  ///
  /// A reading taken while this app's KoboldCpp holds memory says less than
  /// the model will have, so callers that need "free before the model
  /// loaded" keep [HardwareService.freeBeforeEngine] instead.
  Future<FreeMemoryMb> readFreeMemory({int? gpuId}) async {
    int? system;
    try {
      system = await _freeSystemMb();
    } catch (e) {
      debugPrint('[Hardware] free system memory unknown: $e');
    }
    int? graphics;
    try {
      graphics = await _freeGraphicsMb(gpuId, system);
    } catch (e) {
      debugPrint('[Hardware] free graphics memory unknown: $e');
    }
    return (graphics: graphics, system: system);
  }

  Future<int?> _freeSystemMb() async {
    if (Platform.isLinux) {
      return meminfoAvailableMb(await File('/proc/meminfo').readAsString());
    }
    if (Platform.isMacOS) {
      final r = await Process.run('vm_stat', const []);
      return r.exitCode == 0 ? vmStatAvailableMb('${r.stdout}') : null;
    }
    if (Platform.isWindows) {
      final r = await Process.run('powershell', const [
        '-NoProfile',
        '-Command',
        '(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory',
      ]);
      return r.exitCode == 0 ? windowsFreeMb('${r.stdout}') : null;
    }
    return null;
  }

  Future<int?> _freeGraphicsMb(int? gpuId, int? freeSystem) async {
    final info = hardwareInfo;
    if (info == null) return null;
    if (Platform.isMacOS) {
      // One pool: the graphics may use its share of it, as far as it is
      // free.
      if (info.vramMb <= 0) return null;
      return freeSystem == null
          ? info.vramMb
          : (freeSystem < info.vramMb ? freeSystem : info.vramMb);
    }
    if (info.hasCuda || info.vendor == 'NVIDIA') {
      final r = await _runNvidiaSmi(const [
        '--query-gpu=memory.free',
        '--format=csv,noheader,nounits',
      ]);
      if (r != null) return nvidiaFreeMb('${r.stdout}', gpuId: gpuId);
    }
    if (Platform.isLinux && info.vendor == 'AMD') {
      final drm = Directory('/sys/class/drm');
      if (!await drm.exists()) return null;
      final cards = <(int, int?)>[];
      await for (final card in drm.list()) {
        final n = RegExp(
          r'^card(\d+)$',
        ).firstMatch(card.uri.pathSegments.where((s) => s.isNotEmpty).last);
        final total = File('${card.path}/device/mem_info_vram_total');
        final used = File('${card.path}/device/mem_info_vram_used');
        if (n == null || !await total.exists() || !await used.exists()) {
          continue;
        }
        cards.add((
          int.parse(n.group(1)!),
          amdFreeMb(
            totalBytes: await total.readAsString(),
            usedBytes: await used.readAsString(),
          ),
        ));
      }
      cards.sort((a, b) => a.$1.compareTo(b.$1));
      return amdChosenFreeMb([for (final c in cards) c.$2], gpuId: gpuId);
    }
    return null;
  }
}
