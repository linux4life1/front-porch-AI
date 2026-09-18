// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/macro_resolver.dart';
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

  String _displayEvent(String raw) => MacroResolver().resolve(
    raw,
    MacroContext(characterName: _charName ?? 'Character', userName: ''),
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
}
