// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// What Linux's own tools and driver files say about a graphics card, read
// from their text. Each returns null (or 'Unknown') when the text does not
// say.

/// The vendor, as the app names it, of a PCI vendor id as the driver writes
/// it in `/sys/class/drm/cardN/device/vendor` (`0x1002`) or lspci prints it
/// (`1002`).
String vendorFromPciId(String id) {
  final hex = id.trim().toLowerCase().replaceFirst('0x', '');
  return switch (hex) {
    '1002' => 'AMD',
    '10de' => 'Nvidia',
    '8086' => 'Intel',
    _ => 'Unknown',
  };
}

const _vendorRank = {'Nvidia': 3, 'AMD': 2, 'Intel': 1};

/// How likely a card of [vendor] is the one that runs models: a discrete
/// NVIDIA, then AMD, then Intel's built-in graphics.
int gpuVendorRank(String vendor) => _vendorRank[vendor] ?? 0;

final _lspciClass = RegExp(
  r'(VGA compatible controller|3D controller|Display controller)'
  r'(?: \[[0-9a-f]{4}\])?:\s*',
);

/// The graphics card in `lspci` (or `lspci -nn`) output: the one most likely
/// to run models (see [gpuVendorRank]; on a tie the "3D controller", which
/// is what a hybrid laptop calls its discrete card, then the first), with a
/// display name ("AMD Radeon RX 6900 XT") and the vendor. Null when no line
/// names a graphics card.
({String name, String vendor})? lspciGpu(String output) {
  ({String name, String vendor, bool threeD})? best;
  for (final line in output.split('\n')) {
    final m = _lspciClass.firstMatch(line);
    if (m == null) continue;
    final card = _lspciCard(line.substring(m.end));
    final threeD = m.group(1) == '3D controller';
    if (best == null ||
        gpuVendorRank(card.vendor) > gpuVendorRank(best.vendor) ||
        (gpuVendorRank(card.vendor) == gpuVendorRank(best.vendor) &&
            threeD &&
            !best.threeD)) {
      best = (name: card.name, vendor: card.vendor, threeD: threeD);
    }
  }
  return best == null ? null : (name: best.name, vendor: best.vendor);
}

/// One lspci device description, after the class: "Advanced Micro Devices,
/// Inc. [AMD/ATI] Navi 21 [Radeon RX 6900 XT] (rev c0)".
({String name, String vendor}) _lspciCard(String text) {
  final ids = RegExp(r'\[([0-9a-f]{4}):[0-9a-f]{4}\]').firstMatch(text);
  var rest = text
      .replaceAll(RegExp(r'\s*\(rev [0-9a-f]+\)\s*$'), '')
      .replaceAll(RegExp(r'\s*\[[0-9a-f]{4}:[0-9a-f]{4}\]'), '')
      .trim();
  final lower = rest.toLowerCase();
  var vendor = ids == null ? 'Unknown' : vendorFromPciId(ids.group(1)!);
  if (vendor == 'Unknown') {
    vendor = lower.contains('nvidia')
        ? 'Nvidia'
        : lower.contains('advanced micro devices') ||
              lower.contains('amd/ati') ||
              lower.startsWith('ati ')
        ? 'AMD'
        : lower.contains('intel')
        ? 'Intel'
        : 'Unknown';
  }
  // The company as lspci spells it, then what is left is the chip, with the
  // marketing name in its last brackets when the id list knows one.
  rest = rest
      .replaceFirst(
        RegExp(
          r'^(NVIDIA Corporation|Advanced Micro Devices, Inc\. \[AMD/ATI\]|'
          r'Advanced Micro Devices, Inc\. \[AMD\]|Advanced Micro Devices, '
          r'Inc\.|Intel Corporation|ATI Technologies Inc)\s*',
        ),
        '',
      )
      .trim();
  final brackets = RegExp(r'\[([^\]]+)\]').allMatches(rest).toList();
  final model = brackets.isEmpty ? rest : brackets.last.group(1)!.trim();
  final short = switch (vendor) {
    'Nvidia' => 'NVIDIA',
    'Unknown' => '',
    _ => vendor,
  };
  final name =
      short.isEmpty || model.toLowerCase().startsWith(short.toLowerCase())
      ? model
      : '$short $model';
  return (name: name.isEmpty ? text.trim() : name, vendor: vendor);
}

/// The marketing name libdrm's `amdgpu.ids` gives an AMD card, from the
/// device and revision ids the driver writes (`0x73af`, `0xc0`). Lines read
/// `73AF,\tC0,\tAMD Radeon RX 6900 XT`. The revision's own line wins; any
/// line for the device stands in when the revision has none.
String? amdgpuIdsName(String ids, {required String device, String? revision}) {
  String norm(String s) => s.trim().toLowerCase().replaceFirst('0x', '');
  final dev = norm(device);
  final rev = revision == null ? null : norm(revision);
  String? anyRevision;
  for (final line in ids.split('\n')) {
    if (line.startsWith('#')) continue;
    final parts = line.split(',');
    if (parts.length < 3 || norm(parts[0]) != dev) continue;
    final name = parts.sublist(2).join(',').trim();
    if (name.isEmpty) continue;
    if (rev != null &&
        int.tryParse(norm(parts[1]), radix: 16) ==
            int.tryParse(rev, radix: 16)) {
      return name;
    }
    anyRevision ??= name;
  }
  return anyRevision;
}

/// `gfx_target_version` from a KFD topology node's `properties`, null for
/// a node that has none (the processor's own node says 0).
int? kfdGfxTargetVersion(String properties) {
  final m = RegExp(
    r'^gfx_target_version\s+(\d+)\s*$',
    multiLine: true,
  ).firstMatch(properties);
  final v = int.tryParse(m?.group(1) ?? '');
  return v == null || v <= 0 ? null : v;
}

/// The ISA name ROCm gives a KFD `gfx_target_version`: major * 10000 +
/// minor * 100 + stepping, written `gfx` + major + minor and stepping in hex
/// (ROCR-Runtime's libhsakmt.h HSA_GET_GFX_VERSION_* and its ISA table):
/// 100300 is gfx1030, 90010 is gfx90a, 110001 is gfx1101.
String? gfxFromKfdTargetVersion(int version) {
  if (version <= 0) return null;
  final major = (version ~/ 10000) % 100;
  final minor = (version ~/ 100) % 100;
  final step = version % 100;
  if (major == 0 || minor > 15 || step > 15) return null;
  return 'gfx$major${minor.toRadixString(16)}${step.toRadixString(16)}';
}
