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

part of 'hardware_service.dart';

/// macOS GPU + RAM detection via `system_profiler`, including the unified
/// memory heuristic Apple Silicon needs.
extension HardwareServiceApple on HardwareService {
  Future<void> _detectMac() async {
    String gpuName = 'Unknown GPU';
    int vramMb = 0;
    int ramMb = 0;
    String vendor = 'Apple';

    try {
      final result = await Process.run('system_profiler', [
        'SPDisplaysDataType',
        'SPHardwareDataType',
        '-json',
      ]);
      if (result.exitCode == 0) {
        final json = jsonDecode(result.stdout.toString());

        // RAM
        final hardwareData = json['SPHardwareDataType'];
        if (hardwareData != null &&
            hardwareData is List &&
            hardwareData.isNotEmpty) {
          final memory = hardwareData[0]['physical_memory']; // e.g., "16 GB"
          if (memory != null && memory is String) {
            final parts = memory.split(' ');
            if (parts.length >= 2) {
              int val = int.tryParse(parts[0]) ?? 0;
              if (parts[1].toUpperCase() == 'GB') {
                ramMb = val * 1024;
              } else if (parts[1].toUpperCase() == 'MB') {
                ramMb = val;
              }
            }
          }
        }

        // GPU
        final videoData = json['SPDisplaysDataType'];
        if (videoData != null && videoData is List && videoData.isNotEmpty) {
          final gpu = videoData[0];
          gpuName = gpu['sppci_model'] ?? 'Unknown Mac GPU';
          vendor = gpu['sppci_vendor'] ?? 'Apple';

          if (gpuName.contains('Apple M')) {
            // Unified memory - VRAM is effectively RAM (minus OS overhead)
            // But for Kobold purpose, we usually treat a chunk of RAM as VRAM.
            // Let's set VRAM = RAM * 0.75 as a heuristic for unified memory
            vramMb = (ramMb * 0.75).round();
          } else {
            // Discrete GPU (older Macs)
            // Parsing "vram_total" usually string like "4 GB"
            final vramStr = gpu['spdisplays_vram'];
            if (vramStr != null) {
              final parts = vramStr.split(' ');
              if (parts.length >= 2) {
                int val = int.tryParse(parts[0]) ?? 0;
                if (parts[1].toUpperCase() == 'GB') {
                  vramMb = val * 1024;
                } else if (parts[1].toUpperCase() == 'MB') {
                  vramMb = val;
                }
              }
            }
          }
        }
      }
    } catch (e) {
      print('Mac detection error: $e');
    }

    _hardwareInfo = HardwareInfo(
      gpuName: gpuName,
      vramMb: vramMb,
      ramMb: ramMb,
      vendor: vendor,
      hasCuda: _hasCuda,
      hasRocm: _hasRocm,
      hasMetal: true, // Optimistically assume Metal on Mac
    );
  }
}
