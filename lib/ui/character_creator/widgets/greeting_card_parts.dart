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

import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// The Greetings sketch shows a waiting button at 45% instead of greyed out.
const double _kWaitingOpacity = 0.45;

/// The text coming in while a greeting is written, with an amber caret.
class GreetingWritingBox extends StatelessWidget {
  const GreetingWritingBox({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('greeting-writing-box'),
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.backgroundOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: text),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Container(
                width: 2,
                height: 16,
                margin: const EdgeInsets.only(left: 2),
                color: AppColors.porchAmberOf(context),
              ),
            ),
          ],
        ),
        style: TextStyle(
          fontSize: 15,
          height: 1.55,
          color: AppColors.textPrimary(context),
        ),
      ),
    );
  }
}

/// What went wrong with a greeting, in plain words, under its text.
class GreetingErrorLine extends StatelessWidget {
  const GreetingErrorLine({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final red = AppColors.alertRedOf(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Icon(Icons.error_outline, size: 18, color: red),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, height: 1.4, color: red),
          ),
        ),
      ],
    );
  }
}

/// A round 40px icon button in the card header (expand, delete).
class GreetingIconButton extends StatelessWidget {
  const GreetingIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 20,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? _kWaitingOpacity : 1,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: size),
        color: AppColors.textSecondary(context),
        disabledColor: AppColors.textSecondary(context),
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

/// The one-line steer: "start at the harbor at dawn".
class GreetingSteerField extends StatelessWidget {
  const GreetingSteerField({
    super.key,
    required this.controller,
    required this.enabled,
  });

  final TextEditingController? controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: AppTextField(
        controller: controller,
        enabled: enabled,
        maxLines: 1,
        textAlignVertical: TextAlignVertical.center,
        style: TextStyle(
          fontSize: 14,
          color: enabled
              ? AppColors.textPrimary(context)
              : AppColors.textSecondary(context),
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Steer it (optional), e.g. start at the harbor at dawn',
          hintStyle: TextStyle(
            fontSize: 14,
            color: AppColors.textTertiary(context),
          ),
          filled: true,
          fillColor: AppColors.surfaceContainerOf(context),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

ButtonStyle _outlined(BuildContext context, Color fg, Color line) =>
    OutlinedButton.styleFrom(
      foregroundColor: fg,
      disabledForegroundColor: fg,
      side: BorderSide(color: line),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      minimumSize: const Size(0, 44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

/// Button words: set on the Text so they keep the theme's font (a
/// ButtonStyle textStyle replaces the theme's style instead of merging).
const _label = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);

/// Rewrite this greeting (with the steer, when there is one).
class GreetingRegenerateButton extends StatelessWidget {
  const GreetingRegenerateButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    return Opacity(
      opacity: onPressed == null ? _kWaitingOpacity : 1,
      child: SizedBox(
        height: 44,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Regenerate', style: _label),
          style: _outlined(context, amber, amber),
        ),
      ),
    );
  }
}

/// Stop the greeting being written; its old text stays.
class GreetingStopButton extends StatelessWidget {
  const GreetingStopButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.stop, size: 14),
        label: const Text('Stop', style: _label),
        style: _outlined(
          context,
          AppColors.textPrimary(context).withValues(alpha: 0.87),
          AppColors.textTertiary(context),
        ),
      ),
    );
  }
}

/// "Add another greeting": writes one right away. Dashed, per the sketch.
class GreetingAddButton extends StatelessWidget {
  const GreetingAddButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    return Opacity(
      opacity: onPressed == null ? _kWaitingOpacity : 1,
      child: CustomPaint(
        foregroundPainter: _DashedOutline(color: amber, radius: 12),
        child: SizedBox(
          height: 44,
          child: TextButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add another greeting', style: _label),
            style: TextButton.styleFrom(
              foregroundColor: amber,
              disabledForegroundColor: amber,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 1px dashed rounded outline (Flutter borders cannot dash).
class _DashedOutline extends CustomPainter {
  const _DashedOutline({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.5),
          Radius.circular(radius),
        ),
      );
    for (final metric in outline.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 7) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedOutline old) =>
      old.color != color || old.radius != radius;
}
