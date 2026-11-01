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

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A needs bar in trouble (Mood on the character): the row tints in the
/// need's hue and the bar throbs with a glow, twice as fast when the need
/// is critical, with a badge at the bar's end. Under reduce motion the
/// tint and the badge stay and nothing throbs. [inverted] marks hygiene on
/// a character who enjoys it low: the badge reads ↕ so the direction is
/// clear.
class NeedsPulse extends StatefulWidget {
  const NeedsPulse({
    super.key,
    required this.hue,
    required this.critical,
    required this.inverted,
    required this.animate,
    required this.child,
  });

  final Color hue;
  final bool critical;
  final bool inverted;
  final bool animate;
  final Widget child;

  @override
  State<NeedsPulse> createState() => _NeedsPulseState();
}

class _NeedsPulseState extends State<NeedsPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: _period,
  );

  Duration get _period => Duration(milliseconds: widget.critical ? 500 : 1200);

  @override
  void initState() {
    super.initState();
    if (widget.animate) _beat.repeat();
  }

  @override
  void didUpdateWidget(NeedsPulse old) {
    super.didUpdateWidget(old);
    _beat.duration = _period;
    if (widget.animate && !_beat.isAnimating) _beat.repeat();
    if (!widget.animate && _beat.isAnimating) _beat.stop();
  }

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _beat,
      builder: (context, child) {
        // Still: held at the peak, so the trouble reads without motion.
        final p = widget.animate
            ? 0.5 + 0.5 * math.sin(_beat.value * math.pi * 2)
            : 1.0;
        final tint = widget.critical ? 0.12 + 0.2 * p : 0.08 + 0.16 * p;
        return Container(
          key: ValueKey(widget.critical ? 'need-critical' : 'need-low'),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: widget.hue.withValues(alpha: tint),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: widget.hue.withValues(alpha: 0.25 + 0.45 * p),
                blurRadius: 6 + 10 * p,
                spreadRadius: 1 + 2 * p,
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              child!,
              Positioned(
                right: -2,
                top: -6,
                child: Container(
                  width: 14,
                  height: 14,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: widget.hue,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    widget.inverted ? '↕' : '!',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: Colors
                          .black87, // theme-keep: ink on the need's own hue
                      height: 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      child: widget.child,
    );
  }
}
