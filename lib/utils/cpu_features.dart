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

import 'dart:ffi';
import 'dart:io';

/// Whether the host x86 CPU supports the AVX2 instruction set.
///
/// This matters for the KoboldCpp backend: its standard and `nocuda` builds are
/// compiled with AVX2 and crash outright on CPUs that lack it (older/low-end
/// PCs). KoboldCpp ships a separate AVX2-free `oldpc` build for exactly those
/// machines, so [BackendManager] uses this to pick the right binary to download.
///
/// Detection is per-platform and **best-effort**: on any failure — or on
/// Apple Silicon, where the current KoboldCpp release is arm64-only and AVX2 is
/// irrelevant — it returns `true` (assume supported) so a modern machine is
/// never needlessly downgraded to the slower oldpc build. It's the missing-AVX2
/// case we must be sure about, and both detection paths report that reliably.
bool cpuHasAvx2() {
  try {
    if (Platform.isLinux) {
      // The CPU feature flags are listed space-separated on the `flags` lines
      // of /proc/cpuinfo; `avx2` appears as its own token when present.
      final info = File('/proc/cpuinfo').readAsStringSync();
      return RegExp(r'\bavx2\b').hasMatch(info);
    }
    if (Platform.isWindows) {
      // Win32: BOOL IsProcessorFeaturePresent(DWORD ProcessorFeature).
      // PF_AVX2_INSTRUCTIONS_AVAILABLE == 40. Returns non-zero when present.
      final isProcessorFeaturePresent = DynamicLibrary.open('kernel32.dll')
          .lookupFunction<Int32 Function(Uint32), int Function(int)>(
            'IsProcessorFeaturePresent',
          );
      const pfAvx2InstructionsAvailable = 40;
      return isProcessorFeaturePresent(pfAvx2InstructionsAvailable) != 0;
    }
  } catch (_) {
    // Fall through to the safe default below.
  }
  // macOS (arm64-only KoboldCpp release) and any detection failure.
  return true;
}
