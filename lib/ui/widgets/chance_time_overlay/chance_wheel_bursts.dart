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

import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/particles.dart';
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;

import 'package:front_porch_ai/services/chat/scene/scene_rng.dart';
import 'package:front_porch_ai/ui/theme/chance_time_palette.dart';
import 'chance_time_result_card.dart' show ChanceTimeRevealEffect;

/// The Chance Time wheel's particles, as Flame particle systems: sparks off
/// the rim while the wheel is fast, the landed slot's emoji flying out, and
/// the reveal in each result's own key. A bad result never gets anything
/// festive: Misfortune is grey ash and nothing else.
///
/// Positions are in the game's pixels; [centre] is the wheel's centre and
/// [radius] its current radius, so a burst scales with the wheel.
class ChanceWheelBursts {
  ChanceWheelBursts(this._rng);

  final Mulberry32 _rng;

  double _r() => _rng.next();

  /// A few sparks shed off the rim, tangential to the spin.
  ParticleSystemComponent sparks({
    required Vector2 centre,
    required double radius,
    required int count,
    required double omega,
  }) {
    final dir = omega.sign;
    final speed = radius * (0.9 + omega.abs() * 0.045);
    return ParticleSystemComponent(
      position: centre,
      particle: Particle.generate(
        count: count,
        lifespan: 0.35 + _r() * 0.25,
        generator: (_) {
          final a = _r() * 2 * pi;
          final out = Vector2(cos(a), sin(a));
          final tangent = Vector2(-sin(a), cos(a)) * dir;
          return AcceleratedParticle(
            position: out * radius,
            speed: tangent * speed + out * radius * 0.5,
            acceleration: Vector2(0, radius * 1.2),
            child: CircleParticle(
              radius: radius * 0.018,
              paint: Paint()
                ..color = _r() < 0.5
                    ? ChanceTimePalette.gold
                    : ChanceTimePalette.goldPale,
            ),
          );
        },
      ),
    );
  }

  /// The landed slot's emoji, thrown up out of the wheel and tumbling.
  ParticleSystemComponent emojiFlight({
    required Vector2 centre,
    required double radius,
    required Vector2 from,
    required String emoji,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: emoji,
        style: TextStyle(fontSize: radius * 0.32, height: 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return ParticleSystemComponent(
      position: centre,
      particle: AcceleratedParticle(
        position: from,
        speed: Vector2(0, -radius * 2.6),
        acceleration: Vector2(0, radius * 2.4),
        lifespan: 1.1,
        child: RotatingParticle(
          from: 0,
          to: 3,
          child: ComputedParticle(
            renderer: (canvas, particle) {
              final alpha = (1 - particle.progress).clamp(0.0, 1.0);
              canvas.saveLayer(
                null,
                Paint()
                  ..color = ChanceTimePalette.onGold.withValues(alpha: alpha),
              );
              painter.paint(
                canvas,
                Offset(-painter.width / 2, -painter.height / 2),
              );
              canvas.restore();
            },
          ),
        ),
      ),
    );
  }

  /// The reveal for [effect]: confetti for Fortune, ash for Misfortune,
  /// a shower of sparks for Chaos (its strobe is the game's), motes
  /// orbiting the wheel for Wild Card.
  ParticleSystemComponent reveal({
    required ChanceTimeRevealEffect effect,
    required Vector2 centre,
    required double radius,
  }) => switch (effect) {
    ChanceTimeRevealEffect.fortune => _confetti(centre, radius),
    ChanceTimeRevealEffect.misfortune => _ash(centre, radius),
    ChanceTimeRevealEffect.chaos => _chaosSparks(centre, radius),
    ChanceTimeRevealEffect.wildCard => _motes(centre, radius),
  };

  ParticleSystemComponent _confetti(Vector2 centre, double radius) {
    const colours = ChanceTimePalette.confetti;
    return ParticleSystemComponent(
      position: centre,
      particle: Particle.generate(
        count: 140,
        lifespan: 2.6,
        generator: (i) {
          final a = -pi / 2 + (_r() - 0.5) * 1.6;
          final s = radius * (2 + _r() * 3.5);
          final w = radius * (0.05 + _r() * 0.05);
          final h = radius * 0.03;
          final paint = Paint()..color = colours[i % colours.length];
          return AcceleratedParticle(
            position: Vector2(0, radius * 1.3),
            speed: Vector2(cos(a), sin(a)) * s,
            acceleration: Vector2(0, radius * 3.2),
            child: RotatingParticle(
              from: _r() * 2 * pi,
              to: _r() * 2 * pi + (_r() - 0.5) * 30,
              child: ComputedParticle(
                renderer: (canvas, particle) {
                  final fade = (2 * (1 - particle.progress)).clamp(0.0, 1.0);
                  paint.color = paint.color.withValues(alpha: fade);
                  canvas.drawRect(
                    Rect.fromCenter(center: Offset.zero, width: w, height: h),
                    paint,
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  ParticleSystemComponent _ash(Vector2 centre, double radius) {
    return ParticleSystemComponent(
      position: centre,
      particle: Particle.generate(
        count: 50,
        lifespan: 3.5,
        generator: (_) {
          final paint = Paint()
            ..color = _r() < 0.2
                ? ChanceTimePalette.ashEmber
                : ChanceTimePalette.ash;
          final seed = _r() * 9;
          return AcceleratedParticle(
            position: Vector2((_r() - 0.5) * radius * 3.2, -radius * 1.8),
            speed: Vector2(0, radius * (0.25 + _r() * 0.4)),
            acceleration: Vector2(0, radius * 0.4),
            child: ComputedParticle(
              renderer: (canvas, particle) {
                final t = particle.progress;
                final drift = sin(t * 12 + seed) * radius * 0.08;
                paint.color = paint.color.withValues(
                  alpha: (0.85 * (1 - t)).clamp(0.0, 1.0),
                );
                canvas.drawCircle(
                  Offset(drift, 0),
                  radius * (0.015 + seed * 0.003),
                  paint,
                );
              },
            ),
          );
        },
      ),
    );
  }

  ParticleSystemComponent _chaosSparks(Vector2 centre, double radius) {
    return ParticleSystemComponent(
      position: centre,
      particle: Particle.generate(
        count: 60,
        lifespan: 0.9,
        generator: (i) {
          final a = _r() * 2 * pi;
          final s = radius * (2.5 + _r() * 4);
          return AcceleratedParticle(
            speed: Vector2(cos(a), sin(a)) * s,
            acceleration: Vector2(0, radius * 1.2),
            child: CircleParticle(
              radius: radius * 0.02,
              paint: Paint()
                ..color = i % 3 == 0
                    ? ChanceTimePalette.goldPale
                    : ChanceTimePalette.gold,
            ),
          );
        },
      ),
    );
  }

  ParticleSystemComponent _motes(Vector2 centre, double radius) {
    return ParticleSystemComponent(
      position: centre,
      particle: Particle.generate(
        count: 36,
        lifespan: 3,
        generator: (_) {
          final a0 = _r() * 2 * pi;
          final va = 1.2 + _r() * 1.4;
          final r0 = 1.05 + _r() * 0.3;
          final size = radius * (0.02 + _r() * 0.03);
          final paint = Paint()..color = ChanceTimePalette.wildCard;
          return ComputedParticle(
            renderer: (canvas, particle) {
              final t = particle.progress;
              final a = a0 + va * t * 3;
              final r = (r0 + 0.35 * t * 3) * radius;
              paint.color = ChanceTimePalette.wildCard.withValues(
                alpha: (0.9 * (1 - t)).clamp(0.0, 1.0),
              );
              canvas.drawCircle(Offset(cos(a) * r, sin(a) * r), size, paint);
            },
          );
        },
      ),
    );
  }
}
