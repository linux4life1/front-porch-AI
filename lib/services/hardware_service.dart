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
import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Parsed output of `nvidia-smi --query-gpu=name,memory.total`.
/// Used internally by [HardwareService._parseNvidiaSmi] so the multi-line CSV
/// response can be consumed in one shot.
class _NvidiaSmiResult {
  final String name;
  final int vramMb;
  _NvidiaSmiResult({required this.name, required this.vramMb});
}

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
  });

  @override
  String toString() =>
      '$gpuName (VRAM: ${vramMb}MB, RAM: ${ramMb}MB, Shared: $isSharedMemory, Distro: $linuxDistro) [CUDA: $hasCuda, ROCm: $hasRocm, Metal: $hasMetal]';
}

class HardwareService extends ChangeNotifier {
  HardwareInfo? _hardwareInfo;
  bool _isDetecting = false;

  HardwareInfo? get hardwareInfo => _hardwareInfo;
  bool get isDetecting => _isDetecting;

  HardwareService() {
    // Auto-detect hardware at creation so it's available everywhere,
    // not just when the settings page is opened
    detectHardware();
  }

  Future<void> detectHardware() async {
    _isDetecting = true;
    notifyListeners();

    await _checkDrivers();

    try {
      if (Platform.isWindows) {
        await _detectWindows();
      } else if (Platform.isLinux) {
        await _detectLinux();
      } else if (Platform.isMacOS) {
        await _detectMac();
      }
    } catch (e) {
      print('Hardware detection failed: $e');
    } finally {
      _isDetecting = false;
      notifyListeners();
    }
  }

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

  Future<void> _detectWindows() async {
    String gpuName = 'Unknown GPU';
    int vramMb = 0;
    String vendor = 'Unknown';

    try {
      // Method 0: nvidia-smi — authoritative source for NVIDIA cards.
      // Run this FIRST because:
      //   - Win32_VideoController.AdapterRAM is uint32 and overflows to 0 for
      //     any card with VRAM that is an exact multiple of 4 GB (8/16/24 GB).
      //   - HardwareInformation.qwMemorySize in the registry is not reliably
      //     populated for brand-new architectures (e.g. RTX 50-series
      //     "Blackwell" on early 596.x drivers).
      //   - nvidia-smi reports the marketing name + accurate VRAM in one call.
      // _runNvidiaSmi() also tries absolute paths because the NVIDIA driver
      // sometimes installs nvidia-smi only under NVSMI/ without adding it to
      // PATH — which is the most common reason an RTX 5060 Ti shows up as
      // "Unknown GPU" on a fresh Windows install.
      final smiResult = await _runNvidiaSmi([
        '--query-gpu=name,memory.total',
        '--format=csv,noheader,nounits',
      ]);
      if (smiResult != null) {
        final parsed = _parseNvidiaSmi(smiResult.stdout.toString());
        if (parsed.name.isNotEmpty && parsed.name != 'Unknown GPU') {
          gpuName = parsed.name;
        }
        if (parsed.vramMb > 0) vramMb = parsed.vramMb;
        debugPrint('[Hardware] nvidia-smi (Method 0): $gpuName, ${vramMb}MB');
      }

      // Method 1: Registry (preferred for >4GB VRAM when nvidia-smi is absent).
      // Checks HKLM\SYSTEM\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\*
      // for HardwareInformation.qwMemorySize (64-bit VRAM size).
      // Note: we extract DriverDesc even when qwMemorySize is missing — early
      // drivers for new architectures often populate the name but not the
      // 64-bit VRAM size, and we'd otherwise lose the GPU name entirely.
      if (gpuName == 'Unknown GPU' || vramMb == 0) {
        final regResult = await Process.run('powershell', [
          '-command',
          r"Get-ItemProperty 'HKLM:\SYSTEM\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\*' -ErrorAction SilentlyContinue | Select-Object DriverDesc, 'HardwareInformation.qwMemorySize' | ConvertTo-Json",
        ]);

        // Ignore exit code 1 if we get valid JSON output (PowerShell might
        // error on some registry keys but succeed on others).
        if (regResult.stdout.toString().trim().isNotEmpty) {
          try {
            var json = jsonDecode(regResult.stdout.toString());
            if (json is! List) json = [json];

            // Find the best GPU (highest VRAM). Track a separate
            // "named candidate" so we can still recover a name when no item
            // has a usable qwMemorySize.
            var bestGpu = json[0];
            var namedGpu = json[0];
            bool namedGpuSet = false;
            int maxVram = 0;

            for (var item in json) {
              // qwMemorySize is returned as a long number, sometimes string.
              // Windows PowerShell 5.1's ConvertTo-Json may also emit very
              // large values (16 GiB = 17_179_869_184 bytes) in scientific
              // notation, so handle int / double / String uniformly.
              var memSize = item['HardwareInformation.qwMemorySize'];
              int size = 0;
              if (memSize is int) {
                size = memSize;
              } else if (memSize is double) {
                size = memSize.round();
              } else if (memSize is String) {
                size =
                    int.tryParse(memSize) ??
                    double.tryParse(memSize)?.round() ??
                    0;
              }

              if (size > maxVram) {
                maxVram = size;
                bestGpu = item;
              }

              // Remember the first item that actually has a DriverDesc so we
              // can fall back to it when no item has VRAM info.
              final desc = item['DriverDesc'];
              if (!namedGpuSet && desc is String && desc.trim().isNotEmpty) {
                namedGpu = item;
                namedGpuSet = true;
              }
            }

            if (maxVram > 0) {
              if (vramMb == 0) {
                vramMb = (maxVram / (1024 * 1024)).round();
              }
              final desc = bestGpu['DriverDesc'];
              if (gpuName == 'Unknown GPU' &&
                  desc is String &&
                  desc.trim().isNotEmpty) {
                gpuName = desc;
              }
            } else if (namedGpuSet && gpuName == 'Unknown GPU') {
              // No usable VRAM in registry, but we did find a DriverDesc —
              // use it rather than leaving the user with "Unknown GPU".
              final desc = namedGpu['DriverDesc'];
              if (desc is String && desc.trim().isNotEmpty) {
                gpuName = desc;
              }
            }
            debugPrint('[Hardware] registry (Method 1): $gpuName, ${vramMb}MB');
          } catch (e) {
            print('Registry VRAM parse error: $e');
          }
        }
      }

      // Method 2: WMI (fallback if Registry failed or returned 0).
      // WARNING: Win32_VideoController.AdapterRAM is uint32 — overflows to 0
      // for GPUs with VRAM that is an exact multiple of 4GB (8GB, 16GB, 24GB).
      // On multi-GPU systems (e.g. Intel iGPU + NVIDIA dGPU), we deliberately
      // prefer discrete GPU vendors so the iGPU doesn't win the max-RAM race
      // simply because the dGPU's AdapterRAM overflowed to 0.
      if (gpuName == 'Unknown GPU' || vramMb == 0) {
        final gpuResult = await Process.run('powershell', [
          '-command',
          'Get-CimInstance Win32_VideoController | Select-Object Name, AdapterRAM, AdapterCompatibility | ConvertTo-Json',
        ]);

        if (gpuResult.exitCode == 0) {
          final output = gpuResult.stdout.toString().trim();
          if (output.isNotEmpty) {
            var json = jsonDecode(output);
            if (json is! List) json = [json];

            // First pass: look for a discrete GPU (NVIDIA/AMD) by name.
            // AdapterRAM cannot be trusted for >4GB cards.
            var topGpu = json[0];
            bool foundDiscrete = false;
            for (var item in json) {
              final name = (item['Name'] ?? '').toString();
              final v = _vendorFromName(name);
              if (v == 'Nvidia' || v == 'AMD') {
                topGpu = item;
                foundDiscrete = true;
                break;
              }
            }
            // Second pass: if no discrete GPU was found, fall back to the
            // historical behaviour of picking the highest AdapterRAM.
            if (!foundDiscrete) {
              int maxRam = 0;
              for (var item in json) {
                final raw = item['AdapterRAM'];
                final int ram = raw is int
                    ? raw
                    : (raw is String ? int.tryParse(raw) ?? 0 : 0);
                if (ram > maxRam) {
                  maxRam = ram;
                  topGpu = item;
                }
              }
            }
            if (gpuName == 'Unknown GPU') {
              final name = topGpu['Name'];
              if (name is String && name.trim().isNotEmpty) {
                gpuName = name;
              }
            }
            final adapterRam = topGpu['AdapterRAM'];
            final int adapterRamInt = adapterRam is int
                ? adapterRam
                : (adapterRam is String ? int.tryParse(adapterRam) ?? 0 : 0);
            if (adapterRamInt > 0 && vramMb == 0) {
              vramMb = (adapterRamInt / (1024 * 1024)).round();
            }
            debugPrint('[Hardware] WMI (Method 2): $gpuName, ${vramMb}MB');
          }
        }
      }

      // Method 3: nvidia-smi final sweep — fill in any blanks that registry
      // and WMI couldn't (e.g. RTX 50-series where both Microsoft APIs return
      // nothing useful). _runNvidiaSmi() tries PATH and absolute install
      // locations, so this also recovers from "nvidia-smi not in PATH".
      if (vramMb == 0 || gpuName == 'Unknown GPU' || vendor == 'Unknown') {
        final smiResult = await _runNvidiaSmi([
          '--query-gpu=name,memory.total',
          '--format=csv,noheader,nounits',
        ]);
        if (smiResult != null) {
          final parsed = _parseNvidiaSmi(smiResult.stdout.toString());
          if (gpuName == 'Unknown GPU' &&
              parsed.name.isNotEmpty &&
              parsed.name != 'Unknown GPU') {
            gpuName = parsed.name;
          }
          if (vramMb == 0 && parsed.vramMb > 0) vramMb = parsed.vramMb;
          debugPrint('[Hardware] nvidia-smi (Method 3): $gpuName, ${vramMb}MB');
        }
      }

      // Determine Vendor from Name
      vendor = _vendorFromName(gpuName);
    } catch (e) {
      print('Windows GPU detection failed: $e');
    }

    // Detect RAM
    final ramResult = await Process.run('powershell', [
      '-command',
      'Get-CimInstance Win32_ComputerSystem | Select-Object TotalPhysicalMemory | ConvertTo-Json',
    ]);

    int ramMb = 0;
    if (ramResult.exitCode == 0) {
      try {
        final json = jsonDecode(ramResult.stdout.toString());
        ramMb = ((json['TotalPhysicalMemory'] ?? 0) / (1024 * 1024)).round();
      } catch (e) {
        print('Error parsing RAM info: $e');
      }
    }

    // Detect shared memory GPUs (Intel ARC iGPU, AMD APU, etc.)
    // These GPUs dynamically borrow from system RAM and WMI only reports
    // the small dedicated portion. Query SharedSystemMemory to detect this.
    bool isSharedMemory = false;
    try {
      final sharedResult = await Process.run('powershell', [
        '-command',
        'Get-CimInstance Win32_VideoController | Select-Object Name, AdapterRAM, SharedSystemMemory | ConvertTo-Json',
      ]);
      if (sharedResult.exitCode == 0) {
        final output = sharedResult.stdout.toString().trim();
        if (output.isNotEmpty) {
          var json = jsonDecode(output);
          if (json is! List) json = [json];
          // Find the GPU that matches our detected name
          for (var item in json) {
            final name = item['Name'] ?? '';
            if (name == gpuName || gpuName == 'Unknown GPU') {
              // SharedSystemMemory / AdapterRAM are uint32 in WMI but ConvertTo-Json
              // can occasionally emit them as strings on older PowerShell — coerce.
              int toInt(dynamic v) {
                if (v is int) return v;
                if (v is String) return int.tryParse(v) ?? 0;
                if (v is double) return v.round();
                return 0;
              }

              final sharedMem = toInt(item['SharedSystemMemory']);
              final dedicatedMem = toInt(item['AdapterRAM']);
              final sharedMb = (sharedMem / (1024 * 1024)).round();
              final dedicatedMb = (dedicatedMem / (1024 * 1024)).round();
              // If shared memory is significantly larger than dedicated,
              // this is an iGPU/APU that borrows from system RAM
              if (sharedMb > dedicatedMb && sharedMb > 1024) {
                isSharedMemory = true;
                // Use dedicated + shared as the effective VRAM
                vramMb = dedicatedMb + sharedMb;
              }
              break;
            }
          }
        }
      }
    } catch (e) {
      print('Shared memory detection error: $e');
    }

    _hardwareInfo = HardwareInfo(
      gpuName: gpuName,
      vramMb: vramMb,
      ramMb: ramMb,
      vendor: vendor,
      hasCuda: _hasCuda,
      hasRocm: _hasRocm,
      hasMetal: false,
      isSharedMemory: isSharedMemory,
    );
  }

  bool _hasCuda = false;
  bool _hasRocm = false;

  /// Runs `nvidia-smi` with the given args, trying PATH first and then the
  /// common Windows install locations.
  ///
  /// Returns the [ProcessResult] when nvidia-smi exits with code 0, or `null`
  /// when the binary cannot be found or returns a non-zero exit code.
  ///
  /// Why this exists: the NVIDIA driver on Windows sometimes installs
  /// `nvidia-smi.exe` only under `C:\Program Files\NVIDIA Corporation\NVSMI\`
  /// without adding that directory to PATH. A plain `Process.run('nvidia-smi',
  /// ...)` then throws `ProcessException`, the caller's `catch (_)` swallows
  /// it, and the user is left with "Unknown GPU" even though their RTX 5060 Ti
  /// is perfectly functional. This helper recovers from that scenario.
  Future<ProcessResult?> _runNvidiaSmi(List<String> args) async {
    // 1) Try the bare command — works on Linux, macOS, and most Windows
    //    installs (System32\nvidia-smi.exe is in PATH by default).
    try {
      final result = await Process.run('nvidia-smi', args);
      if (result.exitCode == 0) return result;
      debugPrint(
        '[Hardware] nvidia-smi on PATH returned exit code '
        '${result.exitCode}: ${result.stderr}',
      );
    } catch (e) {
      debugPrint('[Hardware] nvidia-smi not on PATH: $e');
    }

    // 2) On Windows, try the well-known absolute install locations.
    if (Platform.isWindows) {
      const fallbackPaths = <String>[
        r'C:\Windows\System32\nvidia-smi.exe',
        r'C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe',
        r'C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi',
      ];
      for (final path in fallbackPaths) {
        if (!await File(path).exists()) continue;
        try {
          final result = await Process.run(path, args);
          if (result.exitCode == 0) return result;
          debugPrint(
            '[Hardware] $path returned exit code ${result.exitCode}: '
            '${result.stderr}',
          );
        } catch (e) {
          debugPrint('[Hardware] failed to run $path: $e');
        }
      }
    }
    return null;
  }

  /// Parses `nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,
  /// nounits` output into a name + VRAM-in-MB pair.
  ///
  /// Handles multi-GPU systems by picking the entry with the largest VRAM.
  /// Also tolerates older nvidia-smi versions that ignore `nounits` and emit
  /// a "MiB" / "MB" suffix after the number.
  _NvidiaSmiResult _parseNvidiaSmi(String stdout) {
    final lines = stdout.trim().split('\n');
    String bestName = 'Unknown GPU';
    int bestVram = 0;
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      // CSV split — but only on the first comma, in case the GPU name itself
      // contains a comma (rare but possible for some workstation cards).
      final commaIdx = line.indexOf(',');
      if (commaIdx < 0) continue;
      final namePart = line.substring(0, commaIdx).trim();
      final vramPart = line.substring(commaIdx + 1).trim();
      if (namePart.isEmpty) continue;

      // Strip any trailing unit suffix ("MiB", "MB", "Mib", ...) and parse.
      final vramDigits = RegExp(r'^(\d+)').firstMatch(vramPart);
      final smiVram = vramDigits == null
          ? 0
          : int.tryParse(vramDigits.group(1)!) ?? 0;

      if (smiVram > bestVram) {
        bestVram = smiVram;
        bestName = namePart;
      } else if (bestName == 'Unknown GPU' && namePart.isNotEmpty) {
        // No VRAM yet but we finally have a name — take it.
        bestName = namePart;
        if (smiVram > 0) bestVram = smiVram;
      }
    }
    return _NvidiaSmiResult(name: bestName, vramMb: bestVram);
  }

  /// Maps a GPU marketing name to one of 'Nvidia', 'AMD', 'Intel', 'Unknown'.
  ///
  /// Recognises a broad set of substrings so very new architectures (RTX
  /// 50-series "Blackwell", Intel Arc, AMD Radeon RX 7000) are still routed to
  /// the right backend even before driver-level identification kicks in.
  String _vendorFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('nvidia') ||
        lower.contains('geforce') ||
        lower.contains('quadro') ||
        lower.contains('rtx ') ||
        lower.contains('gtx ') ||
        lower.contains('tesla ')) {
      return 'Nvidia';
    }
    if (lower.contains('amd') ||
        lower.contains('radeon') ||
        lower.contains('ati ') ||
        lower.contains('firepro') ||
        lower.contains('instinct')) {
      return 'AMD';
    }
    if (lower.contains('intel') ||
        lower.contains('iris') ||
        lower.contains('uhd') ||
        lower.contains('arc ')) {
      return 'Intel';
    }
    return 'Unknown';
  }

  Future<void> _checkDrivers() async {
    _hasCuda = false;
    _hasRocm = false;

    // CUDA Check (nvidia-smi) — skip on macOS where it doesn't exist.
    // Use _runNvidiaSmi() so we still detect CUDA when the driver installed
    // nvidia-smi only under NVSMI/ (not in PATH).
    if (!Platform.isMacOS) {
      final res = await _runNvidiaSmi([]);
      if (res != null) _hasCuda = true;
    }

    // ROCm/HIP Check
    // Windows: Check if amdsysinfo or similar exists, or just defer to Vulkan availability which is standard.
    // But user asked for "ROCm files". On Windows, real ROCm is rare for consumers, they use HIP SDK.
    // We'll filter by "ROCm" if we find 'rocminfo' on Linux or 'hipinfo' on Windows.
    // Simplified: On Windows, if AMD vendor, assume "ROCm/HIP" capability is provided by driver for Kobold (Vulkan is actual backend though).
    // Let's check for 'rocminfo' on Linux.
    if (Platform.isLinux) {
      try {
        final res = await Process.run('rocminfo', []);
        if (res.exitCode == 0) _hasRocm = true;
      } catch (_) {}
    } else if (Platform.isWindows) {
      // Harder to check "ROCm" specifically on Windows without HIP SDK.
      // But we can check if the driver itself is functioning.
      // For now, if Vendor is AMD, we'll assume the files are "available" in the sense that the driver is there.
      // Or we can check for `C:\Windows\System32\amdhip64.dll` if we want to be pedantic about HIP.
      if (File(r'C:\Windows\System32\amdhip64.dll').existsSync()) {
        _hasRocm = true;
      }
    }
  }
}
