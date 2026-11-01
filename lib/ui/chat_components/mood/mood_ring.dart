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

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/chat/mood_atmosphere.dart';
import 'package:front_porch_ai/services/chat/mood_physics.dart';
import 'package:front_porch_ai/ui/theme/realism_colors.dart';
import 'mood_halo.dart';

/// What a portrait's ring paints: the mood, the bond, the trust and a need
/// in trouble, with the hues already picked for the theme.
@immutable
class MoodRingSpec {
  const MoodRingSpec({
    required this.mood,
    required this.bond,
    required this.trust,
    this.needHue,
  });

  final MoodAtmosphere mood;

  /// -100 to 100.
  final int bond;
  final int trust;

  /// The hue of a need in trouble, or null when none is.
  final Color? needHue;

  /// Nothing to paint: a neutral mood with no halo and no need in trouble.
  bool get isQuiet => !mood.isOn && bond == 0 && needHue == null;
}

/// Mood on the character around a portrait (docs/design/ambient-stage.md,
/// the Mood tenant): a rotating ring in the tone's hue that burns,
/// breathes, jitters, bounces, beats or crackles by tone, a particle halo
/// that matches, a wider glow the stronger the mood, a bond halo behind it
/// all, the ring's weight from trust, and a rim in a need's hue that
/// breathes while that need is in trouble. A new tone fires a burst. Under
/// reduce motion the ring sits still with its glow and rim: nothing moves,
/// nothing bursts. Painted with the Flutter canvas alone, never the stage.
class MoodRing extends StatefulWidget {
  const MoodRing({
    super.key,
    required this.spec,
    required this.child,
    this.animate = true,
    this.radius,
  });

  final MoodRingSpec spec;
  final Widget child;

  /// False holds every frame still (reduce motion).
  final bool animate;

  /// The corner radius of a square portrait; null draws a circle.
  final BorderRadius? radius;

  @override
  State<MoodRing> createState() => _MoodRingState();
}

class _MoodRingState extends State<MoodRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 60),
  );
  double _burstAt = -10;

  bool get _moving => widget.animate && !widget.spec.isQuiet;

  @override
  void initState() {
    super.initState();
    if (_moving) _clock.repeat();
  }

  @override
  void didUpdateWidget(MoodRing old) {
    super.didUpdateWidget(old);
    if (_moving && !_clock.isAnimating) _clock.repeat();
    if (!_moving && _clock.isAnimating) _clock.stop();
    // A new tone this turn: the burst. Held or stoked, nothing fires.
    if (widget.animate && widget.spec.mood.label != old.spec.mood.label) {
      _burstAt = _clock.value * 60;
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    if (spec.isQuiet) return widget.child;
    return AnimatedBuilder(
      animation: _clock,
      builder: (context, child) => CustomPaint(
        key: const ValueKey('mood-ring'),
        painter: _MoodRingPainter(
          spec: spec,
          time: widget.animate ? _clock.value * 60 : 0,
          burstAt: widget.animate ? _burstAt : -10,
          radius: widget.radius,
          haloColour: RealismColors.bondHaloOf(
            context,
            warm: bondHalo(spec.bond).warm,
          ),
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

class _MoodRingPainter extends CustomPainter {
  _MoodRingPainter({
    required this.spec,
    required this.time,
    required this.burstAt,
    required this.radius,
    required this.haloColour,
  });

  final MoodRingSpec spec;
  final double time;
  final double burstAt;
  final BorderRadius? radius;
  final Color haloColour;

  static final List<MoodMote> _motes = scatterMotes();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = size.shortestSide / 2;
    final mood = spec.mood;
    final tone = mood.tone;
    final a = mood.strength;
    final breath = tone == null
        ? (scale: 1.0, bright: 1.0)
        : toneBreath(tone, time);
    final jitter = tone == null ? (dx: 0.0, dy: 0.0) : toneJitter(tone, time);
    final centre = rect.center.translate(jitter.dx * r, jitter.dy * r);
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.scale(breath.scale);
    canvas.translate(-rect.center.dx, -rect.center.dy);

    // The bond halo, widest and warmest at a full bond, icy below zero.
    final halo = bondHalo(spec.bond);
    if (halo.share > 0) {
      final w = 4 + 22 * halo.share;
      _stroke(
        canvas,
        rect,
        w / 2,
        Paint()
          ..color = haloColour.withValues(alpha: 0.25 + 0.45 * halo.share)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.8),
      );
    }

    if (tone != null && a > 0) {
      final hue = RealismColors.moodToneColor(tone);
      final lit = (a * breath.bright).clamp(0.0, 1.3);
      // The glow: wider and brighter the stronger the mood.
      final glowW = 6 + 30 * a;
      _stroke(
        canvas,
        rect,
        0,
        Paint()
          ..color = hue.withValues(alpha: (0.35 * lit).clamp(0.0, 0.9))
          ..style = PaintingStyle.stroke
          ..strokeWidth = glowW
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowW * 0.6),
      );
      // The ring: a rotating sweep in the tone, its weight from trust.
      final weight = ringWeightForTrust(spec.trust);
      final ringW = switch (weight) {
        MoodRingWeight.heavy => 3.0 + 3 * a,
        MoodRingWeight.settled => 2.0 + 2 * a,
        MoodRingWeight.broken => 1.0 + a,
      };
      final sweep = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringW
        ..shader = SweepGradient(
          transform: GradientRotation(time * math.pi * 2 / 3),
          colors: [
            hue,
            // The ring's own highlight: the tone, lifted toward white.
            HSLColor.fromColor(hue).withLightness(0.85).toColor(),
            hue,
            hue.withValues(alpha: 0.25),
            hue,
          ],
          stops: const [0, 0.25, 0.5, 0.75, 1],
        ).createShader(rect);
      final ringPath = _path(rect.deflate(-ringW / 2 - 1));
      if (weight == MoodRingWeight.broken) {
        _dashed(canvas, ringPath, sweep, dash: 8, gap: 6);
      } else {
        canvas.drawPath(ringPath, sweep);
      }
      // The halo's motes.
      final motePaint = Paint()..color = hue;
      for (final m in _motes) {
        final p = motePosition(m, tone, time);
        final alpha = (p.alpha * a).clamp(0.0, 1.0);
        if (alpha <= 0) continue;
        motePaint.color = hue.withValues(alpha: alpha);
        canvas.drawCircle(
          rect.center + Offset(p.x * r, p.y * r),
          m.size * r * (tone == MoodTone.warm ? 2.5 : 1),
          motePaint,
        );
      }
      // The burst on a new tone: dots flung out over 0.7 s.
      final since = time - burstAt;
      if (since >= 0 && since < 0.7) {
        final u = since / 0.7;
        final paint = Paint()..color = hue.withValues(alpha: 1 - u);
        for (var i = 0; i < 12; i++) {
          final ang = i * math.pi / 6;
          final d = r * (1 + 1.2 * Curves.easeOut.transform(u));
          canvas.drawCircle(
            rect.center + Offset(math.cos(ang) * d, math.sin(ang) * d),
            3 * (1 - u * 0.6),
            paint,
          );
        }
      }
    }

    // A need in trouble: a rim in its hue, breathing on a four-second
    // cycle (held at its peak when still).
    final need = spec.needHue;
    if (need != null) {
      final b = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(time * math.pi / 2));
      _stroke(
        canvas,
        rect.inflate(6),
        0,
        Paint()
          ..color = need.withValues(alpha: 0.9 * b)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
    canvas.restore();
  }

  Path _path(Rect rect) {
    final radius = this.radius;
    return radius == null
        ? (Path()..addOval(rect))
        : (Path()..addRRect(radius.toRRect(rect)));
  }

  void _stroke(Canvas canvas, Rect rect, double inflate, Paint paint) =>
      canvas.drawPath(_path(rect.inflate(inflate)), paint);

  void _dashed(
    Canvas canvas,
    Path path,
    Paint paint, {
    required double dash,
    required double gap,
  }) {
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_MoodRingPainter old) =>
      old.spec != spec ||
      old.time != time ||
      old.burstAt != burstAt ||
      old.radius != radius ||
      old.haloColour != haloColour;
}
