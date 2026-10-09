// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'hardware_service.dart';

/// Where Linux keeps what [readLinuxGpu] reads. A test lays out its own.
class LinuxGpuPaths {
  const LinuxGpuPaths({
    this.drm = '/sys/class/drm',
    this.kfdDevice = '/dev/kfd',
    this.amdgpuIds = '/usr/share/libdrm/amdgpu.ids',
  });

  /// The driver's card list (`cardN/device/vendor`, AMD memory files).
  final String drm;

  /// The device AMD's compute driver offers; ROCm runs through it.
  final String kfdDevice;

  /// libdrm's list of AMD marketing names by device and revision.
  final String amdgpuIds;
}

/// The graphics card as Linux describes it: the name, the vendor, and for
/// AMD the memory the driver reports per card. [hasKfd] is whether the
/// compute device is there at all (whether this account may open it is
/// [kfdAccessible]).
typedef LinuxGpuFacts = ({
  String name,
  String vendor,
  int vramMb,
  int cardCount,
  int? smallestCardMb,
  bool hasKfd,
});

/// Reads the card from the driver's own files, with no tool installed;
/// [lspci] (its output, when it ran) only names the card better. The vendor
/// is lspci's when it names one, else the best card the driver lists.
Future<LinuxGpuFacts> readLinuxGpu({
  String? lspci,
  LinuxGpuPaths paths = const LinuxGpuPaths(),
}) async {
  final listed = lspci == null ? null : lspciGpu(lspci);
  final cards = await _drmCardIds(paths.drm);
  var vendor = listed?.vendor ?? 'Unknown';
  if (vendor == 'Unknown') {
    for (final c in cards) {
      final v = vendorFromPciId(c.vendor);
      if (gpuVendorRank(v) > gpuVendorRank(vendor)) vendor = v;
    }
  }

  var name = listed != null && listed.vendor == vendor ? listed.name : null;
  var vramMb = 0;
  var amdCards = 0;
  int? smallestCardMb;
  if (vendor == 'AMD') {
    for (final card in await amdDrmCards(paths.drm)) {
      final cardMb = ((int.tryParse(card.total) ?? 0) / (1024 * 1024)).round();
      if (cardMb > vramMb) vramMb = cardMb;
      if (cardMb > 0) {
        amdCards++;
        if (smallestCardMb == null || cardMb < smallestCardMb) {
          smallestCardMb = cardMb;
        }
      }
    }
    final first = cards.where((c) => vendorFromPciId(c.vendor) == 'AMD');
    if (first.isNotEmpty && first.first.device != null) {
      try {
        final ids = File(paths.amdgpuIds);
        if (await ids.exists()) {
          name =
              amdgpuIdsName(
                await ids.readAsString(),
                device: first.first.device!,
                revision: first.first.revision,
              ) ??
              name;
        }
      } on FileSystemException catch (e) {
        debugPrint('[Hardware] amdgpu.ids unreadable: $e');
      }
    }
  }
  name ??= switch (vendor) {
    'AMD' => 'AMD graphics card',
    'Nvidia' => 'NVIDIA graphics card',
    'Intel' => 'Intel graphics',
    _ => 'Unknown GPU',
  };

  return (
    name: name,
    vendor: vendor,
    vramMb: vramMb,
    cardCount: amdCards > 0 ? amdCards : 1,
    smallestCardMb: smallestCardMb,
    // A character device: FileSystemEntity.type calls it notFound, while
    // File.exists answers for anything there that is not a folder.
    hasKfd: await File(paths.kfdDevice).exists(),
  );
}

/// Whether this account may open [device] for reading and writing, as ROCm
/// must. Usually the `render` group grants it.
Future<bool> kfdAccessible([String device = '/dev/kfd']) async {
  try {
    final r = await Process.run('sh', [
      '-c',
      'test -r "\$1" && test -w "\$1"',
      'sh',
      device,
    ]);
    return r.exitCode == 0;
  } on Object catch (e) {
    debugPrint('[Hardware] could not check access to $device: $e');
    return false;
  }
}

/// Each `cardN` the driver lists (each card also has a `renderDN` node,
/// which is not counted), in card order, with the ids it writes.
Future<List<({int id, String vendor, String? device, String? revision})>>
_drmCardIds(String root) async {
  final drm = Directory(root);
  if (!await drm.exists()) return const [];
  Future<String?> read(String path) async {
    final f = File(path);
    return await f.exists() ? (await f.readAsString()).trim() : null;
  }

  final cards = <({int id, String vendor, String? device, String? revision})>[];
  try {
    await for (final entry in drm.list()) {
      final n = RegExp(
        r'^card(\d+)$',
      ).firstMatch(entry.uri.pathSegments.where((s) => s.isNotEmpty).last);
      if (n == null) continue;
      final vendor = await read('${entry.path}/device/vendor');
      if (vendor == null) continue;
      cards.add((
        id: int.parse(n.group(1)!),
        vendor: vendor,
        device: await read('${entry.path}/device/device'),
        revision: await read('${entry.path}/device/revision'),
      ));
    }
  } on FileSystemException catch (e) {
    debugPrint('[Hardware] graphics card list unreadable: $e');
  }
  cards.sort((a, b) => a.id.compareTo(b.id));
  return cards;
}
