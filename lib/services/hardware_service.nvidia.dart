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

/// Parsed output of `nvidia-smi --query-gpu=name,memory.total`.
/// Used internally by [HardwareService._parseNvidiaSmi] so the multi-line CSV
/// response can be consumed in one shot.
class _NvidiaSmiResult {
  final String name;
  final int vramMb;
  _NvidiaSmiResult({required this.name, required this.vramMb});
}

/// nvidia-smi: locating the binary, running it, and parsing its CSV.
/// Shared by the Windows and Linux detection passes and by the CUDA
/// driver check, all of which treat nvidia-smi as authoritative for
/// NVIDIA cards.
extension HardwareServiceNvidia on HardwareService {
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
}
