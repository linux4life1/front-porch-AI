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

/// Whether two GPU names coming from different Windows sources describe the
/// same adapter.
///
/// `Win32_VideoController.Name` (WMI), `DriverDesc` (registry) and
/// nvidia-smi's marketing name are all spelled differently for one card, and
/// on AMD one source routinely includes the model number where another drops
/// it ("AMD Radeon(TM) 780M Graphics" vs "AMD Radeon(TM) Graphics"). Exact
/// string comparison therefore fails on exactly the hardware that most needs
/// shared-memory detection.
///
/// Compares normalized token sets and accepts a subset match, so the less
/// specific name matches the more specific one. Requires at least two shared
/// tokens, which keeps a discrete card from matching an iGPU purely because
/// both start with "AMD" — "AMD Radeon RX 7900 XTX" and "AMD Radeon(TM)
/// Graphics" stay distinct because "graphics" is absent from the former.
bool gpuNamesMatch(String a, String b) {
  final tokensA = _gpuNameTokens(a);
  final tokensB = _gpuNameTokens(b);
  if (tokensA.isEmpty || tokensB.isEmpty) return false;
  final smaller = tokensA.length <= tokensB.length ? tokensA : tokensB;
  final larger = identical(smaller, tokensA) ? tokensB : tokensA;
  // A single shared token ("amd", "intel") is not evidence of anything.
  if (smaller.length < 2) return false;
  return smaller.every(larger.contains);
}

/// Lowercase alphanumeric tokens of a GPU name, with the vendor trademark
/// noise ("(tm)", "(r)") dropped so it never counts toward a match.
Set<String> _gpuNameTokens(String name) => name
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((t) => t.isNotEmpty && t != 'tm' && t != 'r')
    .toSet();

/// Maps a GPU marketing name to one of 'Nvidia', 'AMD', 'Intel', 'Unknown'.
///
/// Recognises a broad set of substrings so very new architectures (RTX
/// 50-series "Blackwell", Intel Arc, AMD Radeon RX 7000) are still routed to
/// the right backend even before driver-level identification kicks in.
String vendorFromGpuName(String name) {
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
