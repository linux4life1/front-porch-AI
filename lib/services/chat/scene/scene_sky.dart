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

import 'package:flutter/material.dart' show Color, immutable;

import 'package:front_porch_ai/ui/theme/scene_palette.dart';
import '../story_clock.dart';
import 'scene_rng.dart';

/// The sky that follows the story clock (docs/design/ambient-stage.md): the
/// six period washes as keyframes blended by the minute, a sun and a moon
/// on an arc across the top of the stage, stars that come out after
/// sunset, and a horizon band at dawn and dusk. Plain Dart with no engine
/// in it; `web_ui/src/theme/sceneSky.ts` is a line-for-line port and
/// `test/fixtures/ambient/scene_sky_vectors.json` pins both to the same
/// numbers. Everything here is a function of the minute, so the sky moves
/// only when the clock does (a model call), never in real time.

/// Fixed sun and moon times for the first cut, minutes of the story day;
/// a world's seasons may bend them later.
const int kSceneSunrise = 360;
const int kSceneSunset = 1110;
const int kSceneMoonrise = 1140;
const int kSceneMoonset = 330;

/// Stars are full this long after sunset and start to fade here before dawn.
const int kSceneStarDusk = 150;
const int kSceneStarFadeFrom = 300;
const int kSceneStarFadeTo = 390;

/// How a clock jump plays: the sky sweeps from the old minute to the new
/// one over this long, forward through the day, on an animated stage.
const double kSceneSweepSeconds = 1.8;

/// The star field: scattered once from a fixed seed, the same on every
/// surface and in every chat, so the stars never jump between scenes.
const int kSceneStarSeed = 0x5EA5BED;
const int kSceneStarCount = 110;
const double kSceneStarBand = 0.72;

/// The gradient's share of the blended wash at the top of the stage, and
/// where it has faded to nothing; the flat tint below keeps the floor the
/// readability guard pins.
const double kSceneSkyTopAlpha = 0.5;
const double kSceneSkyFade = 0.55;

/// The horizon band's strength at full dawn or dusk over a dark canvas.
const double kSceneHorizonAlpha = 0.22;

/// Light mode shows the discs and stars more softly over a pale canvas.
const double kSceneSunLightScale = 0.75;
const double kSceneMoonLightScale = 0.6;
const double kSceneStarLightScale = 0.55;

/// How much of the disc shows through a condition (1 is a clear sky; thick
/// weather dims it and spreads it into a wider glow, never hides it) and
/// how many of the stars.
const Map<String, ({double disc, double stars})> kSceneSkyCover = {
  'clear': (disc: 1, stars: 1),
  'cloudy': (disc: 0.85, stars: 0.5),
  'overcast': (disc: 0.6, stars: 0.15),
  'fog': (disc: 0.55, stars: 0.1),
  'rain': (disc: 0.55, stars: 0.1),
  'storm': (disc: 0.5, stars: 0.05),
  'snow': (disc: 0.7, stars: 0.4),
};

/// One keyframe of the sky's blend: a period's wash at its representative
/// minute (`StoryClock.representativeTime`).
@immutable
class SceneSkyStop {
  const SceneSkyStop(this.at, this.color, this.alpha);
  final int at;
  final Color color;
  final double alpha;
}

/// The six stops in clock order, from the wash table and the clock.
final List<SceneSkyStop> kSceneSkyStops = [
  for (final p in StoryClock.periods)
    SceneSkyStop(
      _minuteOf(StoryClock.representativeTime(DateTime.utc(2000), p)),
      (kSceneDaypartWash[p] ?? SceneWash.none).color,
      (kSceneDaypartWash[p] ?? SceneWash.none).alpha,
    ),
];

int _minuteOf(DateTime t) => t.hour * 60 + t.minute;

/// The clock's minute of the story day, 0 to 1439.
int sceneMinuteOf(DateTime clock) => _minuteOf(clock);

double smoothstep(double t) => t * t * (3 - 2 * t);

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

/// The wash at [minute], blended between the two stops around it and
/// wrapping from night back to dawn across midnight. A zero-alpha stop
/// keeps its neighbour's hue so the blend never greys out through white.
({Color color, double alpha}) skyWashAt(
  double minute, [
  List<SceneSkyStop>? stops,
]) {
  final s = stops ?? kSceneSkyStops;
  for (var i = 0; i < s.length; i++) {
    final a = s[i];
    final b = s[(i + 1) % s.length];
    final bAt = b.at > a.at ? b.at : b.at + 1440;
    final m = minute >= a.at ? minute : minute + 1440;
    if (m >= a.at && m < bAt) {
      final t = smoothstep((m - a.at) / (bAt - a.at));
      final ac = a.alpha == 0 ? b.color : a.color;
      final bc = b.alpha == 0 ? a.color : b.color;
      return (
        color: Color.lerp(ac, bc, t)!,
        alpha: a.alpha + (b.alpha - a.alpha) * t,
      );
    }
  }
  return (color: s.first.color, alpha: s.first.alpha);
}

/// Where a disc is on its arc: [p] 0 at rise to 1 at set, [x] and [y] as
/// fractions of the stage, [alt] 0 at the horizon to 1 at the top. Null
/// while the disc is below the horizon.
typedef SceneSkyArc = ({double p, double x, double y, double alt});

SceneSkyArc? skyArcAt(double minute, {required int rise, required int set}) {
  final span = set > rise ? set - rise : set + 1440 - rise;
  final since = minute >= rise ? minute - rise : minute + 1440 - rise;
  if (since > span) return null;
  final p = since / span;
  final alt = math.sin(math.pi * p);
  return (p: p, x: 0.08 + 0.84 * p, y: 0.40 - 0.27 * alt, alt: alt);
}

/// How far out the stars are, 0 by day to 1 at night: they come out over
/// [kSceneStarDusk] minutes after sunset and go in before dawn.
double starVisibilityAt(double minute) {
  if (minute >= kSceneSunset && minute < kSceneSunset + kSceneStarDusk) {
    return smoothstep((minute - kSceneSunset) / kSceneStarDusk);
  }
  if (minute >= kSceneSunset + kSceneStarDusk || minute < kSceneStarFadeFrom) {
    return 1;
  }
  if (minute < kSceneStarFadeTo) {
    return 1 -
        smoothstep(
          (minute - kSceneStarFadeFrom) /
              (kSceneStarFadeTo - kSceneStarFadeFrom),
        );
  }
  return 0;
}

/// The horizon band's strength, 0 to 1, and whether it is dawn's (warm
/// pink) or dusk's (deep orange).
({double strength, bool dawn}) horizonGlowAt(double minute) {
  final dawn = 1 - _clamp01((minute - 380).abs() / 110);
  final dusk = 1 - _clamp01((minute - 1100).abs() / 120);
  return dawn >= dusk
      ? (strength: dawn, dawn: true)
      : (strength: dusk, dawn: false);
}

/// The moon's phase on [clock], 0 at new through 0.5 at full and back,
/// counted from the new moon of 6 January 2000 over the synodic month.
double moonPhaseFor(DateTime clock) {
  final days =
      clock.difference(DateTime.utc(2000, 1, 6, 18, 14)).inMinutes / 1440;
  final f = (days / 29.530588853) % 1;
  return f < 0 ? f + 1 : f;
}

/// One star: its place as fractions of the stage (within the top
/// [kSceneStarBand]), its radius in pixels, its resting alpha, and the
/// phase and speed of its twinkle.
@immutable
class SceneStar {
  const SceneStar({
    required this.x,
    required this.y,
    required this.size,
    required this.alpha,
    required this.phase,
    required this.speed,
  });
  final double x;
  final double y;
  final double size;
  final double alpha;
  final double phase;
  final double speed;
}

/// Scatters [count] stars from [seed], in draw order.
List<SceneStar> scatterStars(int seed, int count) {
  final r = Mulberry32(seed);
  return [
    for (var i = 0; i < count; i++)
      SceneStar(
        x: r.next(),
        y: r.next() * kSceneStarBand,
        size: 0.6 + r.next() * 1.2,
        alpha: 0.35 + r.next() * 0.55,
        phase: r.next() * math.pi * 2,
        speed: 0.6 + r.next() * 1.4,
      ),
  ];
}

/// A star's brightness at [time] seconds, 0.4 to 1 around its rest.
double starTwinkle(SceneStar s, double time) =>
    0.7 + 0.3 * math.sin(time * s.speed + s.phase);

/// The sky's inputs for one scene: the clock's minute, the moon's phase,
/// and how much the condition lets through. Value type on [SceneTokens].
@immutable
class SceneSky {
  const SceneSky({
    required this.minute,
    required this.moonPhase,
    required this.disc,
    required this.stars,
  });

  /// From the clock's minute and the condition's cover.
  factory SceneSky.resolve({
    required int minute,
    required double moonPhase,
    required String condition,
  }) {
    final cover = kSceneSkyCover[condition] ?? kSceneSkyCover['clear']!;
    return SceneSky(
      minute: minute,
      moonPhase: moonPhase,
      disc: cover.disc,
      stars: cover.stars,
    );
  }

  /// Minute of the story day, 0 to 1439.
  final int minute;

  /// 0 new, 0.5 full, back to 1.
  final double moonPhase;

  /// How much of the sun or moon shows, 0 to 1 ([kSceneSkyCover]).
  final double disc;

  /// How many of the stars show, 0 to 1.
  final double stars;

  /// What the weather veils: 0 on a clear sky, higher the thicker it is.
  double get veil => 1 - disc;

  Map<String, Object> toWire() => {
    'minute': minute,
    'moonPhase': moonPhase,
    'disc': disc,
    'stars': stars,
  };

  @override
  bool operator ==(Object other) =>
      other is SceneSky &&
      other.minute == minute &&
      other.moonPhase == moonPhase &&
      other.disc == disc &&
      other.stars == stars;

  @override
  int get hashCode => Object.hash(minute, moonPhase, disc, stars);
}

/// The minute the stage shows, which trails the clock through a sweep: a
/// jump on an animated stage plays forward through the day over
/// [kSceneSweepSeconds], and a still one snaps. Stepped by the game loop,
/// so a paused stage holds wherever it is; [time] is the twinkle's clock.
class SceneSkyMotion {
  SceneSkyMotion(int minute) : _shown = minute.toDouble(), _target = minute;

  double _shown;
  int _target;
  double _from = 0;
  double _to = 0;
  double _t = 1;

  /// Seconds the stage has animated, for the twinkle.
  double time = 0;

  /// The minute on show now, 0 up to (not including) 1440.
  double get shown => _shown % 1440;

  /// The clock's minute, where a sweep ends.
  int get target => _target;

  bool get sweeping => _t < 1;

  /// Aims at [minute]: a sweep from wherever the sky is now, or a snap.
  void retarget(int minute, {required bool sweep}) {
    if (minute == _target) return;
    _target = minute;
    if (!sweep) {
      _shown = minute.toDouble();
      _t = 1;
      return;
    }
    _from = shown;
    var delta = minute - _from;
    if (delta <= 0) delta += 1440;
    _to = _from + delta;
    _t = 0;
  }

  void advance(double dt) {
    time += dt;
    if (_t >= 1) return;
    _t = math.min(1, _t + dt / kSceneSweepSeconds);
    _shown = _t >= 1
        ? _target.toDouble()
        : _from + (_to - _from) * smoothstep(_t);
  }
}
