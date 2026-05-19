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

class HardwareInfo {
  final String gpuName;
  final int vramMb;
  final int ramMb;
  final String vendor; // 'Nvidia', 'AMD', 'Intel', 'Unknown'
  final bool hasCuda;
  final bool hasRocm;
  final bool hasMetal;
  final bool isSharedMemory; // Intel ARC iGPU, AMD APU, etc.
  final String linuxDistro; // 'arch', 'ubuntu', 'debian', 'fedora', 'rhel', 'opensuse', 'unknown'

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
  String toString() => '$gpuName (VRAM: ${vramMb}MB, RAM: ${ramMb}MB, Shared: $isSharedMemory, Distro: $linuxDistro) [CUDA: $hasCuda, ROCm: $hasRocm, Metal: $hasMetal]';
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
    // Try lspci first for name
    try {
      final lspci = await Process.run('lspci', []);
      if (lspci.exitCode == 0) {
        final lines = lspci.stdout.toString().split('\n');
        for (final line in lines) {
          if (line.contains('VGA') || line.contains('3D controller') || line.contains('Display controller')) {
            gpuName = line.substring(line.indexOf(':') + 1).trim();
            // Clean up name
            gpuName = gpuName.replaceAll(RegExp(r'\[.*?\]'), '').trim();
            break; // Take first one
          }
        }
      }
    } catch (e) {
      print('Linux GPU match error: $e');
    }

    // Determine vendor
    final lowerName = gpuName.toLowerCase();
    if (lowerName.contains('nvidia')) vendor = 'Nvidia';
    else if (lowerName.contains('amd') || lowerName.contains('ati')) vendor = 'AMD';
    else if (lowerName.contains('intel')) vendor = 'Intel';

    // VRAM detection
    if (vendor == 'Nvidia') {
      try {
        final res = await Process.run('nvidia-smi', ['--query-gpu=memory.total', '--format=csv,noheader,nounits']);
        if (res.exitCode == 0) {
          vramMb = int.tryParse(res.stdout.toString().trim()) ?? 0;
        }
      } catch (_) {}
    } else if (vendor == 'AMD') {
      // Try sysfs for AMD VRAM (amdgpu driver exposes this)
      try {
        final drmDir = Directory('/sys/class/drm');
        if (await drmDir.exists()) {
          final cards = await drmDir.list().toList();
          for (final card in cards) {
            final vramFile = File('${card.path}/device/mem_info_vram_total');
            if (await vramFile.exists()) {
              final vramBytes = int.tryParse((await vramFile.readAsString()).trim()) ?? 0;
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
        if (id == 'arch' || id == 'manjaro' || id == 'endeavouros' || id == 'garuda' || idLike.contains('arch')) {
          return 'arch';
        } else if (id == 'ubuntu' || id == 'linuxmint' || id == 'pop' || idLike.contains('ubuntu')) {
          return 'ubuntu';
        } else if (id == 'debian' || idLike.contains('debian')) {
          return 'debian';
        } else if (id == 'fedora' || idLike.contains('fedora')) {
          return 'fedora';
        } else if (id == 'rhel' || id == 'centos' || id == 'rocky' || id == 'almalinux' || idLike.contains('rhel')) {
          return 'rhel';
        } else if (id == 'opensuse-tumbleweed' || id == 'opensuse-leap' || idLike.contains('suse')) {
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
      final result = await Process.run('system_profiler', ['SPDisplaysDataType', 'SPHardwareDataType', '-json']);
      if (result.exitCode == 0) {
        final json = jsonDecode(result.stdout.toString());
        
        // RAM
        final hardwareData = json['SPHardwareDataType'];
        if (hardwareData != null && hardwareData is List && hardwareData.isNotEmpty) {
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
      // Method 1: Registry (Preferred for >4GB VRAM)
      // Checks HKLM\SYSTEM\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\*
      // for HardwareInformation.qwMemorySize (64-bit VRAM size)
      final regResult = await Process.run('powershell', [
        '-command',
        r"Get-ItemProperty 'HKLM:\SYSTEM\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\*' -ErrorAction SilentlyContinue | Select-Object DriverDesc, 'HardwareInformation.qwMemorySize' | ConvertTo-Json"
      ]);

      // Ignore exit code 1 if we get valid JSON output (PowerShell might error on some registry keys but succeed on others)
      if (regResult.stdout.toString().trim().isNotEmpty) {
        try {
          var json = jsonDecode(regResult.stdout.toString());
          if (json is! List) json = [json];

          // Find the best GPU (highest VRAM)
          var bestGpu = json[0];
          int maxVram = 0;

          for (var item in json) {
             // qwMemorySize is returned as a long number, sometimes string in JSON
             var memSize = item['HardwareInformation.qwMemorySize'];
             int size = 0;
             if (memSize is int) size = memSize;
             else if (memSize is String) size = int.tryParse(memSize) ?? 0;
             
             if (size > maxVram) {
               maxVram = size;
               bestGpu = item;
             }
          }
          
          if (maxVram > 0) {
             vramMb = (maxVram / (1024 * 1024)).round();
             gpuName = bestGpu['DriverDesc'] ?? 'Unknown GPU';
          }
        } catch (e) {
          print('Registry VRAM parse error: $e');
        }
      }

      // Method 2: WMI (Fallback if Registry failed or returned 0)
      // WARNING: Win32_VideoController.AdapterRAM is uint32 — overflows to 0
      // for GPUs with VRAM that is an exact multiple of 4GB (8GB, 16GB, 24GB, etc.)
      if (vramMb == 0) {
        final gpuResult = await Process.run('powershell', [
          '-command',
          'Get-CimInstance Win32_VideoController | Select-Object Name, AdapterRAM, AdapterCompatibility | ConvertTo-Json'
        ]);

        if (gpuResult.exitCode == 0) {
          final output = gpuResult.stdout.toString().trim();
          if (output.isNotEmpty) {
            var json = jsonDecode(output);
            if (json is List) {
              var topGpu = json[0];
              int maxRam = 0;
              for (var item in json) {
                int ram = item['AdapterRAM'] ?? 0;
                if (ram > maxRam) {
                  maxRam = ram;
                  topGpu = item;
                }
              }
              json = topGpu;
            }
            if (gpuName == 'Unknown GPU') gpuName = json['Name'] ?? 'Unknown';
            final adapterRam = json['AdapterRAM'] ?? 0;
            if (adapterRam > 0) {
              vramMb = (adapterRam / (1024 * 1024)).round();
            }
          }
        }
      }

      // Method 3: nvidia-smi — always preferred for Nvidia name + VRAM.
      // Runs when: (a) VRAM is still 0 (registry + WMI both failed or overflowed),
      //        or  (b) GPU name is still unknown.
      // The RTX 50-series (Blackwell) hits the uint32 overflow at exactly 16 GB,
      // and newer drivers may not populate qwMemorySize for new architectures yet.
      // nvidia-smi is always the authoritative source for Nvidia cards.
      if (vramMb == 0 || gpuName == 'Unknown GPU') {
        try {
          final smiResult = await Process.run('nvidia-smi', [
            '--query-gpu=name,memory.total',
            '--format=csv,noheader,nounits'
          ]);
          if (smiResult.exitCode == 0) {
            final lines = smiResult.stdout.toString().trim().split('\n');
            // Pick the GPU with the most VRAM (matches what registry/WMI did)
            int bestVram = vramMb;
            String bestName = gpuName;
            for (final line in lines) {
              final parts = line.split(',').map((s) => s.trim()).toList();
              if (parts.length >= 2) {
                final smiVram = int.tryParse(parts[1]) ?? 0;
                if (smiVram > bestVram) {
                  bestVram = smiVram;
                  bestName = parts[0];
                }
                // Always take the name if we still don't have one
                if (gpuName == 'Unknown GPU' && parts[0].isNotEmpty) {
                  bestName = parts[0];
                  bestVram = smiVram > 0 ? smiVram : bestVram;
                }
              }
            }
            if (bestName != 'Unknown GPU') gpuName = bestName;
            if (bestVram > 0) vramMb = bestVram;
            debugPrint('[Hardware] nvidia-smi: $gpuName, ${vramMb}MB');
          }
        } catch (_) {
          // nvidia-smi not available — Nvidia card without drivers, fall through
        }
      }

      // Determine Vendor from Name
      final nameLower = gpuName.toLowerCase();
      if (nameLower.contains('nvidia') || nameLower.contains('geforce')) vendor = 'Nvidia';
      else if (nameLower.contains('amd') || nameLower.contains('radeon')) vendor = 'AMD';
      else if (nameLower.contains('intel') || nameLower.contains('iris') || nameLower.contains('uhd')) vendor = 'Intel';

    } catch (e) {
      print('Windows GPU detection failed: $e');
    }

    // Detect RAM
    final ramResult = await Process.run('powershell', [
      '-command',
      'Get-CimInstance Win32_ComputerSystem | Select-Object TotalPhysicalMemory | ConvertTo-Json'
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
        'Get-CimInstance Win32_VideoController | Select-Object Name, AdapterRAM, SharedSystemMemory | ConvertTo-Json'
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
              final sharedMem = (item['SharedSystemMemory'] ?? 0) as int;
              final dedicatedMem = (item['AdapterRAM'] ?? 0) as int;
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
  
  Future<void> _checkDrivers() async {
    _hasCuda = false;
    _hasRocm = false;

    // CUDA Check (nvidia-smi) — skip on macOS where it doesn't exist
    if (!Platform.isMacOS) {
      try {
        final res = await Process.run('nvidia-smi', []);
        if (res.exitCode == 0) _hasCuda = true;
      } catch (_) {}
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
