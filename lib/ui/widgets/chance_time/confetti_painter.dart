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

/// Falling confetti for the Chance Time "Fortune!" reveal, driven by a 0→1
/// [progress] value.
///
/// The particle field is a seeded `static final` so the same 30 pieces fall the
/// same way on every reveal — do not make it per-instance, the painter is
/// rebuilt on every animation tick.
class ConfettiPainter extends CustomPainter {
  final double progress; // 0→1

  ConfettiPainter({required this.progress});

  static final List<Confetto> _pieces = List.generate(30, (i) {
    final rng = Random(i * 13);
    return Confetto(
      x: rng.nextDouble(),
      startY: -0.2 - rng.nextDouble() * 0.4,
      color: [
        const Color(0xFF06D6A0),
        const Color(0xFFFFD166),
        const Color(0xFFFF6B9D),
        const Color(0xFF9B5DE5),
        const Color(0xFF118AB2),
      ][i % 5],
      size: 5 + rng.nextDouble() * 6,
      speed: 0.6 + rng.nextDouble() * 0.4,
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in _pieces) {
      final y = p.startY + progress * p.speed * 1.6;
      if (y < 0 || y > 1.1) continue;
      paint.color = p.color.withValues(alpha: (1 - progress).clamp(0, 1));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(p.x * size.width, y * size.height),
            width: p.size,
            height: p.size * 0.5,
          ),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(ConfettiPainter old) => old.progress != progress;
}

/// One confetti particle: horizontal position, spawn height, colour and fall
/// speed, all in unit space.
class Confetto {
  final double x, startY, size, speed;
  final Color color;
  const Confetto({
    required this.x,
    required this.startY,
    required this.color,
    required this.size,
    required this.speed,
  });
}
