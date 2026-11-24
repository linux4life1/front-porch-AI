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

/// The milestone celebration, as plain maths (docs/design/boons-and-bogies.md
/// §7, ruling 12 as amended 2026-11-23): one deterministic particle sim that
/// Flame paints on desktop and a canvas paints on web. Its web twin is
/// `web_ui/src/theme/milestoneBurst.ts`; both are pinned to
/// `test/fixtures/growth/milestone_burst_vectors.json` (the Chance Time
/// structure: `chance_spin.dart` ↔ `chanceSpin.ts`).
///
/// Rules that keep the twins frame-for-frame identical:
/// - every particle is decided at spawn from `(kind, seed)` by one
///   [Mulberry32], drawn in a fixed order;
/// - motion is fixed 1/60 s steps of `+ − × ÷` only — trig runs once per
///   particle at spawn, so no library difference can accumulate;
/// - units are card widths, origin at the card's centre, y down — the same
///   burst at desktop and phone size.
///
/// Pure Dart (no Flutter), so `tool/gen_milestone_burst_vectors.dart` can
/// run it with `dart run`.
library;

import 'dart:math';

import 'package:front_porch_ai/services/chat/scene/scene_rng.dart';

/// One simulation step, seconds.
const double kBurstDt = 1 / 60;

/// When a Master badge stamps in (the card reads this; the sim does not).
const double kBurstBadgeAt = 0.35;

/// The celebration kinds, by the moment's wire kind.
enum BurstKind { newBoon, newBogey, masterBoon, masterBogey, overcome }

BurstKind? burstKindForWire(String wire) => switch (wire) {
  'new_boon' => BurstKind.newBoon,
  'new_bogey' => BurstKind.newBogey,
  'master_boon' => BurstKind.masterBoon,
  'master_bogey' => BurstKind.masterBogey,
  'overcome' => BurstKind.overcome,
  _ => null,
};

/// How a particle draws. The painters own the look; the sim owns motion.
enum BurstShape { glow, spark, confetti, smoke, shard, ember }

/// Palette slots, in `milestone_palette.dart` / its web twin order.
abstract final class BurstColor {
  static const int gold = 0;
  static const int goldDeep = 1;
  static const int violet = 2;
  static const int smoke = 3;
  static const int overcome = 4;
  static const int pink = 5;
  static const int blue = 6;
  static const int white = 7;
}

/// Per-shape physics: velocity kept per step, gravity (card widths/s²),
/// peak alpha, and the fade-in time.
class _ShapeRule {
  const _ShapeRule(this.drag, this.gravity, this.peak, this.fadeIn);
  final double drag;
  final double gravity;
  final double peak;
  final double fadeIn;
}

const Map<BurstShape, _ShapeRule> _rules = {
  BurstShape.glow: _ShapeRule(0.98, -0.06, 0.6, 0.18),
  BurstShape.spark: _ShapeRule(0.94, 0.6, 1.0, 0.04),
  BurstShape.confetti: _ShapeRule(0.985, 1.4, 1.0, 0.05),
  BurstShape.smoke: _ShapeRule(0.97, -0.05, 0.45, 0.2),
  BurstShape.shard: _ShapeRule(0.95, 0.9, 0.9, 0.04),
  BurstShape.ember: _ShapeRule(0.96, -0.2, 0.85, 0.08),
};

/// One particle: its fixed spawn values and its running state.
class BurstParticle {
  BurstParticle({
    required this.shape,
    required this.color,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    this.grow = 0,
    this.rot = 0,
    this.vrot = 0,
    required this.delay,
    required this.life,
  });

  final BurstShape shape;
  final int color;
  double x, y, vx, vy, size, rot;
  final double grow, vrot, delay, life;

  /// Seconds since this particle was born (negative before [delay]).
  double age = 0;

  /// 0..1, ready to paint. 0 before birth and after death.
  double alpha = 0;

  bool get alive => age >= 0 && age <= life;
}

/// The running sim for one moment.
class MilestoneBurst {
  MilestoneBurst._(this.kind, this.seed, this.particles)
    : duration = particles.fold(0, (d, p) => max(d, p.delay + p.life));

  /// Plan every particle for [kind] from [seed].
  factory MilestoneBurst.plan(BurstKind kind, int seed) {
    final rng = Mulberry32(seed);
    double r(double lo, double hi) => lo + (hi - lo) * rng.next();
    final ps = <BurstParticle>[];

    void glow(int color, double vy) => ps.add(
      BurstParticle(
        shape: BurstShape.glow,
        color: color,
        x: 0,
        y: 0,
        vx: 0,
        vy: vy,
        size: 0.5,
        grow: 0.4,
        delay: 0,
        life: 1.4,
      ),
    );

    void radial(
      BurstShape shape,
      int count,
      List<int> colors, {
      required double speedLo,
      required double speedHi,
      double radius = 0,
      double sizeLo = 0.012,
      double sizeHi = 0.022,
      double lifeLo = 0.7,
      double lifeHi = 1.2,
      double delayLo = 0,
      double delayHi = 0,
      double grow = 0,
      double spin = 0,
    }) {
      for (var i = 0; i < count; i++) {
        final a = r(0, 2 * pi);
        final speed = r(speedLo, speedHi);
        final c = cos(a), s = sin(a);
        ps.add(
          BurstParticle(
            shape: shape,
            color: colors[(rng.next() * colors.length).floor()],
            x: c * radius,
            y: s * radius,
            vx: c * speed,
            vy: s * speed,
            size: r(sizeLo, sizeHi),
            grow: grow,
            rot: r(0, 2 * pi),
            vrot: r(-spin, spin),
            delay: r(delayLo, delayHi),
            life: r(lifeLo, lifeHi),
          ),
        );
      }
    }

    void fountain(
      int count,
      List<int> colors, {
      required double delayLo,
      required double delayHi,
    }) {
      for (var i = 0; i < count; i++) {
        ps.add(
          BurstParticle(
            shape: BurstShape.confetti,
            color: colors[(rng.next() * colors.length).floor()],
            x: r(-0.5, 0.5),
            y: 0.55,
            vx: r(-0.6, 0.6),
            vy: r(-2.4, -1.4),
            size: r(0.018, 0.03),
            rot: r(0, 2 * pi),
            vrot: r(-12, 12),
            delay: r(delayLo, delayHi),
            life: r(1.6, 2.4),
          ),
        );
      }
    }

    void orbit(int count, List<int> colors) {
      for (var i = 0; i < count; i++) {
        final a = r(0, 2 * pi);
        final radius = r(0.45, 0.65);
        final speed = r(0.25, 0.45);
        final c = cos(a), s = sin(a);
        ps.add(
          BurstParticle(
            shape: BurstShape.smoke,
            color: colors[(rng.next() * colors.length).floor()],
            x: c * radius,
            y: s * radius,
            vx: -s * speed,
            vy: c * speed,
            size: r(0.12, 0.22),
            grow: 0.12,
            delay: r(0, 0.3),
            life: r(1.4, 2.2),
          ),
        );
      }
    }

    const gold = [BurstColor.gold, BurstColor.goldDeep, BurstColor.white];
    const confetti = [
      BurstColor.overcome,
      BurstColor.gold,
      BurstColor.pink,
      BurstColor.violet,
      BurstColor.blue,
    ];
    const bogey = [BurstColor.smoke, BurstColor.violet];

    switch (kind) {
      case BurstKind.newBoon:
        glow(BurstColor.gold, -0.08);
        radial(BurstShape.spark, 48, gold, speedLo: 0.9, speedHi: 1.8);
      case BurstKind.newBogey:
        radial(
          BurstShape.smoke,
          16,
          bogey,
          speedLo: 0.1,
          speedHi: 0.35,
          radius: 0.25,
          sizeLo: 0.12,
          sizeHi: 0.22,
          lifeLo: 1.4,
          lifeHi: 2.2,
          grow: 0.12,
        );
        radial(
          BurstShape.shard,
          14,
          const [BurstColor.white, BurstColor.violet],
          speedLo: 0.8,
          speedHi: 1.4,
          sizeLo: 0.02,
          sizeHi: 0.04,
          lifeLo: 0.8,
          lifeHi: 1.3,
          spin: 8,
        );
      case BurstKind.masterBoon:
        glow(BurstColor.gold, -0.08);
        fountain(84, confetti, delayLo: 0, delayHi: 0.25);
        radial(BurstShape.spark, 20, gold, speedLo: 0.9, speedHi: 1.6);
      case BurstKind.masterBogey:
        orbit(26, bogey);
        radial(
          BurstShape.ember,
          18,
          const [BurstColor.violet, BurstColor.white],
          speedLo: 0.2,
          speedHi: 0.6,
          radius: 0.3,
          sizeLo: 0.008,
          sizeHi: 0.014,
          lifeLo: 1.0,
          lifeHi: 1.8,
        );
      case BurstKind.overcome:
        radial(
          BurstShape.smoke,
          18,
          bogey,
          speedLo: 0.1,
          speedHi: 0.3,
          radius: 0.3,
          sizeLo: 0.12,
          sizeHi: 0.22,
          lifeLo: 0.8,
          lifeHi: 1.1,
          grow: 0.16,
        );
        radial(
          BurstShape.ember,
          10,
          const [BurstColor.gold],
          speedLo: 0.2,
          speedHi: 0.5,
          radius: 0.3,
          sizeLo: 0.008,
          sizeHi: 0.014,
          lifeLo: 0.7,
          lifeHi: 0.9,
        );
        fountain(
          72,
          const [BurstColor.overcome, BurstColor.gold, BurstColor.pink],
          delayLo: 0.55,
          delayHi: 0.85,
        );
    }
    final burst = MilestoneBurst._(kind, seed, ps);
    for (final p in ps) {
      p.age = -p.delay;
    }
    return burst;
  }

  final BurstKind kind;
  final int seed;
  final List<BurstParticle> particles;

  /// Seconds until the last particle dies.
  final double duration;

  /// Steps taken so far.
  int frame = 0;

  bool get done => frame * kBurstDt > duration;

  /// Advance one [kBurstDt] step.
  void step() {
    frame++;
    for (final p in particles) {
      p.age += kBurstDt;
      if (p.age < 0) continue;
      if (p.age > p.life) {
        p.alpha = 0;
        continue;
      }
      final rule = _rules[p.shape]!;
      p.vx *= rule.drag;
      p.vy = p.vy * rule.drag + rule.gravity * kBurstDt;
      p.x += p.vx * kBurstDt;
      p.y += p.vy * kBurstDt;
      p.rot += p.vrot * kBurstDt;
      p.size += p.grow * kBurstDt;
      final fadeOutFrom = p.life * 0.65;
      final inA = p.age < rule.fadeIn ? p.age / rule.fadeIn : 1.0;
      final outA = p.age > fadeOutFrom
          ? 1 - (p.age - fadeOutFrom) / (p.life - fadeOutFrom)
          : 1.0;
      p.alpha = rule.peak * min(inA, outA);
    }
  }

  /// Advance to [targetFrame] (no-op when already there or past).
  void stepTo(int targetFrame) {
    while (frame < targetFrame) {
      step();
    }
  }
}

/// The seed a moment's celebration draws from: its id, hashed — the same
/// moment replays the same burst on both surfaces.
int burstSeedFor(String momentId) => fnv1a32('milestone|$momentId');
