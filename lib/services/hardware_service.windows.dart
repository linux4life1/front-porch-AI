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

/// Windows GPU / VRAM / RAM detection: the four-method cascade
/// (nvidia-smi, registry, WMI, nvidia-smi sweep) plus shared-memory
/// (iGPU/APU) resolution.
extension HardwareServiceWindows on HardwareService {
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

      // Resolve the vendor from the name we have so far so the Method 3 guard
      // below (vendor == 'Unknown') is actually meaningful. Without this,
      // `vendor` is still its initial 'Unknown' here (it was only assigned
      // after Method 3), so the guard was always true and the nvidia-smi sweep
      // ran on every detection — even when Method 0 had already succeeded with
      // a known NVIDIA name + VRAM — spawning a redundant process each time.
      vendor = _vendorFromName(gpuName);

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

          // SharedSystemMemory / AdapterRAM are uint32 in WMI but ConvertTo-Json
          // can occasionally emit them as strings on older PowerShell — coerce.
          int toInt(dynamic v) {
            if (v is int) return v;
            if (v is String) return int.tryParse(v) ?? 0;
            if (v is double) return v.round();
            return 0;
          }

          // Pick the adapter this machine actually renders on.
          //
          // This used to require WMI's Name to be string-equal to the name we
          // resolved earlier from the registry / nvidia-smi. Those sources
          // disagree constantly on AMD — the registry says "AMD Radeon(TM)
          // 780M Graphics" where WMI says "AMD Radeon(TM) Graphics" — so on
          // essentially every APU the match failed, isSharedMemory stayed
          // false, and vramMb stayed 0. KoboldLayerSolver turns 0 VRAM into
          // --gpulayers 0, i.e. a silent CPU-only launch: no error, just an
          // app that feels slow for no visible reason. Second half of #137.
          //
          // Now: compare normalized token sets (so the vaguer name still
          // matches the more specific one), and when nothing matches, fall
          // back to whichever adapter reports the most shared memory — the
          // APU signature. The fallback is gated on us having no VRAM figure
          // yet (or no GPU name at all), so on a laptop with both an iGPU and
          // a discrete card the iGPU's shared pool can never overwrite the
          // discrete card's real VRAM.
          Map<String, dynamic>? matched;
          Map<String, dynamic>? mostShared;
          int mostSharedMb = -1;

          for (final item in json) {
            if (item is! Map<String, dynamic>) continue;
            final name = (item['Name'] ?? '').toString();
            if (matched == null &&
                HardwareService.gpuNamesMatch(name, gpuName)) {
              matched = item;
              continue;
            }
            final sharedMb = (toInt(item['SharedSystemMemory']) / (1024 * 1024))
                .round();
            if (sharedMb > mostSharedMb) {
              mostSharedMb = sharedMb;
              mostShared = item;
            }
          }

          final canFallBack = vramMb == 0 || gpuName == 'Unknown GPU';
          final chosen = matched ?? (canFallBack ? mostShared : null);

          if (chosen != null) {
            final sharedMb =
                (toInt(chosen['SharedSystemMemory']) / (1024 * 1024)).round();
            final dedicatedMb = (toInt(chosen['AdapterRAM']) / (1024 * 1024))
                .round();
            // If shared memory is significantly larger than dedicated,
            // this is an iGPU/APU that borrows from system RAM
            if (sharedMb > dedicatedMb && sharedMb > 1024) {
              isSharedMemory = true;
              // Use dedicated + shared as the effective VRAM
              vramMb = dedicatedMb + sharedMb;
            }
            debugPrint(
              '[Hardware] shared-memory adapter: ${chosen['Name']} '
              '(matched: ${matched != null}, shared: ${sharedMb}MB, '
              'dedicated: ${dedicatedMb}MB) -> vram ${vramMb}MB, '
              'isShared $isSharedMemory',
            );
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
}
