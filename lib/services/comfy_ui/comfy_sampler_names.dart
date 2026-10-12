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

/// Known A1111-style → ComfyUI sampler name mappings, used when the stored
/// sampler (shared across backends) isn't already a ComfyUI-native name.
const Map<String, String> _samplerAliases = {
  'euler a': 'euler_ancestral',
  'euler': 'euler',
  'heun': 'heun',
  'ddim': 'ddim',
  'lcm': 'lcm',
  'uni_pc': 'uni_pc',
  'unipc': 'uni_pc',
  'dpm++ 2m': 'dpmpp_2m',
  'dpm++ 2m karras': 'dpmpp_2m',
  'dpm++ sde': 'dpmpp_sde',
  'dpm++ sde karras': 'dpmpp_sde',
  'dpm++ 2m sde': 'dpmpp_2m_sde',
  'dpm++ 2m sde karras': 'dpmpp_2m_sde',
  'dpm++ 3m sde': 'dpmpp_3m_sde',
};

/// Normalize a (possibly A1111-style) sampler name to one this ComfyUI
/// server actually offers. Pure. Preference order: already valid → known
/// alias → 'euler' → first available.
String normalizeComfySampler(String stored, List<String> available) {
  final s = stored.trim();
  if (available.contains(s)) return s;
  final alias = _samplerAliases[s.toLowerCase()];
  if (alias != null && (available.isEmpty || available.contains(alias))) {
    return alias;
  }
  if (available.contains('euler')) return 'euler';
  return available.isNotEmpty ? available.first : 'euler';
}

/// A "Karras"-flavored A1111 sampler name maps to the karras scheduler in
/// ComfyUI (the sampler and schedule are separate knobs there). Pure.
String comfySchedulerFor(String storedSampler) =>
    storedSampler.toLowerCase().contains('karras') ? 'karras' : 'normal';
