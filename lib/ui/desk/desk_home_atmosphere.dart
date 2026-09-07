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

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Amber / honey / terracotta porch-light wash. Finite sparkle pop-in so
/// widget tests can [WidgetTester.pumpAndSettle].
class DeskHomeAtmosphere extends StatelessWidget {
  const DeskHomeAtmosphere({super.key, this.child});

  final Widget? child;

  static const _sparks = <(double, double, double, int)>[
    (0.07, 0.16, 16, 0),
    (0.22, 0.07, 11, 70),
    (0.41, 0.13, 14, 40),
    (0.63, 0.06, 10, 110),
    (0.82, 0.14, 18, 20),
    (0.93, 0.28, 12, 90),
    (0.12, 0.72, 13, 130),
    (0.88, 0.78, 15, 50),
    (0.54, 0.88, 11, 160),
  ];

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    final honey = AppColors.porchHoneyOf(context);
    final terra = AppColors.porchTerracottaOf(context);
    final chaos = AppColors.chaosAccentOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: _PorchSkyPainter(
            amber: amber,
            honey: honey,
            terra: terra,
            chaos: chaos,
            bg: AppColors.backgroundOf(context),
          ),
        ),
        for (final s in _sparks)
          Align(
            alignment: Alignment(s.$1 * 2 - 1, s.$2 * 2 - 1),
            child: IgnorePointer(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Duration(milliseconds: 520 + s.$4),
                curve: Curves.easeOutBack,
                builder: (context, t, child) {
                  final v = t.clamp(0.0, 1.0);
                  return Opacity(
                    opacity: v,
                    child: Transform.scale(scale: 0.4 + v * 0.8, child: child),
                  );
                },
                child: Icon(
                  Icons.auto_awesome,
                  size: s.$3,
                  color: chaos.withValues(alpha: 0.85),
                ),
              ),
            ),
          ),
        ?child,
      ],
    );
  }
}

class _PorchSkyPainter extends CustomPainter {
  const _PorchSkyPainter({
    required this.amber,
    required this.honey,
    required this.terra,
    required this.chaos,
    required this.bg,
  });

  final Color amber;
  final Color honey;
  final Color terra;
  final Color chaos;
  final Color bg;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    void orb(Offset c, double r, Color color, double a) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = color.withValues(alpha: a)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 48),
      );
    }

    orb(Offset(size.width * 0.08, size.height * 0.12), 170, amber, 0.42);
    orb(Offset(size.width * 0.92, size.height * 0.08), 150, honey, 0.34);
    orb(Offset(size.width * 0.78, size.height * 0.82), 190, terra, 0.28);
    orb(Offset(size.width * 0.18, size.height * 0.88), 130, amber, 0.22);
    orb(Offset(size.width * 0.48, size.height * 0.38), 110, chaos, 0.14);
  }

  @override
  bool shouldRepaint(covariant _PorchSkyPainter old) =>
      old.amber != amber ||
      old.honey != honey ||
      old.terra != terra ||
      old.chaos != chaos ||
      old.bg != bg;
}
