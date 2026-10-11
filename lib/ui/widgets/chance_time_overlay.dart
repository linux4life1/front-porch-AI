// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show ChaosCategory, ChaosModeService;
import 'package:front_porch_ai/ui/widgets/chance_time/chance_time.dart';

part 'chance_time_overlay.view.dart';

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
  ChaosCategory? _kind;

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
      final kind = ChaosModeService.categoryOf(_segments[_landedIndex]);
      setState(() {
        _spinning = false;
        _landed = true;
        _kind = kind;
        _category = _effectFor(kind);
      });
      _revealController.forward(from: 0);
    });
  }

  // ── Category ───────────────────────────────────────────────────────────────

  /// The reveal effect for a category: the wheel has four animations, and the
  /// newer kinds borrow the closest one while keeping their own label.
  static _EventCategory _effectFor(ChaosCategory c) => switch (c) {
    ChaosCategory.fortune => _EventCategory.fortune,
    ChaosCategory.misfortune ||
    ChaosCategory.slapstick ||
    ChaosCategory.needs => _EventCategory.misfortune,
    ChaosCategory.chaos || ChaosCategory.weather => _EventCategory.chaos,
    ChaosCategory.wildCard ||
    ChaosCategory.social ||
    ChaosCategory.plotHook ||
    ChaosCategory.spicy => _EventCategory.wildCard,
  };

  String _displayEvent(String raw) => context
      .read<ChatService>()
      .resolveChanceTimeEvent(raw, _charName ?? 'Character');

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
}
