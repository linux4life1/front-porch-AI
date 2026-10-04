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

/// Free memory in MB: graphics memory, and system memory. Null where the
/// machine cannot say.
typedef FreeMemoryMb = ({int? graphics, int? system});

/// The machine's GPU/RAM profile as detected by HardwareService, and the
/// shape persisted to SharedPreferences between launches.
///
/// A pure data model — it lived inside hardware_service.dart, which put a
/// serializable value type in a 1,000-line service and left the service one
/// edit away from the god-file bar. Consumers keep importing it from
/// `services/hardware_service.dart` (which re-exports it) or the models
/// barrel; nothing about the JSON shape changed.
class HardwareInfo {
  final String gpuName;
  final int vramMb;
  final int ramMb;
  final String vendor; // 'Nvidia', 'AMD', 'Intel', 'Unknown'
  final bool hasCuda;
  final bool hasRocm;
  final bool hasMetal;
  final bool isSharedMemory; // Intel ARC iGPU, AMD APU, etc.
  final String
  linuxDistro; // 'arch', 'ubuntu', 'debian', 'fedora', 'rhel', 'opensuse', 'unknown'

  HardwareInfo({
    required this.gpuName,
    required this.vramMb,
    required this.ramMb,
    required this.vendor,
    this.hasCuda = false,
    this.hasRocm = false,
    this.hasMetal = false,
    this.isSharedMemory = false,
    this.linuxDistro = 'unknown',
    this.cardCount = 1,
  });

  /// Graphics cards of the detected vendor: KoboldCpp spreads a model over
  /// all of them when a preset names no card.
  final int cardCount;

  @override
  String toString() =>
      '$gpuName (VRAM: ${vramMb}MB, RAM: ${ramMb}MB, Shared: $isSharedMemory, Distro: $linuxDistro) [CUDA: $hasCuda, ROCm: $hasRocm, Metal: $hasMetal]';

  Map<String, dynamic> toJson() => {
    'gpuName': gpuName,
    'vramMb': vramMb,
    'ramMb': ramMb,
    'vendor': vendor,
    'hasCuda': hasCuda,
    'hasRocm': hasRocm,
    'hasMetal': hasMetal,
    'isSharedMemory': isSharedMemory,
    'linuxDistro': linuxDistro,
    'cardCount': cardCount,
  };

  /// Rebuilds from [toJson]. Every field is read defensively — a cache written
  /// by an older build (or a partially-written entry) degrades to defaults
  /// rather than throwing on startup.
  static HardwareInfo? fromJson(Map<String, dynamic> json) {
    final gpuName = json['gpuName'];
    if (gpuName is! String) return null;
    return HardwareInfo(
      gpuName: gpuName,
      vramMb: (json['vramMb'] as num?)?.toInt() ?? 0,
      ramMb: (json['ramMb'] as num?)?.toInt() ?? 0,
      vendor: json['vendor'] as String? ?? 'Unknown',
      hasCuda: json['hasCuda'] as bool? ?? false,
      hasRocm: json['hasRocm'] as bool? ?? false,
      hasMetal: json['hasMetal'] as bool? ?? false,
      isSharedMemory: json['isSharedMemory'] as bool? ?? false,
      linuxDistro: json['linuxDistro'] as String? ?? 'unknown',
      cardCount: (json['cardCount'] as num?)?.toInt() ?? 1,
    );
  }
}
