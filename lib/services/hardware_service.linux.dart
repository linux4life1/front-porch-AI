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

/// Linux GPU / VRAM / RAM detection (lspci, sysfs, nvidia-smi) and the
/// distro-family probe the backend downloader keys off.
extension HardwareServiceLinux on HardwareService {
  Future<void> _detectLinux() async {
    String gpuName = 'Unknown GPU';
    int vramMb = 0;
    int ramMb = 0;
    String vendor = 'Unknown';

    // Detect Linux distro
    final distro = await _detectLinuxDistro();

    // Detect RAM
    try {
      final result = await Process.run('cat', ['/proc/meminfo']);
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\n');
        for (final line in lines) {
          if (line.startsWith('MemTotal:')) {
            final parts = line.split(RegExp(r'\s+'));
            if (parts.length >= 2) {
              final kb = int.tryParse(parts[1]) ?? 0;
              ramMb = (kb / 1024).round();
            }
          }
        }
      }
    } catch (e) {
      print('Linux RAM detection error: $e');
    }

    // Detect GPU & VRAM
    // Try lspci first for name. On systems with both an iGPU (VGA compatible
    // controller) and a discrete NVIDIA card (often listed as "3D controller"
    // because NVIDIA Optimus/hybrid setups don't expose a VGA BAR), we prefer
    // the discrete GPU — the iGPU is irrelevant for LLM inference.
    try {
      final lspci = await Process.run('lspci', []);
      if (lspci.exitCode == 0) {
        final lines = lspci.stdout.toString().split('\n');
        String? vgaCandidate;
        String? threeDCandidate;
        for (final line in lines) {
          if (line.contains('VGA') || line.contains('Display controller')) {
            vgaCandidate ??= line;
          } else if (line.contains('3D controller')) {
            threeDCandidate ??= line;
          }
        }
        // Prefer the 3D controller entry when present — on hybrid laptops this
        // is the discrete NVIDIA/AMD GPU, while the VGA entry is the Intel iGPU.
        final gpuLine = threeDCandidate ?? vgaCandidate;
        if (gpuLine != null) {
          gpuName = gpuLine.substring(gpuLine.indexOf(':') + 1).trim();
          // Clean up name
          gpuName = gpuName.replaceAll(RegExp(r'\[.*?\]'), '').trim();
        }
      }
    } catch (e) {
      print('Linux GPU match error: $e');
    }

    // Determine vendor
    vendor = _vendorFromName(gpuName);

    // nvidia-smi is authoritative for NVIDIA cards — it gives both the
    // marketing name (e.g. "NVIDIA GeForce RTX 5060 Ti") and accurate VRAM,
    // which lspci cannot reliably provide for very new GPUs.
    if (vendor == 'Nvidia') {
      final smi = await _runNvidiaSmi([
        '--query-gpu=name,memory.total',
        '--format=csv,noheader,nounits',
      ]);
      if (smi != null) {
        final parsed = _parseNvidiaSmi(smi.stdout.toString());
        if (parsed.name.isNotEmpty && parsed.name != 'Unknown GPU') {
          gpuName = parsed.name;
        }
        if (parsed.vramMb > 0) vramMb = parsed.vramMb;
      }
    } else if (vendor == 'AMD') {
      // Try sysfs for AMD VRAM (amdgpu driver exposes this)
      try {
        final drmDir = Directory('/sys/class/drm');
        if (await drmDir.exists()) {
          final cards = await drmDir.list().toList();
          for (final card in cards) {
            final vramFile = File('${card.path}/device/mem_info_vram_total');
            if (await vramFile.exists()) {
              final vramBytes =
                  int.tryParse((await vramFile.readAsString()).trim()) ?? 0;
              final cardVramMb = (vramBytes / (1024 * 1024)).round();
              if (cardVramMb > vramMb) vramMb = cardVramMb;
            }
          }
        }
      } catch (e) {
        print('AMD VRAM sysfs detection error: $e');
      }
    }

    _hardwareInfo = HardwareInfo(
      gpuName: gpuName,
      vramMb: vramMb,
      ramMb: ramMb,
      vendor: vendor,
      hasCuda: _hasCuda,
      hasRocm: _hasRocm,
      hasMetal: false,
      linuxDistro: distro,
    );
  }

  /// Detects the Linux distribution family by reading /etc/os-release.
  Future<String> _detectLinuxDistro() async {
    try {
      final file = File('/etc/os-release');
      if (await file.exists()) {
        final content = await file.readAsString();
        final lines = content.split('\n');
        String id = '';
        String idLike = '';
        for (final line in lines) {
          if (line.startsWith('ID=')) {
            id = line.substring(3).replaceAll('"', '').trim().toLowerCase();
          } else if (line.startsWith('ID_LIKE=')) {
            idLike = line.substring(8).replaceAll('"', '').trim().toLowerCase();
          }
        }
        // Match distro families
        if (id == 'arch' ||
            id == 'manjaro' ||
            id == 'endeavouros' ||
            id == 'garuda' ||
            idLike.contains('arch')) {
          return 'arch';
        } else if (id == 'ubuntu' ||
            id == 'linuxmint' ||
            id == 'pop' ||
            idLike.contains('ubuntu')) {
          return 'ubuntu';
        } else if (id == 'debian' || idLike.contains('debian')) {
          return 'debian';
        } else if (id == 'fedora' || idLike.contains('fedora')) {
          return 'fedora';
        } else if (id == 'rhel' ||
            id == 'centos' ||
            id == 'rocky' ||
            id == 'almalinux' ||
            idLike.contains('rhel')) {
          return 'rhel';
        } else if (id == 'opensuse-tumbleweed' ||
            id == 'opensuse-leap' ||
            idLike.contains('suse')) {
          return 'opensuse';
        }
        return id.isNotEmpty ? id : 'unknown';
      }
    } catch (e) {
      print('Linux distro detection error: $e');
    }
    return 'unknown';
  }
}
