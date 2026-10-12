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
import 'package:front_porch_ai/ui/settings/dialogs/color_picker_dialog.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// "Lock Avatar Size" row of the UI Settings Appearance section.
class AvatarLockToggle extends StatelessWidget {
  final bool locked;
  final ValueChanged<bool> onChanged;

  const AvatarLockToggle({
    super.key,
    required this.locked,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Lock Avatar Size',
                style: TextStyle(color: AppColors.textSecondary(context)),
              ),
              Text(
                'Avatar won\'t grow past default size when sidebar is wider',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: locked,
          onChanged: onChanged,
          activeTrackColor: AppColors.formMasterAccent,
        ),
      ],
    );
  }
}

/// Labelled slider with its value printed to two decimals.
class UiSettingsSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final int? divisions;

  const UiSettingsSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
            Text(
              value.toStringAsFixed(2),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary(context),
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          activeColor: AppColors.formMasterAccent,
          inactiveColor: AppColors.borderOf(context),
        ),
      ],
    );
  }
}

/// A labelled color swatch; tapping it opens the shared [showColorPicker].
class ChatColorRow extends StatelessWidget {
  final String label;
  final Color color;
  final ValueChanged<Color> onChanged;

  const ChatColorRow({
    super.key,
    required this.label,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 13,
            ),
          ),
          const Spacer(),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.borderOf(context), width: 1),
            ),
            child: IconButton(
              icon: Icon(Icons.color_lens, size: 20, color: swatchInkOn(color)),
              onPressed: () => showColorPicker(context, color, onChanged),
            ),
          ),
        ],
      ),
    );
  }
}
