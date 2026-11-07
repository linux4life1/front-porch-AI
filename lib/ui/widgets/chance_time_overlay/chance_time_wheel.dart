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
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/chance_time_palette.dart';

/// The header's height, which the overlay uses to place the wheel.
const double kChanceTimeHeaderHeight = 60;

/// The wheel's box before and after landing: it shrinks once the wheel
/// has landed to make room for the result card.
const double kChanceWheelBoxPx = 290;
const double kChanceWheelBoxLandedPx = 190;

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
          height: kChanceTimeHeaderHeight,
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

/// The room the wheel takes in the overlay's column. The wheel itself is
/// the Flame game painted over the column (`chance_wheel_game.dart`); this
/// only holds its place, and shrinks once [landed] so the result card
/// fits, over the same 600 ms the game eases the wheel down.
class ChanceTimeWheel extends StatelessWidget {
  const ChanceTimeWheel({super.key, required this.landed});

  final bool landed;

  @override
  Widget build(BuildContext context) {
    final px = landed ? kChanceWheelBoxLandedPx : kChanceWheelBoxPx;
    // Under reduce motion the wheel jumps to its stop, so its box jumps too.
    final reduce = MediaQuery.disableAnimationsOf(context);
    return AnimatedContainer(
      key: const ValueKey('chance-wheel-box'),
      duration: reduce ? Duration.zero : const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      width: px,
      height: px,
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
