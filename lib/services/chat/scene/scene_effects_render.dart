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

/// How the stage draws the sim's numbers so the weather reads as weather
/// and not as a diagram of one: depth in the rain and the snow, a storm
/// that strikes, fog that lies on the ground and breathes, clouds with a
/// lit top. Everything here is pure arithmetic over the sim's state, so
/// the sim and its shared vectors are untouched and the web painter
/// (`web_ui/src/theme/sceneEffectsRender.ts`) follows the same recipe
/// number for number. Each alpha is a share of the paint's own ceiling;
/// the readability floor (`scene_effects_test`) is set by the thickest
/// cloud at 0.75 and the thickest fog at 0.5 of their paints, and nothing
/// here draws past either.
library;

import 'dart:math' as math;

import 'scene_effects_sim.dart';
import 'scene_rng.dart';

/// Rain draws in three depth bands by each drop's own alpha, nearest
/// thickest, longest and brightest, so the sheet has depth without one
/// more particle. Each streak is a sprite with a soft tail: the atlas is
/// [kSceneStreakSpriteHeight] tall with one column per band at
/// [kSceneStreakSpriteWidth], drawn at `len / height` scale with the head
/// at the drop, so a longer streak is also a touch wider.
const List<double> kSceneRainBandWidth = [0.7, 1.0, 1.7];
const List<double> kSceneRainBandLength = [0.65, 1.0, 1.35];
const List<double> kSceneRainBandAlpha = [0.45, 0.8, 1.0];
const double kSceneStreakSpriteHeight = 64;
const List<double> kSceneStreakSpriteWidth = [3, 4, 7];

/// Heavy rain (a storm's density and up) carries a third sheet between
/// the far one and the bands.
const double kSceneHeavyRainDensity = 0.0005;
const double kSceneMidSheetDx = 0.23;
const double kSceneMidSheetDy = 0.61;
const double kSceneMidSheetLength = 0.75;
const double kSceneMidSheetAlpha = 0.45;

/// Splashes: a near drop that lands throws a ring that spreads and fades
/// over [kSceneSplashLife] seconds, with two droplets off its crown.
const double kSceneSplashLife = 0.4;
const int kSceneSplashCap = 48;
const double kSceneSplashRingAlpha = 0.7;

/// A second, farther sheet of the same drops, offset across the stage,
/// shorter and fainter: twice the rain for the same sim.
const double kSceneFarSheetDx = 0.5;
const double kSceneFarSheetDy = 0.37;
const double kSceneFarSheetLength = 0.5;
const double kSceneFarSheetWidth = 0.6;
const double kSceneFarSheetAlpha = 0.3;

/// A near drop about to land throws a short splash along the ground.
const double kSceneSplashZone = 14;
const double kSceneSplashAlpha = 0.6;

/// Snow: the nearest band wears a soft halo; a far sheet of pinpoint
/// flakes sits behind, as for the rain.
const double kSceneSnowHaloWidth = 2.4;
const double kSceneSnowHaloAlpha = 0.16;
const double kSceneSnowFarAlpha = 0.3;

/// Clouds: a body and a smaller, lifted highlight over it. The two never
/// composite past 0.75 of the paint, the readability bound.
const double kSceneCloudBodyAlpha = 0.62;
const double kSceneCloudTopAlpha = 0.32;
const double kSceneCloudTopScale = 0.78;
const double kSceneCloudTopLift = 0.22;

/// Fog lies thickest on the ground: a band over the bottom of the stage
/// in [kSceneGroundFogStripes] steps, peaking at [kSceneGroundFogAlpha]
/// of the paint and breathing slowly with the sim's clock.
const int kSceneGroundFogStripes = 24;
const double kSceneGroundFogHeight = 0.3;
const double kSceneGroundFogAlpha = 0.35;

/// Which depth band a raindrop draws in: 0 far, 1 mid, 2 near.
int rainBand(SceneDrop d) => d.a < 0.52 ? 0 : (d.a < 0.68 ? 1 : 2);

/// The wind's gust at [time], a slow swell between 0.65 and 1.35 that
/// leans the streaks and stretches them, so the rain comes in sheets
/// rather than falling like a curtain. The sim's drift is steady; the
/// gust is in how the streak is drawn.
double rainGust(double time) =>
    1 + 0.35 * math.sin(time * 0.37) * math.sin(time * 0.11 + 1);

/// How much a storm's flash lights the rain: every streak brightens with
/// the strike, up to 1.8 times, and the paint's own ceiling still caps it.
double rainLit(double flash) => 1 + 0.8 * flashShape(flash);

/// The angle, in radians, a streak leans for the sim's [wind] under the
/// [gust]: the sprite hangs straight down and is turned about its head.
double rainLean(double wind, double gust) => -math.atan(wind * gust);

/// One splash on the ground: where it landed and when.
typedef SceneSplash = ({double x, double at});

/// Where the near rain lands. Watches the drops frame to frame: a near
/// drop whose y went back up has respawned at the top, so it landed where
/// it last was, and a splash is born there. Nothing is drawn from the
/// sim's generator, so the shared vectors hold; both surfaces run the
/// same watch, so both splash in the same places.
class SceneSplashes {
  final List<SceneSplash> live = [];
  List<double> _lastX = const [];
  List<double> _lastY = const [];

  /// Notes landings since the last call and drops splashes past their
  /// life, given the sim's [drops], its clock [time] and the [height].
  void observe(List<SceneDrop> drops, double time, double height) {
    if (_lastY.length != drops.length) {
      _lastX = [for (final d in drops) d.x];
      _lastY = [for (final d in drops) d.y];
      return;
    }
    for (var i = 0; i < drops.length; i++) {
      final d = drops[i];
      if (rainBand(d) == 2 && d.y < _lastY[i] && _lastY[i] > height * 0.5) {
        live.add((x: _lastX[i], at: time));
        if (live.length > kSceneSplashCap) live.removeAt(0);
      }
      _lastX[i] = d.x;
      _lastY[i] = d.y;
    }
    live.removeWhere((s) => time - s.at > kSceneSplashLife);
  }

  /// A splash's age as a share of its life, 0 fresh to 1 gone.
  static double progress(SceneSplash s, double time) {
    final p = (time - s.at) / kSceneSplashLife;
    return p < 0 ? 0 : (p > 1 ? 1 : p);
  }

  /// The ring's half-width at [p]: it spreads from 2 to 12 pixels.
  static double ringRadius(double p) => 2 + 10 * p;

  /// A crown droplet's height above the ground at [p]: up, then back.
  static double dropletLift(double p) => 8 * p - 10 * p * p;
}

/// How much of the ground fog's peak the stage shows at [time] seconds.
double groundFogBreath(double time) => 0.8 + 0.2 * math.sin(time * 0.35);

/// The ground fog's alpha share for stripe [i] of [kSceneGroundFogStripes],
/// top to bottom, before the breath: thicker toward the ground.
double groundFogStripeAlpha(int i) {
  final t = (i + 1) / kSceneGroundFogStripes;
  return kSceneGroundFogAlpha * t * t;
}

/// A fog blob's slow vertical bob at [time], as a share of the stage's
/// height, so the fog rolls rather than slides.
double fogBob(int i, double time) => math.sin(time * 0.25 + i * 1.7) * 0.015;

/// A cloud's slow vertical bob at [time], as a share of the stage's height.
double cloudBob(double seed, double time) =>
    math.sin(time * 0.1 + seed * math.pi * 2) * 0.01;

/// The flash's shown strength for the sim's decaying [flash]: a strike,
/// a dark beat, a second strike, then the fade, instead of one wash.
double flashShape(double flash) {
  if (flash <= 0) return 0;
  if (flash > 0.72) return 1;
  if (flash > 0.58) return 0.15;
  if (flash > 0.42) return 0.85;
  return flash / 0.42 * 0.6;
}

/// A lightning bolt as the points of its trunk and one branch, in stage
/// pixels, drawn from the scene's [seed] and the flash's place in the
/// schedule ([nextFlashAt], which the sim has already moved on to the
/// next strike when the flash fires, so it is fixed for the flash's
/// life). The same seed and schedule give the same bolt on both surfaces.
({List<math.Point<double>> trunk, List<math.Point<double>> branch}) sceneBolt(
  int seed,
  double nextFlashAt,
  double width,
  double height,
) {
  final r = Mulberry32(seed ^ (nextFlashAt * 1000).floor()).next;
  const segments = 9;
  final trunk = <math.Point<double>>[];
  var x = width * (0.15 + r() * 0.7);
  var y = -4.0;
  trunk.add(math.Point(x, y));
  final reach = height * 0.55;
  for (var i = 0; i < segments; i++) {
    y += reach / segments * (0.7 + r() * 0.6);
    x += (r() - 0.5) * width * 0.06;
    trunk.add(math.Point(x, y));
  }
  final branch = <math.Point<double>>[trunk[3]];
  var bx = trunk[3].x;
  var by = trunk[3].y;
  final side = r() < 0.5 ? -1 : 1;
  for (var i = 0; i < 4; i++) {
    by += reach / segments * (0.5 + r() * 0.5);
    bx += side * (0.2 + r() * 0.8) * width * 0.03;
    branch.add(math.Point(bx, by));
  }
  return (trunk: trunk, branch: branch);
}

/// The bolt's glow and core, as line widths and alpha shares of the flash
/// paint at full strength.
const double kSceneBoltGlowWidth = 7;
const double kSceneBoltGlowAlpha = 0.35;
const double kSceneBoltCoreWidth = 2;
const double kSceneBoltCoreAlpha = 0.95;
