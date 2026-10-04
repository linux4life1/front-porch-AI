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
      final cards = await amdDrmCards();
      if (cards.isEmpty) return null;
      return amdChosenFreeMb([
        for (final c in cards)
          if (c.used != null)
            amdFreeMb(totalBytes: c.total, usedBytes: c.used!),
      ], gpuId: gpuId);
    }
    return null;
  }
}

/// The AMD graphics cards the driver lists under [root], in card order, with
/// their total and used memory in bytes as the driver writes them. Each card
/// is listed twice there (`cardN` and its `renderDN` node, both with the
/// card's memory files), so only `cardN` entries count.
Future<List<({int id, String total, String? used})>> amdDrmCards([
  String root = '/sys/class/drm',
]) async {
  final drm = Directory(root);
  if (!await drm.exists()) return const [];
  final cards = <({int id, String total, String? used})>[];
  await for (final entry in drm.list()) {
    final n = RegExp(
      r'^card(\d+)$',
    ).firstMatch(entry.uri.pathSegments.where((s) => s.isNotEmpty).last);
    final total = File('${entry.path}/device/mem_info_vram_total');
    if (n == null || !await total.exists()) continue;
    final used = File('${entry.path}/device/mem_info_vram_used');
    cards.add((
      id: int.parse(n.group(1)!),
      total: (await total.readAsString()).trim(),
      used: await used.exists() ? (await used.readAsString()).trim() : null,
    ));
  }
  cards.sort((a, b) => a.id.compareTo(b.id));
  return cards;
}
