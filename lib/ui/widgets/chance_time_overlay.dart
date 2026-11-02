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

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/ui/theme/chance_time_palette.dart';
import 'package:front_porch_ai/ui/widgets/chance_time_overlay/chance_time_overlay.dart';

/// The Chance Time overlay: the wheel, the spin, the landed event and the
/// Accept that resumes the parked send.
///
/// Outcome first: [_spin] picks the slot (and so the event) before the
/// wheel moves, as it always has, and hands it to the Flame wheel
/// ([ChanceWheelGame]) to land on. The wheel is painted over the overlay's
/// column so its particles can fly over the card; the column keeps the
/// wheel's room with [ChanceTimeWheel]. Under reduce motion the wheel
/// jumps to its stop and the card shows at once.
class ChanceTimeOverlay extends StatefulWidget {
  const ChanceTimeOverlay({super.key, this.host});

  /// What the overlay asks of the chat; null reads the [ChatService] in
  /// context through [ChatChanceTimeHost].
  final ChanceTimeHost? host;

  @override
  State<ChanceTimeOverlay> createState() => _ChanceTimeOverlayState();
}

class _ChanceTimeOverlayState extends State<ChanceTimeOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _revealController;
  late Animation<double> _revealAnimation;
  late final ChanceWheelGame _game = ChanceWheelGame(
    segments: const [],
    onLanded: _onLanded,
    onSettled: _onSettled,
  );

  List<String> _segments = const [];
  bool _spinning = false;
  bool _landed = false;
  bool _settled = false;
  int _landedIndex = 0;
  String? _charName;
  ChanceTimeRevealEffect? _category;
  ChaosCategory? _kind;

  /// The wheel's centre, down the overlay's column: the header, the gap,
  /// then half the wheel's box.
  static double _wheelCentreY(bool landed) =>
      kChanceTimeHeaderHeight +
      12 +
      (landed ? kChanceWheelBoxLandedPx : kChanceWheelBoxPx) / 2;

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _revealAnimation = CurvedAnimation(
      parent: _revealController,
      curve: Curves.easeOut,
    );
    _game.layout(centreY: _wheelCentreY(false), radius: kChanceWheelBaseRadius);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final host = _host;
      host.consumeTrigger();
      setState(() {
        _segments = host.spinWheelEvents();
        _game.segments = _segments;
        // Attribute the event to whoever actually responds next (group speaker,
        // else the 1:1 host) — single-sourced on ChatService so the web accept
        // path attributes it identically.
        _charName = host.speakerName;
      });
    });
  }

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  void _spin() {
    if (_spinning || _landed) return;
    // The slot is the outcome, picked here before anything moves; the
    // wheel's spin is solved to land on it.
    final rng = Random();
    _landedIndex = rng.nextInt(_segments.length);
    final kind = ChaosModeService.categoryOf(_segments[_landedIndex]);
    _kind = kind;
    _category = _effectFor(kind);
    _game.reduceMotion = MediaQuery.disableAnimationsOf(context);
    setState(() => _spinning = true);
    _game.spin(
      seed: rng.nextInt(1 << 31),
      slot: _landedIndex,
      effect: _category!,
    );
  }

  void _onLanded() {
    if (!mounted) return;
    setState(() {
      _spinning = false;
      _landed = true;
    });
    _game.layout(
      centreY: _wheelCentreY(true),
      radius: kChanceWheelBoxLandedPx / 2 - 8,
      animate: true,
    );
  }

  void _onSettled() {
    if (!mounted) return;
    setState(() => _settled = true);
    if (_game.reduceMotion) {
      _revealController.value = 1;
    } else {
      _revealController.forward(from: 0);
    }
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

  ChanceTimeHost get _host =>
      widget.host ?? ChatChanceTimeHost(context.read<ChatService>());

  String _displayEvent(String raw) =>
      _host.resolve(raw, _charName ?? 'Character');

  void _accept() {
    final host = _host;
    final seg = _segments[_landedIndex];
    final name = _charName ?? 'Character';
    // Pop FIRST so the overlay is fully disposed before
    // _generateResponse fires notifyListeners.
    Navigator.of(context).pop();
    host.apply(seg, name);
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
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ChanceTimeHeader(),
                const SizedBox(height: 12),
                ChanceTimeWheel(landed: _landed),
                const SizedBox(height: 12),
                if (_settled)
                  ChanceTimeResultCard(
                    event: _displayEvent(_segments[_landedIndex]),
                    effect: _category,
                    kind: _kind,
                    reveal: _revealAnimation,
                    onAccept: _accept,
                  )
                else if (_spinning || _landed)
                  // The spin and the settle: the wheel is the whole show
                  // until the card comes.
                  const SizedBox(height: 56)
                else
                  ChanceTimeSpinButton(onSpin: _spin),
                const SizedBox(height: 10),
                const ChanceTimePressureRow(),
              ],
            ),
            // The wheel and its particles, over the column. It takes no
            // input and no focus; the buttons under it keep both.
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeFocus(
                  child: GameWidget(game: _game, autofocus: false),
                ),
              ),
            ),
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
