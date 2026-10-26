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

/// The Ambient Stage's seeded random source: mulberry32, bit for bit the
/// generator the web twin runs (`web_ui/src/theme/sceneEffects.ts`), so the
/// same seed scatters the same rain on both surfaces. All maths is 32-bit
/// unsigned with wraparound: Dart's native int is 64-bit and wraps on
/// overflow, so masking to the low 32 bits after each step is JavaScript's
/// `Math.imul` and `>>> 0`.
class Mulberry32 {
  Mulberry32(int seed) : _a = seed & _mask;

  static const int _mask = 0xFFFFFFFF;
  int _a;

  static int _imul(int a, int b) => (a * b) & _mask;

  /// The next number in [0, 1).
  double next() {
    _a = (_a + 0x6D2B79F5) & _mask;
    var t = _a;
    t = _imul(t ^ (t >> 15), t | 1);
    t = t ^ ((t + _imul(t ^ (t >> 7), t | 61)) & _mask);
    return (t ^ (t >> 14)) / 4294967296;
  }
}

/// FNV-1a, 32-bit, over [s] the way JavaScript's
/// `for (const c of s) c.charCodeAt(0)` reads it: one step per code point,
/// taking its first UTF-16 unit. Stable across runs and platforms, unlike
/// `String.hashCode`.
int fnv1a32(String s) {
  var h = 2166136261;
  for (final rune in s.runes) {
    final unit = rune > 0xFFFF ? 0xD800 + ((rune - 0x10000) >> 10) : rune;
    h = ((h ^ unit) * 16777619) & 0xFFFFFFFF;
  }
  return h;
}

/// The seed the stage scatters a scene from: the chat, the story day, the
/// part of day and the condition, the same inputs the weather engine is a
/// function of. Regen, swipe and reload draw the same sky; a new part of
/// day or a change of weather draws a new one.
int sceneSeed({
  required String sessionSeed,
  required int dayCount,
  required String daypart,
  required String condition,
}) => fnv1a32('$sessionSeed|day-$dayCount|$daypart|$condition');
