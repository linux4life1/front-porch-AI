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

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;

import 'package:front_porch_ai/services/chat/mood_physics.dart';
import 'package:front_porch_ai/services/chat/scene/scene_rng.dart';

/// The particle halo around a portrait and how each tone moves it, as
/// plain Dart: the painter in `mood_ring.dart` draws what this returns.
/// Scattered once from a fixed seed so every portrait and both surfaces
/// draw the same halo; only the time moves.

const int kMoodHaloSeed = 0x0DDBA11;
const int kMoodHaloCount = 18;

/// One particle: its angle and radius around the ring (fractions of the
/// ring radius), its size, phase and speed.
@immutable
class MoodMote {
  const MoodMote({
    required this.angle,
    required this.radius,
    required this.size,
    required this.phase,
    required this.speed,
    required this.life,
  });
  final double angle;
  final double radius;
  final double size;
  final double phase;
  final double speed;
  final double life;
}

List<MoodMote> scatterMotes([
  int seed = kMoodHaloSeed,
  int count = kMoodHaloCount,
]) {
  final r = Mulberry32(seed);
  return [
    for (var i = 0; i < count; i++)
      MoodMote(
        angle: r.next() * math.pi * 2,
        radius: 1.15 + r.next() * 0.45,
        size: 0.03 + r.next() * 0.04,
        phase: r.next() * math.pi * 2,
        speed: 0.4 + r.next() * 1.0,
        life: 0.8 + r.next() * 1.4,
      ),
  ];
}

/// Where a mote is at [time] for a tone, as a fraction offset from the ring
/// centre (x, y in ring radii) and its alpha 0 to 1. Each tone moves its
/// own way: embers rise, motes fall, sparks jitter, sparkles orbit and
/// twinkle, bokeh drifts up, arcs flash in place.
({double x, double y, double alpha}) motePosition(
  MoodMote m,
  MoodTone tone,
  double time,
) {
  final t = (time * m.speed + m.phase) % m.life / m.life;
  final fade = 1 - (t * 2 - 1).abs();
  switch (tone) {
    case MoodTone.sour:
      return (
        x: math.cos(m.angle) * m.radius + math.sin(time * 6 + m.phase) * 0.05,
        y: 0.9 - t * 1.6,
        alpha: fade,
      );
    case MoodTone.low:
      return (
        x: math.cos(m.angle) * m.radius + math.sin(time * 1.5 + m.phase) * 0.08,
        y: -0.9 + t * 1.8,
        alpha: fade * 0.6,
      );
    case MoodTone.anxious:
      final j = math.sin(time * 37 + m.phase * 11);
      final k = math.cos(time * 29 + m.phase * 7);
      return (
        x: math.cos(m.angle) * m.radius + j * 0.06,
        y: math.sin(m.angle) * m.radius + k * 0.06,
        alpha: fade,
      );
    case MoodTone.lifted:
      final a = m.angle + time * 0.9;
      return (
        x: math.cos(a) * m.radius,
        y: math.sin(a) * m.radius,
        alpha: fade * (0.5 + 0.5 * math.sin(time * 9 + m.phase * 20)),
      );
    case MoodTone.warm:
      return (
        x: math.cos(m.angle) * m.radius + math.sin(time + m.phase * 7) * 0.07,
        y: math.sin(m.angle) * m.radius - t * 0.6,
        alpha: fade * 0.5,
      );
    case MoodTone.charged:
      final on = math.sin(time * 14 + m.phase * 40) > 0.75;
      return (
        x: math.cos(m.angle) * m.radius,
        y: math.sin(m.angle) * m.radius,
        alpha: on ? 1 : 0,
      );
  }
}

/// How a tone breathes: the ring's scale and brightness at [time].
({double scale, double bright}) toneBreath(MoodTone tone, double time) {
  switch (tone) {
    case MoodTone.sour:
      final p = math.sin(time * math.pi * 2 / 0.9);
      return (scale: 1 + 0.03 * p, bright: 1 + 0.25 * (0.5 + 0.5 * p));
    case MoodTone.low:
      final p = math.sin(time * math.pi * 2 / 5);
      return (
        scale: 1 - 0.015 * (0.5 + 0.5 * p),
        bright: 1 - 0.3 * (0.5 + 0.5 * p),
      );
    case MoodTone.anxious:
      return (scale: 1, bright: 1 + 0.3 * ((time * 6).floor() % 2));
    case MoodTone.lifted:
      final p = math.sin(time * math.pi * 2 / 1.6);
      return (
        scale: 1 + 0.06 * (0.5 + 0.5 * p),
        bright: 1 + 0.4 * (0.5 + 0.5 * p),
      );
    case MoodTone.warm:
      final u = (time % 1.4) / 1.4;
      final beat = u < 0.14
          ? u / 0.14
          : u < 0.28
          ? 1 - (u - 0.14) / 0.14
          : u < 0.42
          ? (u - 0.28) / 0.14
          : u < 0.6
          ? 1 - (u - 0.42) / 0.18
          : 0.0;
      return (scale: 1 + 0.06 * beat, bright: 1 + 0.2 * beat);
    case MoodTone.charged:
      final step = (time * 6).floor() % 3;
      return (
        scale: 1,
        bright: step == 0
            ? 1
            : step == 1
            ? 1.5
            : 0.9,
      );
  }
}

/// The jitter an anxious ring wears, in ring radii.
({double dx, double dy}) toneJitter(MoodTone tone, double time) =>
    tone == MoodTone.anxious
    ? (dx: math.sin(time * 41) * 0.02, dy: math.cos(time * 37) * 0.02)
    : (dx: 0, dy: 0);
