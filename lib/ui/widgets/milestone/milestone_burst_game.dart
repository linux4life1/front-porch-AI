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

import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';

import 'package:front_porch_ai/services/chat/milestone_burst.dart';
import 'package:front_porch_ai/ui/theme/milestone_palette.dart';

/// Flame paints the milestone celebration on desktop (ruling 12 as amended):
/// the shared [MilestoneBurst] sim stepped on a fixed 1/60 s clock, drawn at
/// the card's width with the card's centre as origin. The web canvas paints
/// the same sim (milestoneBurstPaint.ts) — the look is the painters', the
/// motion is the sim's and is identical.
class MilestoneBurstGame extends FlameGame {
  MilestoneBurstGame({required this.burst, required this.cardWidth}) {
    pauseWhenBackgrounded = false;
  }

  final MilestoneBurst burst;

  /// The card's width in logical pixels: one sim unit.
  double cardWidth;

  /// The card's centre, as a fraction of the game's height (the card sits
  /// slightly above centre on a tall screen).
  double centreY = 0.5;

  double _acc = 0;

  @override
  Color backgroundColor() => MilestonePalette.clear;

  @override
  Future<void> onLoad() async {
    await add(_BurstNode(this));
  }

  @override
  void update(double dt) {
    super.update(dt);
    // Fixed steps: a slow frame catches up, a fast one waits — the motion
    // is the sim's, never the frame rate's.
    _acc += dt.clamp(0, 0.25);
    while (_acc >= kBurstDt && !burst.done) {
      burst.step();
      _acc -= kBurstDt;
    }
  }
}

class _BurstNode extends Component {
  _BurstNode(this.game);

  final MilestoneBurstGame game;
  final Paint _paint = Paint()..isAntiAlias = true;

  @override
  void render(Canvas canvas) {
    final w = game.cardWidth;
    final cx = game.size.x / 2;
    final cy = game.size.y * game.centreY;
    for (final p in game.burst.particles) {
      if (p.alpha <= 0) continue;
      final colour = MilestonePalette.slots[p.color].withValues(
        alpha: p.alpha.clamp(0.0, 1.0),
      );
      final x = cx + p.x * w;
      final y = cy + p.y * w;
      final s = p.size * w;
      _paint
        ..shader = null
        ..maskFilter = null
        ..color = colour;
      switch (p.shape) {
        case BurstShape.glow:
          _paint.shader = Gradient.radial(Offset(x, y), s, [
            colour,
            colour.withValues(alpha: 0),
          ]);
          canvas.drawCircle(Offset(x, y), s, _paint);
        case BurstShape.smoke:
          _paint.maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.45);
          canvas.drawCircle(Offset(x, y), s, _paint);
        case BurstShape.spark:
        case BurstShape.ember:
          _paint.maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.6);
          canvas.drawCircle(Offset(x, y), s * 1.6, _paint);
          _paint.maskFilter = null;
          canvas.drawCircle(Offset(x, y), s * 0.7, _paint);
        case BurstShape.confetti:
          canvas
            ..save()
            ..translate(x, y)
            ..rotate(p.rot)
            ..drawRect(
              Rect.fromCenter(center: Offset.zero, width: s, height: s * 0.5),
              _paint,
            )
            ..restore();
        case BurstShape.shard:
          canvas
            ..save()
            ..translate(x, y)
            ..rotate(p.rot)
            ..drawPath(
              Path()
                ..moveTo(0, -s)
                ..lineTo(s * 0.35, s * 0.6)
                ..lineTo(-s * 0.35, s * 0.6)
                ..close(),
              _paint,
            )
            ..restore();
      }
    }
  }
}
