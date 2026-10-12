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
import 'package:front_porch_ai/services/chat/chat.dart' show ChaosCategory;
import 'package:front_porch_ai/ui/theme/chance_time_palette.dart';
import 'package:front_porch_ai/ui/widgets/chance_time/chance_time.dart';

/// The reveal animation a landed category plays. The wheel has four; newer
/// [ChaosCategory] kinds borrow the closest one while keeping their own label.
enum ChanceTimeRevealEffect { fortune, misfortune, chaos, wildCard }

/// What the wheel landed on: reveal splash, category banner, the event text
/// and the Accept button. There is no skip.
class ChanceTimeResultCard extends StatelessWidget {
  const ChanceTimeResultCard({
    super.key,
    required this.event,
    required this.effect,
    required this.kind,
    required this.reveal,
    required this.onAccept,
  });

  /// The landed event, already resolved for the speaker.
  final String event;
  final ChanceTimeRevealEffect? effect;
  final ChaosCategory? kind;
  final Animation<double> reveal;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final cat = effect ?? ChanceTimeRevealEffect.wildCard;

    final catColor = switch (cat) {
      ChanceTimeRevealEffect.fortune => ChanceTimePalette.fortune,
      ChanceTimeRevealEffect.misfortune => ChanceTimePalette.misfortune,
      ChanceTimeRevealEffect.chaos => ChanceTimePalette.gold,
      ChanceTimeRevealEffect.wildCard => ChanceTimePalette.wildCard,
    };
    final kind = this.kind ?? ChaosCategory.wildCard;
    final catEmoji = kind.emoji;
    final catLabel = kind.label;

    return Column(
      children: [
        // ── Reveal splash ───────────────────────────────────────────────
        _revealSplash(cat, catColor),
        const SizedBox(height: 6),

        // ── Category banner ─────────────────────────────────────────────
        AnimatedBuilder(
          animation: reveal,
          builder: (_, _) {
            final t = reveal.value;
            return Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 0.7 + 0.3 * t,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(catEmoji, style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 6),
                    Text(
                      catLabel,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: catColor,
                        letterSpacing: 1.2,
                        shadows: [
                          Shadow(
                            color: catColor.withValues(alpha: 0.6),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),

        // ── Event text card ─────────────────────────────────────────────
        AnimatedBuilder(
          animation: reveal,
          builder: (_, _) {
            final t = (reveal.value - 0.3).clamp(0.0, 1.0) / 0.7;
            return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, 20 * (1 - t)),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: catColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: catColor.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: catColor.withValues(alpha: 0.18),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Text(
                    event,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: catColor,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),

        // ── No skip — you enabled Chaos, you live with the consequences ──
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: ChanceTimePalette.gold,
              foregroundColor: ChanceTimePalette.onGold,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(50),
              ),
            ),
            onPressed: onAccept,
            child: const Text(
              'Accept Your Fate 🎲',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _revealSplash(ChanceTimeRevealEffect cat, Color catColor) {
    return AnimatedBuilder(
      animation: reveal,
      builder: (context, _) {
        final t = reveal.value;
        return SizedBox(
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Category-specific background pulse
              if (cat == ChanceTimeRevealEffect.fortune ||
                  cat == ChanceTimeRevealEffect.misfortune)
                Opacity(
                  opacity: (1 - t).clamp(0.0, 0.6),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: catColor.withValues(alpha: 0.25),
                    ),
                  ),
                ),

              // Fortune: confetti
              if (cat == ChanceTimeRevealEffect.fortune)
                Positioned.fill(
                  child: CustomPaint(painter: ConfettiPainter(progress: t)),
                ),

              // Chaos: lightning strobe flash
              if (cat == ChanceTimeRevealEffect.chaos)
                Opacity(
                  opacity: (sin(t * pi * 6) * 0.5 + 0.5) * (1 - t),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: ChanceTimePalette.gold.withValues(alpha: 0.35),
                    ),
                  ),
                ),

              // Wild card: purple shimmer sweep
              if (cat == ChanceTimeRevealEffect.wildCard)
                Positioned(
                  left: (MediaQuery.of(context).size.width * 1.4 * t) - 60,
                  child: Container(
                    width: 60,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          ChanceTimePalette.wildCard.withValues(
                            alpha: 0.5 * (1 - t),
                          ),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),

              // Big bouncing category emoji
              Transform.scale(
                scale: t < 0.4
                    ? (t / 0.4) * 1.2
                    : 1.2 - ((t - 0.4) / 0.6) * 0.2,
                child: Text(
                  (kind ?? ChaosCategory.wildCard).emoji,
                  style: const TextStyle(fontSize: 36),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
