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

import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// The creator's step dots, right-aligned in the app bar
/// (docs/design/creator-ui-spec.md, "Desktop chrome"). Each step is a column:
/// a 24px circle, 3px gap, then a 10px label. Done steps are amber with an
/// amber-ink check, the current one amber with a 2px ink ring, upcoming ones
/// a raised fill with a muted number and a faint label.
class CreatorStepIndicator extends StatelessWidget {
  const CreatorStepIndicator({
    super.key,
    required this.labels,
    required this.current,
    this.isDone,
  });

  /// Step labels, in order.
  final List<String> labels;

  /// Index of the step on screen.
  final int current;

  /// Whether step `i` counts as done. Defaults to every step before
  /// [current].
  final bool Function(int i)? isDone;

  /// Steps whose labels need the wider 60px column.
  static const _wide = {'Configure', 'Generate', 'Greetings'};

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < labels.length; i++)
        SizedBox(
          width: _wide.contains(labels[i]) ? 60 : 52,
          child: _StepDot(
            number: i + 1,
            label: labels[i],
            current: i == current,
            done: i != current && (isDone?.call(i) ?? i < current),
          ),
        ),
    ],
  );
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.number,
    required this.label,
    required this.current,
    required this.done,
  });

  final int number;
  final String label;
  final bool current;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final amber = StudioColors.amberOf(context);
    final ink = StudioColors.inkOf(context);
    final lit = current || done;
    final Widget mark = done
        ? CustomPaint(
            size: const Size.square(13),
            painter: _CheckPainter(StudioColors.amberInkOf(context)),
          )
        : Text(
            '$number',
            style: TextStyle(
              fontSize: 11,
              height: 1,
              fontWeight: current ? FontWeight.w700 : FontWeight.w600,
              color: current
                  ? StudioColors.amberInkOf(context)
                  : StudioColors.mutedOf(context),
            ),
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: lit ? amber : StudioColors.raiseOf(context),
            border: current ? Border.all(color: ink, width: 2) : null,
          ),
          child: Center(child: mark),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.visible,
          softWrap: false,
          style: TextStyle(
            fontSize: 10,
            color: current
                ? ink
                : done
                ? StudioColors.mutedOf(context)
                : StudioColors.faintOf(context),
          ),
        ),
      ],
    );
  }
}

/// The spec's 13px check: a 24-unit path drawn with a 3-unit stroke, the
/// same mark the web draws as an SVG.
class _CheckPainter extends CustomPainter {
  const _CheckPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(5 * s, 12.5 * s)
      ..lineTo(10 * s, 17.5 * s)
      ..lineTo(19 * s, 7 * s);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.color != color;
}
