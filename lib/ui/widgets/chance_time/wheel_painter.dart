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
import 'package:flutter/material.dart';

/// Paints the Chance Time wheel: eight coloured segments, one emoji per slot,
/// and the gold rim.
///
/// The spin rotation is applied OUTSIDE the painter (a `Transform.rotate` in
/// chance_time_overlay.dart) — that is why the emojis are drawn upright rather
/// than along their segment.
class WheelPainter extends CustomPainter {
  final List<String> segments;
  final List<Color> colors;

  // Fixed fun emojis per slot — visually interesting while spinning,
  // no text that goes upside-down. Event text revealed in result card.
  static const List<String> _slotEmojis = [
    '🎲',
    '⚡',
    '🎯',
    '🔮',
    '🎪',
    '💎',
    '🌈',
    '🎭',
  ];

  const WheelPainter({required this.segments, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final n = segments.length;
    final segmentAngle = (2 * pi) / n;
    final fillPaint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < n; i++) {
      final startAngle = i * segmentAngle - pi / 2;

      // Segment fill
      fillPaint.color = colors[i % colors.length];
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 4),
        startAngle,
        segmentAngle,
        true,
        fillPaint,
      );

      // Segment border
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 4),
        startAngle,
        segmentAngle,
        true,
        Paint()
          ..color = Colors.black45
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );

      // Emoji centered in segment — drawn horizontally (not rotated),
      // so it always faces the same direction regardless of spin angle.
      final midAngle = startAngle + segmentAngle / 2;
      final emojiRadius = radius * 0.60;
      final ex = center.dx + emojiRadius * cos(midAngle);
      final ey = center.dy + emojiRadius * sin(midAngle);

      final emoji = _slotEmojis[i % _slotEmojis.length];
      final tp = TextPainter(
        text: TextSpan(
          text: emoji,
          style: const TextStyle(fontSize: 26, height: 1),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(ex - tp.width / 2, ey - tp.height / 2));
    }

    // Gold outer rim
    canvas.drawCircle(
      center,
      radius - 2,
      Paint()
        ..color = const Color(0xFFFFD166)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6,
    );
  }

  @override
  bool shouldRepaint(covariant WheelPainter old) => old.segments != segments;
}

/// The fixed gold triangle at 12 o'clock that marks the landed segment.
class PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, size.height)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFFFD166)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}
