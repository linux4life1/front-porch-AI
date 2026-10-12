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
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/chance_time_palette.dart';
import 'package:front_porch_ai/ui/widgets/chance_time/chance_time.dart';

/// The glowing "CHANCE TIME!" title.
class ChanceTimeHeader extends StatelessWidget {
  const ChanceTimeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Starburst glow
        Container(
          width: 200,
          height: 60,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [
                ChanceTimePalette.gold.withValues(alpha: 0.3),
                Colors.transparent,
              ],
            ),
          ),
        ),
        const Text(
          'CHANCE TIME!',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: ChanceTimePalette.gold,
            letterSpacing: 2,
            shadows: [
              Shadow(color: ChanceTimePalette.gold, blurRadius: 20),
              Shadow(color: Colors.black, blurRadius: 4, offset: Offset(2, 2)),
            ],
          ),
        ),
      ],
    );
  }
}

/// The wheel stack: glow ring, the spinning wheel, gold hub and pointer.
/// Shrinks once the wheel has [landed] to make room for the result card.
class ChanceTimeWheel extends StatelessWidget {
  const ChanceTimeWheel({
    super.key,
    required this.segments,
    required this.spinning,
    required this.landed,
    required this.targetAngle,
    this.spinAnimation,
  });

  final List<String> segments;
  final bool spinning;
  final bool landed;
  final double targetAngle;

  /// The running spin; read only while [spinning].
  final Animation<double>? spinAnimation;

  @override
  Widget build(BuildContext context) {
    // Shrink wheel after landing to give the result card more room
    final wheelPx = landed ? 190.0 : 290.0;
    final paintPx = landed ? 174.0 : 274.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      width: wheelPx,
      height: wheelPx,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer glow ring
          AnimatedContainer(
            duration: const Duration(milliseconds: 600),
            width: wheelPx + 14,
            height: wheelPx + 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Colors.transparent,
                  ChanceTimePalette.gold.withValues(alpha: 0.25),
                ],
                stops: const [0.85, 1.0],
              ),
            ),
          ),
          // Spinning wheel
          AnimatedBuilder(
            animation: spinning
                ? spinAnimation!
                : AlwaysStoppedAnimation(landed ? targetAngle % (2 * pi) : 0),
            builder: (context, child) {
              final angle = spinning
                  ? spinAnimation!.value
                  : (landed ? targetAngle % (2 * pi) : 0.0);
              return Transform.rotate(
                angle: angle,
                child: CustomPaint(
                  size: Size(paintPx, paintPx),
                  painter: WheelPainter(
                    segments: segments,
                    colors: ChanceTimePalette.segments,
                  ),
                ),
              );
            },
          ),
          // Gold centre hub
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [ChanceTimePalette.goldPale, ChanceTimePalette.gold],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          // Pointer triangle at top
          Positioned(
            top: 0,
            child: CustomPaint(
              size: const Size(22, 28),
              painter: PointerPainter(),
            ),
          ),
        ],
      ),
    );
  }
}

/// The gold SPIN pill shown until the wheel lands.
class ChanceTimeSpinButton extends StatelessWidget {
  const ChanceTimeSpinButton({super.key, required this.onSpin});

  final VoidCallback onSpin;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSpin,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [ChanceTimePalette.gold, ChanceTimePalette.goldDeep],
          ),
          borderRadius: BorderRadius.circular(50),
          boxShadow: [
            BoxShadow(
              color: ChanceTimePalette.gold.withValues(alpha: 0.5),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Text(
          'SPIN',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: ChanceTimePalette.onGold,
            letterSpacing: 3,
          ),
        ),
      ),
    );
  }
}

/// The chaos pressure readout under the wheel, calm teal to hot red.
class ChanceTimePressureRow extends StatelessWidget {
  const ChanceTimePressureRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatService>(
      builder: (_, svc, _) {
        final pressure = svc.chaosModeService.chaosPressure;
        final color = Color.lerp(
          ChanceTimePalette.calm,
          ChanceTimePalette.misfortune,
          pressure / 100,
        )!;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.casino_rounded, color: color, size: 18),
            const SizedBox(width: 6),
            Text(
              'Chaos pressure: $pressure%',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
      },
    );
  }
}
