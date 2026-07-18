// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/macro_resolver.dart';

enum _EventCategory { fortune, misfortune, chaos, wildCard }

/// Full-screen Chance Time overlay.
///
/// Show it via:
/// ```dart
/// showDialog(context: context, builder: (_) => const ChanceTimeOverlay());
/// ```
class ChanceTimeOverlay extends StatefulWidget {
  const ChanceTimeOverlay({super.key});

  @override
  State<ChanceTimeOverlay> createState() => _ChanceTimeOverlayState();
}

class _ChanceTimeOverlayState extends State<ChanceTimeOverlay>
    with TickerProviderStateMixin {
  late AnimationController _spinController;
  late Animation<double> _spinAnimation;
  late AnimationController _revealController;
  late Animation<double> _revealAnimation;

  List<String> _segments = const [];
  bool _spinning = false;
  bool _landed = false;
  int _landedIndex = 0;
  double _targetAngle = 0;
  String? _charName;
  _EventCategory? _category;

  // Segment colours (Mario Party palette)
  static const List<Color> _segmentColors = [
    Color(0xFFE63946), // red
    Color(0xFFFF9F1C), // orange
    Color(0xFF2EC4B6), // teal
    Color(0xFF9B5DE5), // purple
    Color(0xFF06D6A0), // green
    Color(0xFFFF6B9D), // pink
    Color(0xFFFFD166), // amber
    Color(0xFF118AB2), // blue
  ];

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(vsync: this);
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _revealAnimation = CurvedAnimation(
      parent: _revealController,
      curve: Curves.easeOut,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final svc = context.read<ChatService>();
      svc.consumeChanceTimeTrigger();
      setState(() {
        _segments = svc.spinWheelEvents();
        // Attribute the event to whoever actually responds next (group speaker,
        // else the 1:1 host) — single-sourced on ChatService so the web accept
        // path attributes it identically.
        _charName = svc.chanceTimeSpeakerName;
      });
    });
  }

  @override
  void dispose() {
    _spinController.dispose();
    _revealController.dispose();
    super.dispose();
  }

  void _spin() {
    if (_spinning || _landed) return;
    setState(() => _spinning = true);

    // Pick a random landing segment
    final rng = Random();
    _landedIndex = rng.nextInt(8);

    // Extra full rotations (5–8) + precise landing angle
    final extraRotations = (rng.nextInt(4) + 5) * 2 * pi;
    // Segment size = 2π/8. Pointer is at top (12 o'clock) = 0.
    // Segment i starts at i*(2π/8), centre at (i+0.5)*(2π/8).
    final segmentAngle = (2 * pi) / 8;
    final landingAngleInWheel = (_landedIndex + 0.5) * segmentAngle;
    // We need the wheel to rotate so that segment is under the pointer.
    // Pointer at top means we want the segment centre at angle 0 (top).
    // Wheel rotation = full rotations + (2π - landingAngle).
    _targetAngle = extraRotations + (2 * pi - landingAngleInWheel);

    _spinAnimation = Tween<double>(begin: 0, end: _targetAngle).animate(
      CurvedAnimation(parent: _spinController, curve: Curves.easeOutCubic),
    );

    _spinController.reset();
    _spinController.duration = const Duration(milliseconds: 3800);
    _spinController.forward().whenComplete(() {
      final cat = _categorize(_segments[_landedIndex]);
      setState(() {
        _spinning = false;
        _landed = true;
        _category = cat;
      });
      _revealController.forward(from: 0);
    });
  }

  // ── Category detection ─────────────────────────────────────────────────────

  static const _fortuneKeywords = [
    'found something valuable',
    'mistaken for someone important',
    'crowd of admirers',
    'turned up in the most unexpected',
    'unexpected compliment',
    'hidden stash',
    'pulled off something impressive',
    'stranger just paid',
    'arrived somewhere late',
    'won something',
    'beautiful view',
    'accidentally said the perfect',
    'best hair',
    'turned completely around',
    'shortcut or trick',
    'best seat',
    'weather turned',
    'ran into someone',
    'animal has taken',
    'made a guess',
    'overheard something',
    'arrived to help',
    'offered more than they asked',
    'kindness',
    'well-rested',
    'best portion',
    'accomplished something',
    'charming today',
    'rooting for them',
    'unexpected credit',
  ];
  static const _misfortuneKeywords = [
    'urgently needs to use the restroom',
    'stepped in something extremely unpleasant',
    'sneezed violently',
    'sat in something wet',
    'hiccups',
    'bit their tongue',
    'something in their teeth',
    'ripped in an extremely inconvenient',
    'knocked something over',
    'tripped',
    'involuntary sound',
    'extremely itchy somewhere',
    'spilled something on themselves',
    'stomach is making alarming sounds',
    'said goodbye to someone and then walked',
    'confidently greeted someone who has no idea',
    'waved back at someone who was not',
    'laughed at something completely inappropriate',
    'walked into something',
    'piece of hair or debris',
    'mark on their face',
    'squeaking piece',
    'yawned enormously',
    'sent a message and immediately regretted',
    'pretend they remember',
    'hands are completely full',
    'dropped something and it rolled',
    'something in their eye',
    'nodding along',
    'pronouncing something wrong',
    'sneezing fit',
    'direct and sustained eye contact',
    'reached for something',
    'fell asleep briefly',
    'confident prediction',
    'forgot where it was going',
    'uncooperative hair',
    'involuntary noise while trying to lift',
    'regretted the food choice',
    'footwear issue',
    'mispronounced repeatedly',
    'backwards or inside-out',
  ];
  static const _chaosKeywords = [
    'bird flew directly',
    'loud and disruptive noise',
    'fell over on its own',
    'unexpected center of a very enthusiastic',
    'animal has decided',
    'unusual outfit',
    'make noise',
    'gust of wind',
    'extremely large insect',
    'lighting wherever',
    'crowd has formed',
    'very loud and very one-sided story',
    'enthusiastic child',
    'cooking or burning nearby',
    'broken in a way that is more funny',
    'uninvited guest or creature',
    'spontaneously rearranged',
    'recruit',
    'loud and personal argument',
    'small and ridiculous has escalated',
    'animal is doing exactly what it should not',
    'accidentally started a trend',
    'performing something unsolicited',
    'synchronized into something inexplicably musical',
    'delivery or package',
    'definitely fixed has become unfixed',
    'squeak, rattle, or wobble',
    'very long and intricate process',
    'every seat, surface',
    'counting on to work fine',
  ];

  _EventCategory _categorize(String event) {
    final lower = event.toLowerCase();
    for (final k in _fortuneKeywords) {
      if (lower.contains(k)) return _EventCategory.fortune;
    }
    for (final k in _misfortuneKeywords) {
      if (lower.contains(k)) return _EventCategory.misfortune;
    }
    for (final k in _chaosKeywords) {
      if (lower.contains(k)) return _EventCategory.chaos;
    }
    return _EventCategory.wildCard;
  }

  String _displayEvent(String raw) =>
      MacroResolver().resolve(
        raw,
        MacroContext(
          characterName: _charName ?? 'Character',
          userName: '',
        ),
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: _segments.isEmpty ? const SizedBox.shrink() : _buildContent(),
      ),
    );
  }

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
                  painter: _WheelPainter(
                    segments: _segments,
                    colors: _segmentColors,
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
              painter: _PointerPainter(),
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
                  child: CustomPaint(painter: _ConfettiPainter(progress: t)),
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

// ── Confetti painter ─────────────────────────────────────────────────────────

class _ConfettiPainter extends CustomPainter {
  final double progress; // 0→1

  _ConfettiPainter({required this.progress});

  static final List<_Confetto> _pieces = List.generate(30, (i) {
    final rng = Random(i * 13);
    return _Confetto(
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
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}

class _Confetto {
  final double x, startY, size, speed;
  final Color color;
  const _Confetto({
    required this.x,
    required this.startY,
    required this.color,
    required this.size,
    required this.speed,
  });
}

// ── Wheel & Pointer ───────────────────────────────────────────────────────────

class _WheelPainter extends CustomPainter {
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

  const _WheelPainter({required this.segments, required this.colors});

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
  bool shouldRepaint(covariant _WheelPainter old) => old.segments != segments;
}

class _PointerPainter extends CustomPainter {
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
