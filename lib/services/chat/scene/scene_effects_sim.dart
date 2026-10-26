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

import 'scene_effects.dart';
import 'scene_rng.dart';

/// A raindrop or a snowflake. [len] is a streak's length or a flake's radius.
class SceneDrop {
  SceneDrop(this.x, this.y, this.v, this.len, this.drift, this.a);
  double x;
  double y;

  /// Fall speed, logical pixels per second.
  final double v;
  final double len;

  /// A flake's sway phase, radians.
  double drift;

  /// Opacity under the paint's own ceiling, 0.35 to 0.85.
  final double a;
}

/// A cloud: a row of [puffs] ellipses drifting right along the top.
class SceneCloud {
  SceneCloud(
    this.x,
    this.y,
    this.w,
    this.h,
    this.v,
    this.a,
    this.puffs,
    this.seed,
  );
  double x;
  final double y;
  final double w;
  final double h;
  final double v;
  final double a;
  final int puffs;

  /// Shapes the puffs; fixed per cloud.
  final double seed;

  /// The cloud's puffs, left to right, worked out once: only [x] moves, so
  /// a puff is its offset from it, and a frame allocates nothing.
  late final List<ScenePuff> shapes = List.unmodifiable([
    for (var p = 0; p < puffs; p++) _puff(p),
  ]);

  ScenePuff _puff(int p) {
    final r = h * (0.7 + ((p * 37 + seed * 100) % 10) / 20);
    return (
      dx: (p / puffs) * w,
      y: y + math.sin(seed * 10 + p) * h * 0.3,
      rx: r * 1.6,
      ry: r,
    );
  }
}

/// A fog blob: a radial fade of radius [r] drifting right.
class SceneFogBlob {
  SceneFogBlob(this.x, this.y, this.r, this.v, this.a);
  double x;
  final double y;
  final double r;
  final double v;
  final double a;
}

/// One storm flash, for the scene sound to time its thunder by: [at] is the
/// sim's clock in seconds, [rumbleDelay] the randomised gap before the
/// rumble.
class SceneFlash {
  const SceneFlash({required this.at, required this.rumbleDelay});
  final double at;
  final double rumbleDelay;
}

/// A cloud puff: its centre's offset from the cloud's moving left edge,
/// its centre's height and its radii.
typedef ScenePuff = ({double dx, double y, double rx, double ry});

/// Snowflakes draw in three bands by size, nearest biggest and brightest,
/// so a frame is three batched draws instead of one per flake.
const List<double> kSceneSnowBandRadius = [1.57, 2.3, 3.03];
const List<double> kSceneSnowBandAlpha = [0.5, 0.7, 0.9];

/// The flash fades from 1 to 0 at this rate per second.
const double kSceneFlashDecay = 4.0;

/// The moving weather as plain numbers: drops, clouds and fog blobs
/// scattered from [seed] over a [width] by [height] stage, stepped by
/// [advance]. No engine in it, so motion is tested without Flame, and the
/// web twin (`web_ui/src/theme/sceneEffects.ts`) runs the same steps in the
/// same order from the same seed, drawing the same random numbers. Every
/// draw from the generator, respawns and the flash schedule included,
/// happens here. The same seed, surface and integer stage size give the
/// same scene; the two surfaces match only at identical integer sizes (see
/// [Mulberry32]).
class SceneEffectsSim {
  SceneEffectsSim({
    required this.spec,
    required this.seed,
    required this.width,
    required this.height,
    this.onFlash,
  }) : _rnd = Mulberry32(seed) {
    _scatter();
  }

  final SceneEffectSpec spec;
  final int seed;
  final double width;
  final double height;

  /// Called on each storm flash; the stage forwards it as a stream.
  void Function(SceneFlash flash)? onFlash;

  final Mulberry32 _rnd;
  final List<SceneDrop> drops = [];
  final List<SceneCloud> clouds = [];
  final List<SceneFogBlob> fogBlobs = [];

  /// Seconds stepped so far.
  double time = 0;

  /// The flash's strength now, 0 to 1.
  double flash = 0;

  /// When the next flash fires, on [time]'s clock.
  late double nextFlashAt;

  bool get _snow => spec.kind == SceneEffectKind.snow;

  void _scatter() {
    final r = _rnd.next;
    final w = width;
    final h = height;
    final n = spec.particlesFor(w, h);
    for (var i = 0; i < n; i++) {
      drops.add(
        SceneDrop(
          r() * w,
          r() * h,
          _snow ? 18 + r() * 22 : 420 + r() * 260,
          _snow ? 1.2 + r() * 2.2 : 10 + r() * 14,
          r() * math.pi * 2,
          0.35 + r() * 0.5,
        ),
      );
    }
    for (var i = 0; i < spec.clouds; i++) {
      clouds.add(
        SceneCloud(
          r() * w,
          10 + r() * (h * 0.28),
          w * (0.18 + r() * 0.22),
          h * (0.06 + r() * 0.06),
          6 + r() * 10,
          0.45 + r() * 0.3,
          3 + (r() * 3).floor(),
          r(),
        ),
      );
    }
    if (spec.fog) {
      for (var i = 0; i < kSceneFogBlobs; i++) {
        fogBlobs.add(
          SceneFogBlob(
            r() * w,
            h * (0.35 + r() * 0.6),
            w * (0.25 + r() * 0.25),
            4 + r() * 6,
            0.25 + r() * 0.25,
          ),
        );
      }
    }
    nextFlashAt = 2.5 + r() * 6;
  }

  /// Steps the weather [dt] seconds, clamped to 0..0.1 so a stalled frame
  /// never teleports the rain.
  void advance(double dt) {
    final step = dt < 0 ? 0.0 : (dt > 0.1 ? 0.1 : dt);
    time += step;
    for (final c in clouds) {
      c.x += c.v * step;
      if (c.x - c.w > width) c.x = -c.w;
    }
    for (final f in fogBlobs) {
      f.x += f.v * step;
      if (f.x - f.r > width) f.x = -f.r;
    }
    if (spec.kind == SceneEffectKind.rain) {
      _rain(step);
    } else if (_snow) {
      _fall(step);
    }
    if (spec.lightning && time >= nextFlashAt) {
      flash = 1;
      final rumble = 0.4 + _rnd.next() * 1.4;
      nextFlashAt = time + 7 + _rnd.next() * 12;
      onFlash?.call(SceneFlash(at: time, rumbleDelay: rumble));
    }
    final faded = flash - step * kSceneFlashDecay;
    flash = faded > 0 ? faded : 0;
  }

  void _rain(double step) {
    final wind = spec.wind;
    for (final p in drops) {
      p.y += p.v * step;
      p.x += p.v * wind * step;
      if (p.y > height) {
        p.y = -p.len;
        p.x = _rnd.next() * width;
      }
      if (p.x > width) p.x -= width;
    }
  }

  void _fall(double step) {
    for (final p in drops) {
      p.drift += step * 0.8;
      p.y += p.v * step;
      p.x += math.sin(p.drift) * 12 * step;
      if (p.y > height) {
        p.y = -4;
        p.x = _rnd.next() * width;
      }
      if (p.x < 0) {
        p.x += width;
      } else if (p.x > width) {
        p.x -= width;
      }
    }
  }

  /// Which of the three snow bands a flake draws in.
  static int snowBand(SceneDrop d) => d.len < 1.93 ? 0 : (d.len < 2.67 ? 1 : 2);
}
