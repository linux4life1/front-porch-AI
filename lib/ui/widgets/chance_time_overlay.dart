// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show ChaosCategory, ChaosModeService;
import 'package:front_porch_ai/ui/theme/chance_time_palette.dart';
import 'package:front_porch_ai/ui/widgets/chance_time_overlay/chance_time_overlay.dart';

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
  ChanceTimeRevealEffect? _category;
  ChaosCategory? _kind;

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

  static ChanceTimeRevealEffect _effectFor(ChaosCategory c) => switch (c) {
    ChaosCategory.fortune => ChanceTimeRevealEffect.fortune,
    ChaosCategory.misfortune ||
    ChaosCategory.slapstick ||
    ChaosCategory.needs => ChanceTimeRevealEffect.misfortune,
    ChaosCategory.chaos ||
    ChaosCategory.weather => ChanceTimeRevealEffect.chaos,
    ChaosCategory.wildCard ||
    ChaosCategory.social ||
    ChaosCategory.plotHook ||
    ChaosCategory.spicy => ChanceTimeRevealEffect.wildCard,
  };

  String _displayEvent(String raw) => context
      .read<ChatService>()
      .resolveChanceTimeEvent(raw, _charName ?? 'Character');

  void _accept() {
    final svc = context.read<ChatService>();
    final seg = _segments[_landedIndex];
    final name = _charName ?? 'Character';
    // Pop FIRST so the overlay is fully disposed before
    // _generateResponse fires notifyListeners.
    Navigator.of(context).pop();
    svc.applyChanceTimeResult(seg, name);
  }

  Widget _buildContent() {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: ChanceTimePalette.backdrop.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: ChanceTimePalette.gold.withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: ChanceTimePalette.gold.withValues(alpha: 0.15),
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
            const ChanceTimeHeader(),
            const SizedBox(height: 12),
            ChanceTimeWheel(
              segments: _segments,
              spinning: _spinning,
              landed: _landed,
              targetAngle: _targetAngle,
              spinAnimation: _spinning ? _spinAnimation : null,
            ),
            const SizedBox(height: 12),
            if (_landed)
              ChanceTimeResultCard(
                event: _displayEvent(_segments[_landedIndex]),
                effect: _category,
                kind: _kind,
                reveal: _revealAnimation,
                onAccept: _accept,
              )
            else
              ChanceTimeSpinButton(onSpin: _spin),
            const SizedBox(height: 10),
            const ChanceTimePressureRow(),
          ],
        ),
      ),
    );
  }

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
