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

import 'package:front_porch_ai/ui/theme/theme.dart';

/// A small caption over a segmented control, for one Appearance choice.
class AppearanceChoice<T> extends StatelessWidget {
  const AppearanceChoice({
    super.key,
    required this.label,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  final String label;
  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppearanceCaption(label),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) =>
              constraints.maxWidth >= _segmentedWidth(context)
              ? SegmentedButton<T>(
                  showSelectedIcon: false,
                  segments: [
                    for (final v in values)
                      ButtonSegment<T>(value: v, label: Text(labelOf(v))),
                  ],
                  selected: {selected},
                  onSelectionChanged: (picked) => onChanged(picked.first),
                )
              // Too narrow for one row of segments, which would wrap their
              // labels a letter at a time: chips wrap whole.
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final v in values)
                      ChoiceChip(
                        label: Text(labelOf(v)),
                        selected: v == selected,
                        showCheckmark: false,
                        onSelected: (_) => onChanged(v),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  /// What the segments need on one row: each label plus its padding.
  double _segmentedWidth(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;
    final scaler = MediaQuery.textScalerOf(context);
    var width = 0.0;
    for (final v in values) {
      final painter = TextPainter(
        text: TextSpan(text: labelOf(v), style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      width += painter.width + 36;
      painter.dispose();
    }
    return width;
  }
}

/// The small upper-case caption over each Appearance control.
class AppearanceCaption extends StatelessWidget {
  const AppearanceCaption(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      color: AppColors.textSecondary(context),
      fontSize: 11,
      letterSpacing: 0.8,
      fontWeight: FontWeight.w600,
    ),
  );
}
