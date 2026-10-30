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

/// The seed keys the web wizard posted for one member ([members] is the
/// body's `realism.members`, keyed by library id), each checked against the
/// desktop wizard's control: bond and trust −300…300, a non-empty emotion, an
/// intensity, verification with 1–5 passes and strictness, a Pace, needs
/// that exist, seven 0–100 baselines and Enjoys low hygiene. Anything
/// missing or malformed is left out, so the caller's default stands.
Map<String, dynamic> memberSeedOverrides(Object? members, String? libId) {
  final m = members is Map ? members[libId] : null;
  if (m is! Map) return const {};
  final out = <String, dynamic>{};
  void ranged(String key, int lo, int hi) {
    if (m[key] case final num v when v.isFinite) {
      out[key] = v.toInt().clamp(lo, hi);
    }
  }

  void flag(String key) {
    if (m[key] case final bool v) out[key] = v;
  }

  // Short-Term Bond, Long-Term Bond (the engine's longTermScore) and Trust
  // Level, each in its own key and on its own scale.
  ranged('affection', -300, 300);
  ranged('longTermScore', -300, 300);
  ranged('trust', -100, 100);
  if (m['emotion'] case final String e when e.trim().isNotEmpty) {
    out['emotion'] = e.trim();
  }
  if (m['emotionIntensity'] case final String i when _intensities.contains(i)) {
    out['emotionIntensity'] = i;
  }
  flag('verificationEnabled');
  ranged('verificationMaxReprocesses', 1, 5);
  ranged('verificationStrictness', 1, 5);
  if (m['needsPace'] case final String p when _paces.contains(p)) {
    out['needsPace'] = p;
  }
  if (m['needsOff'] case final List off) {
    out['needsOff'] = <String>[
      for (final n in off)
        if (n is String && _needs.contains(n)) n,
    ];
  }
  for (final need in _needs) {
    ranged('needsBaseline${need[0].toUpperCase()}${need.substring(1)}', 0, 100);
  }
  flag('enjoysLowHygiene');
  return out;
}

/// The desktop's Intensity choices for a starting emotion.
const _intensities = ['mild', 'moderate', 'strong'];

/// The desktop's needs Pace choices.
const _paces = ['sloth', 'normal', 'fast'];

/// The seven needs, as the needs seed and `needsOff` name them.
const _needs = [
  'hunger',
  'bladder',
  'energy',
  'social',
  'fun',
  'hygiene',
  'comfort',
];
