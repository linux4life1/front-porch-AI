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
        SegmentedButton<T>(
          showSelectedIcon: false,
          segments: [
            for (final v in values)
              ButtonSegment<T>(value: v, label: Text(labelOf(v))),
          ],
          selected: {selected},
          onSelectionChanged: (picked) => onChanged(picked.first),
        ),
      ],
    );
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
