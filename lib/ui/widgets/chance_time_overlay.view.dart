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

part of 'chance_time_overlay.dart';

/// The Chance Time overlay's visual builders — card shell, starburst header,
/// wheel stack, spin button, result card, reveal splash and pressure row. Pure
/// presentation over [_ChanceTimeOverlayState]'s data; the spin animation,
/// category detection and the accept path stay in chance_time_overlay.dart.
extension _ChanceTimeOverlayView on _ChanceTimeOverlayState {
  Widget _buildContent() {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117).withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFFFD166).withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD166).withValues(alpha: 0.15),
            blurRadius: 40,
            spreadRadius: 4,
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            const SizedBox(height: 12),
            _buildWheel(),
            const SizedBox(height: 12),
            if (_landed) _buildResultCard() else _buildSpinButton(),
            const SizedBox(height: 10),
            _buildPressureRow(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
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
                const Color(0xFFFFD166).withValues(alpha: 0.3),
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
            color: Color(0xFFFFD166),
            letterSpacing: 2,
            shadows: [
              Shadow(color: Color(0xFFFFD166), blurRadius: 20),
              Shadow(color: Colors.black, blurRadius: 4, offset: Offset(2, 2)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWheel() {
    // Shrink wheel after landing to give the result card more room
    final wheelPx = _landed ? 190.0 : 290.0;
    final paintPx = _landed ? 174.0 : 274.0;
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
                  const Color(0xFFFFD166).withValues(alpha: 0.25),
                ],
                stops: const [0.85, 1.0],
              ),
            ),
          ),
          // Spinning wheel
          AnimatedBuilder(
            animation: _spinning
                ? _spinAnimation
                : AlwaysStoppedAnimation(_landed ? _targetAngle % (2 * pi) : 0),
            builder: (context, child) {
              final angle = _spinning
                  ? _spinAnimation.value
                  : (_landed ? _targetAngle % (2 * pi) : 0.0);
              return Transform.rotate(
                angle: angle,
                child: CustomPaint(
                  size: Size(paintPx, paintPx),
                  painter: WheelPainter(
                    segments: _segments,
                    colors: _ChanceTimeOverlayState._segmentColors,
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
                colors: [Color(0xFFFFF9C4), Color(0xFFFFD166)],
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

  Widget _buildSpinButton() {
    return GestureDetector(
      onTap: _spin,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFD166), Color(0xFFFFC233)],
          ),
          borderRadius: BorderRadius.circular(50),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFFD166).withValues(alpha: 0.5),
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
            color: Color(0xFF1A1200),
            letterSpacing: 3,
          ),
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    final event = _displayEvent(_segments[_landedIndex]);
    final cat = _category ?? _EventCategory.wildCard;

    final (catEmoji, catLabel, catColor) = switch (cat) {
      _EventCategory.fortune => ('🎉', 'Fortune!', const Color(0xFF06D6A0)),
      _EventCategory.misfortune => (
        '💀',
        'Misfortune',
        const Color(0xFFE63946),
      ),
      _EventCategory.chaos => ('⚡', 'Chaos!', const Color(0xFFFFD166)),
      _EventCategory.wildCard => ('🔮', 'Wild Card', const Color(0xFF9B5DE5)),
    };

    return Column(
      children: [
        // ── Reveal splash ───────────────────────────────────────────────
        _buildRevealSplash(cat, catColor),
        const SizedBox(height: 6),

        // ── Category banner ─────────────────────────────────────────────
        AnimatedBuilder(
          animation: _revealAnimation,
          builder: (_, _) {
            final t = _revealAnimation.value;
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
          animation: _revealAnimation,
          builder: (_, _) {
            final t = (_revealAnimation.value - 0.3).clamp(0.0, 1.0) / 0.7;
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
              backgroundColor: const Color(0xFFFFD166),
              foregroundColor: const Color(0xFF1A1200),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(50),
              ),
            ),
            onPressed: () {
              final svc = context.read<ChatService>();
              final seg = _segments[_landedIndex];
              final name = _charName ?? 'Character';
              // Pop FIRST so the overlay is fully disposed before
              // _generateResponse fires notifyListeners.
              Navigator.of(context).pop();
              svc.applyChanceTimeResult(seg, name);
            },
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

  Widget _buildRevealSplash(_EventCategory cat, Color catColor) {
    return AnimatedBuilder(
      animation: _revealAnimation,
      builder: (context, _) {
        final t = _revealAnimation.value;
        return SizedBox(
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Category-specific background pulse
              if (cat == _EventCategory.fortune ||
                  cat == _EventCategory.misfortune)
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
              if (cat == _EventCategory.fortune)
                Positioned.fill(
                  child: CustomPaint(painter: ConfettiPainter(progress: t)),
                ),

              // Chaos: lightning strobe flash
              if (cat == _EventCategory.chaos)
                Opacity(
                  opacity: (sin(t * pi * 6) * 0.5 + 0.5) * (1 - t),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: const Color(0xFFFFD166).withValues(alpha: 0.35),
                    ),
                  ),
                ),

              // Wild card: purple shimmer sweep
              if (cat == _EventCategory.wildCard)
                Positioned(
                  left: (MediaQuery.of(context).size.width * 1.4 * t) - 60,
                  child: Container(
                    width: 60,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          const Color(
                            0xFF9B5DE5,
                          ).withValues(alpha: 0.5 * (1 - t)),
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
                  cat == _EventCategory.fortune
                      ? '🎉'
                      : cat == _EventCategory.misfortune
                      ? '💀'
                      : cat == _EventCategory.chaos
                      ? '⚡'
                      : '🔮',
                  style: const TextStyle(fontSize: 36),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPressureRow() {
    return Consumer<ChatService>(
      builder: (_, svc, _) {
        final pressure = svc.chaosModeService.chaosPressure;
        final color = Color.lerp(
          const Color(0xFF2EC4B6),
          const Color(0xFFE63946),
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
