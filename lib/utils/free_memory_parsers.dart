// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Free memory from what each system's own tools print, in MB. Each returns
// null when the text does not say.

/// `nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits`: one
/// line per card, in MiB. [gpuId] picks a card; without it, the card with
/// the most free.
int? nvidiaFreeMb(String out, {int? gpuId}) {
  final cards = [
    for (final line in out.trim().split('\n'))
      int.tryParse(RegExp(r'\d+').firstMatch(line)?.group(0) ?? ''),
  ].whereType<int>().toList();
  if (cards.isEmpty) return null;
  if (gpuId != null && gpuId >= 0 && gpuId < cards.length) return cards[gpuId];
  return cards.reduce((a, b) => a > b ? a : b);
}

/// Linux `/proc/meminfo`: MemAvailable, in kB.
int? meminfoAvailableMb(String text) {
  final kb = RegExp(
    r'^MemAvailable:\s+(\d+)',
    multiLine: true,
  ).firstMatch(text);
  return kb == null ? null : int.parse(kb.group(1)!) ~/ 1024;
}

/// macOS `vm_stat`: free, inactive, speculative and purgeable pages are what
/// a newly started program can have.
int? vmStatAvailableMb(String text) {
  final page = int.tryParse(
    RegExp(r'page size of (\d+) bytes').firstMatch(text)?.group(1) ?? '',
  );
  if (page == null) return null;
  int pages(String name) =>
      int.tryParse(
        RegExp(
              '^Pages $name:\\s+(\\d+)',
              multiLine: true,
            ).firstMatch(text)?.group(1) ??
            '',
      ) ??
      0;
  final available =
      pages('free') +
      pages('inactive') +
      pages('speculative') +
      pages('purgeable');
  return available * page ~/ (1024 * 1024);
}

/// An AMD card on Linux: the driver's `mem_info_vram_total` and
/// `mem_info_vram_used`, in bytes.
int? amdFreeMb({required String totalBytes, required String usedBytes}) {
  final total = int.tryParse(totalBytes.trim());
  final used = int.tryParse(usedBytes.trim());
  if (total == null || used == null || total <= 0) return null;
  return (total - used).clamp(0, total) ~/ (1024 * 1024);
}

/// Windows: `(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory`,
/// in kB.
int? windowsFreeMb(String out) {
  final kb = int.tryParse(out.trim());
  return kb == null ? null : kb ~/ 1024;
}
