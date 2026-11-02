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
import 'package:flame/effects.dart';
import 'package:flame/game.dart';
import 'package:flutter/animation.dart' show Curves;

import 'package:front_porch_ai/services/chat/chaos/chance_spin.dart';
import 'package:front_porch_ai/services/chat/scene/scene_rng.dart';
import 'package:front_porch_ai/ui/theme/chance_time_palette.dart';
import 'package:front_porch_ai/ui/widgets/chance_time/chance_time.dart';
import 'chance_time_result_card.dart' show ChanceTimeRevealEffect;
import 'chance_wheel_bursts.dart';

/// The wheel's radius as the painter draws it, before the node's scale.
const double kChanceWheelBaseRadius = 137;

/// The Chance Time wheel as a Flame game, over the overlay's content.
///
/// Outcome first: [spin] takes the slot the overlay already picked and
/// plans a spin that lands on it (`chance_spin.dart`); nothing here can
/// change that. The game steps the shared sim each frame and dresses it:
/// a pointer that clicks on the pegs, bulbs that chase at wheel speed,
/// sparks off the rim while fast, a shake, pop and flash on landing, the
/// slot's emoji thrown out, then the reveal in the result's own key. Under
/// reduce motion the wheel jumps to its stop and none of that plays.
///
/// The overlay places the wheel with [layout] in the game's own pixels;
/// the game covers the overlay's content so particles can fly over the
/// card. It never takes input.
class ChanceWheelGame extends FlameGame {
  ChanceWheelGame({required this.segments, this.onLanded, this.onSettled}) {
    pauseWhenBackgrounded = false;
  }

  /// The spin has stopped on its slot (the settle is still to come).
  final VoidCallback? onLanded;

  /// The settle is over and the reveal is playing: time for the card.
  final VoidCallback? onSettled;

  /// The wheel's eight events; only their count and order matter here.
  List<String> segments;
  late final _WheelNode _node = _WheelNode(this);

  ChanceSpinSim? sim;
  ChanceTimeRevealEffect? effect;
  ChanceWheelBursts? _bursts;

  /// Reduce motion: a spin jumps straight to its stop.
  bool reduceMotion = false;

  double _centreY = kChanceWheelBaseRadius + 10;
  double _targetRadius = kChanceWheelBaseRadius;
  double _shake = 0;
  double _pop = 0;
  double _flash = 0;
  double _strobe = 0;
  double _dread = 0;
  double _glow = 0.3;
  double _bulbPhase = 0;
  bool _revealFired = false;

  /// The landed slot's pop, 1 at the stop and fading.
  double get pop => _pop;

  /// The landed slot's white flash, 1 at the stop and fading.
  double get flash => _flash;

  /// The Misfortune dim, 1 at the reveal and fading over seconds.
  double get dread => _dread;

  /// The rim glow's strength, 0.3 at rest and up with speed.
  double get glow => _glow;

  /// The bulbs' chase, in radians of rim travelled.
  double get bulbPhase => _bulbPhase;

  /// The wheel's radius on screen now.
  double get radiusNow => kChanceWheelBaseRadius * _node.scale.x;

  /// The wheel's centre on screen now.
  Vector2 get centreNow => _node.position.clone();

  /// Transparent: the overlay's own backdrop shows through.
  @override
  Color backgroundColor() => ChanceTimePalette.backdrop.withValues(alpha: 0);

  @override
  Future<void> onLoad() async {
    await add(_node);
    _place();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (!_node.isMounted) return;
    _place();
  }

  void _place() {
    _node.position = Vector2(size.x / 2, _centreY);
    _node.scale = Vector2.all(_targetRadius / kChanceWheelBaseRadius);
  }

  /// Puts the wheel's centre [centreY] pixels down the game at [radius],
  /// at once, or eased over the overlay's shrink when [animate].
  void layout({
    required double centreY,
    required double radius,
    bool animate = false,
  }) {
    _centreY = centreY;
    _targetRadius = radius;
    if (!animate || reduceMotion) {
      if (_node.isMounted) _place();
      return;
    }
    _node.add(
      MoveToEffect(
        Vector2(size.x / 2, centreY),
        EffectController(duration: 0.6, curve: Curves.easeInOut),
      ),
    );
    _node.add(
      ScaleEffect.to(
        Vector2.all(radius / kChanceWheelBaseRadius),
        EffectController(duration: 0.6, curve: Curves.easeInOut),
      ),
    );
  }

  /// Spins to [slot]. The slot is the outcome, decided by the caller.
  void spin({
    required int seed,
    required int slot,
    required ChanceTimeRevealEffect effect,
  }) {
    final plan = ChanceSpinPlan.draw(seed: seed, slot: slot);
    final s = ChanceSpinSim(plan);
    sim = s;
    this.effect = effect;
    _bursts = ChanceWheelBursts(Mulberry32(seed ^ 0x9E3779B9));
    _revealFired = false;
    if (reduceMotion) {
      s.jumpToEnd();
      onLanded?.call();
      _revealFired = true;
      onSettled?.call();
      return;
    }
    s.start();
  }

  @override
  void update(double dt) {
    super.update(dt);
    final s = sim;
    if (s == null || !s.started || reduceMotion) return;
    if (s.step(dt)) _land(s);
    final w = s.omega.abs();
    _glow = 0.3 + (w / 22).clamp(0.0, 1.0) * 0.7;
    _bulbPhase += w * dt * 1.6 + dt * 2;
    if (!s.landed && w > 7) {
      add(
        _bursts!.sparks(
          centre: centreNow,
          radius: radiusNow,
          count: min(4, (w / 6).floor()),
          omega: s.omega,
        ),
      );
    }
    _shake = max(0, _shake - dt * 3.2);
    _pop = max(0, _pop - dt * 2.2);
    _flash = max(0, _flash - dt * 2.5);
    _strobe = max(0, _strobe - dt);
    _dread = max(0, _dread - dt * 0.22);
    if (s.settled && !_revealFired) _reveal();
  }

  void _land(ChanceSpinSim s) {
    _shake = 1;
    _pop = 1;
    _flash = 1;
    final r = radiusNow;
    _node.add(
      MoveByEffect(
        Vector2(r * 0.04, r * 0.02),
        EffectController(duration: 0.04, reverseDuration: 0.04, repeatCount: 5),
      ),
    );
    final a =
        s.plan.slot * kChanceSlotAngle -
        pi / 2 +
        kChanceSlotAngle / 2 +
        s.angle;
    add(
      _bursts!.emojiFlight(
        centre: centreNow,
        radius: r,
        from: Vector2(cos(a), sin(a)) * r * 0.62,
        emoji: WheelPainter
            .slotEmojis[s.plan.slot % WheelPainter.slotEmojis.length],
      ),
    );
    onLanded?.call();
  }

  void _reveal() {
    _revealFired = true;
    final e = effect ?? ChanceTimeRevealEffect.wildCard;
    if (e == ChanceTimeRevealEffect.chaos) _strobe = 1.2;
    if (e == ChanceTimeRevealEffect.misfortune) _dread = 1;
    add(
      _bursts!.reveal(
        effect: e,
        centre: Vector2(size.x / 2, _centreY),
        radius: _targetRadius,
      ),
    );
    onSettled?.call();
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    if (_dread > 0) {
      // Misfortune: the room darkens from the edges in.
      final c = Offset(size.x / 2, _centreY);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = Gradient.radial(
            c,
            max(size.x, size.y) * 0.8,
            [
              ChanceTimePalette.dread.withValues(alpha: 0),
              ChanceTimePalette.dread.withValues(alpha: _dread * 0.75),
            ],
            [0.25, 1],
          ),
      );
    }
    if (_strobe > 0) {
      // Chaos: lightning.
      final a = (sin(_strobe * pi * 6) * 0.5 + 0.5) * min(1, _strobe) * 0.35;
      canvas.drawRect(
        rect,
        Paint()..color = ChanceTimePalette.gold.withValues(alpha: a),
      );
    }
  }
}

/// The wheel itself: glow, bulbs, the painted wheel turned by the sim, the
/// landed slot's pop and flash, the hub and the pointer. Drawn around its
/// own origin; the game places and scales it.
class _WheelNode extends PositionComponent {
  _WheelNode(this.game);

  final ChanceWheelGame game;

  @override
  void render(Canvas canvas) {
    const r = kChanceWheelBaseRadius;
    final sim = game.sim;
    final angle = sim?.angle ?? 0;
    final segments = game.segments;
    if (segments.isEmpty) return;

    // Glow: breathes with speed, red and dim under a Misfortune.
    final dread = game.dread;
    final glowA = (0.18 + game.glow * 0.45) * (1 - dread * 0.6);
    final glowColour = Color.lerp(
      ChanceTimePalette.gold,
      ChanceTimePalette.misfortune,
      dread,
    )!;
    canvas.drawCircle(
      Offset.zero,
      r * 1.35,
      Paint()
        ..shader = Gradient.radial(
          Offset.zero,
          r * (1.22 + game.glow * 0.12),
          [
            glowColour.withValues(alpha: 0),
            glowColour.withValues(alpha: glowA),
            glowColour.withValues(alpha: 0),
          ],
          [0, 0.7, 1],
        ),
    );

    // Bulbs chase at wheel speed; they die under a Misfortune.
    const bulbs = 24;
    const step = 2 * pi / bulbs;
    final lit = (game.bulbPhase / step).floor();
    final bulbOn = Paint()..color = ChanceTimePalette.goldPale;
    final bulbOff = Paint()
      ..color = ChanceTimePalette.gold.withValues(alpha: 0.25);
    final bulbGlow = Paint()
      ..color = ChanceTimePalette.gold.withValues(alpha: 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    for (var i = 0; i < bulbs; i++) {
      final on = (i - lit) % 3 == 0 && dread < 0.6;
      final a = i * step - pi / 2;
      final at = Offset(cos(a) * r * 1.085, sin(a) * r * 1.085);
      if (on) canvas.drawCircle(at, r * 0.05, bulbGlow);
      canvas.drawCircle(at, r * 0.028, on ? bulbOn : bulbOff);
    }

    // The wheel, turned.
    canvas.save();
    canvas.rotate(angle);
    canvas.translate(-r, -r);
    WheelPainter(
      segments: segments,
      colors: ChanceTimePalette.segments,
    ).paint(canvas, const Size(2 * r, 2 * r));
    canvas.restore();

    // The landed slot pops and flashes.
    if (sim != null && sim.landed && (game.pop > 0 || game.flash > 0)) {
      final start = sim.plan.slot * kChanceSlotAngle - pi / 2 + angle;
      final rr = (r - 4) * (1 + game.pop * 0.06);
      final slice = Path()
        ..moveTo(0, 0)
        ..arcTo(
          Rect.fromCircle(center: Offset.zero, radius: rr),
          start,
          kChanceSlotAngle,
          false,
        )
        ..close();
      canvas.drawPath(
        slice,
        Paint()
          ..color = ChanceTimePalette
              .segments[sim.plan.slot % ChanceTimePalette.segments.length]
              .withValues(alpha: game.pop * 0.9),
      );
      canvas.drawPath(
        slice,
        Paint()
          ..color = ChanceTimePalette.goldPale.withValues(
            alpha: game.flash * 0.7,
          ),
      );
    }

    // Hub.
    canvas.drawCircle(
      Offset.zero,
      15,
      Paint()
        ..color = ChanceTimePalette.pointerEdge
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      Offset.zero,
      14,
      Paint()
        ..shader = Gradient.radial(Offset.zero, 14, [
          ChanceTimePalette.goldPale,
          ChanceTimePalette.gold,
        ]),
    );

    // The pointer pivots at its top and bends back against the spin.
    final swing = sim == null ? 0.0 : sim.pointer * (sim.omega < 0 ? -1 : 1);
    canvas.save();
    canvas.translate(0, -(r + 10));
    canvas.rotate(swing);
    canvas.translate(-11, 0);
    PointerPainter().paint(canvas, const Size(22, 28));
    canvas.restore();
  }
}
