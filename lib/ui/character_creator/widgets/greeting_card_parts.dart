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

import 'package:front_porch_ai/ui/character_creator/widgets/creator_dashed_outline.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/streamed_text.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';
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
        color: StudioColors.bgOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StudioColors.lineOf(context)),
      ),
      child: StreamedText(
        text: text,
        style: TextStyle(
          fontSize: 15,
          height: 1.55,
          color: StudioColors.inkOf(context),
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
    final red = StudioColors.badOf(context);
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
        color: StudioColors.proseOf(context),
        disabledColor: StudioColors.proseOf(context),
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

/// The spec's steer field: `raise` fill, no border, radius 12, 14px ink,
/// a faint placeholder. One line at 44px ("start at the harbor at dawn"),
/// or, when [grows], a box that grows with its text from 44px (the
/// profile rewrite).
class GreetingSteerField extends StatelessWidget {
  const GreetingSteerField({
    super.key,
    required this.controller,
    required this.enabled,
    this.hint = 'Steer it (optional), e.g. start at the harbor at dawn',
    this.grows = false,
    this.onChanged,
  });

  final TextEditingController? controller;
  final bool enabled;
  final String hint;
  final bool grows;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final field = AppTextField(
      controller: controller,
      enabled: enabled,
      maxLines: grows ? null : 1,
      minLines: grows ? 1 : null,
      onChanged: onChanged,
      textAlignVertical: grows ? null : TextAlignVertical.center,
      style: TextStyle(
        fontSize: 14,
        height: grows ? 1.4 : null,
        color: enabled
            ? StudioColors.inkOf(context)
            : StudioColors.proseOf(context),
      ),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: TextStyle(
          fontSize: 14,
          color: StudioColors.faintOf(context),
        ),
        filled: true,
        fillColor: StudioColors.raiseOf(context),
        contentPadding: grows
            ? const EdgeInsets.symmetric(horizontal: 14, vertical: 12)
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
    if (grows) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: field,
      );
    }
    return SizedBox(height: 44, child: field);
  }
}

ButtonStyle _outlined(BuildContext context, Color fg, Color line) =>
    OutlinedButton.styleFrom(
      foregroundColor: fg,
      disabledForegroundColor: fg,
      side: BorderSide(color: line, width: 1.5),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      minimumSize: const Size(0, 44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

/// Button words: set on the Text so they keep the theme's font (a
/// ButtonStyle textStyle replaces the theme's style instead of merging).
const _label = TextStyle(fontSize: 14, fontWeight: FontWeight.w700);

/// Rewrite this greeting (with the steer, when there is one).
class GreetingRegenerateButton extends StatelessWidget {
  const GreetingRegenerateButton({
    super.key,
    required this.onPressed,
    this.label = 'Regenerate',
  });

  final VoidCallback? onPressed;

  /// The outlined action's words ("Rewrite the profile", "Rewrite the
  /// lorebook").
  final String label;

  @override
  Widget build(BuildContext context) {
    final amber = StudioColors.amberOf(context);
    return Opacity(
      opacity: onPressed == null ? _kWaitingOpacity : 1,
      child: SizedBox(
        height: 44,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(label, style: _label),
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
        icon: const Icon(Icons.stop, size: 18),
        label: const Text('Stop', style: _label),
        // The outlined action's shape in `bad` (creator-ui-spec.md).
        style: _outlined(
          context,
          StudioColors.badOf(context),
          StudioColors.badOf(context),
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
    final amber = StudioColors.amberOf(context);
    return Opacity(
      opacity: onPressed == null ? _kWaitingOpacity : 1,
      child: CustomPaint(
        foregroundPainter: CreatorDashedOutline(color: amber, radius: 12),
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
