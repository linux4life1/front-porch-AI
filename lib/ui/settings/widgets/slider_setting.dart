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

/// Slider setting widget extracted from settings_page (Stage 5).
/// Pure lift of _buildSlider with AppColors exclusive.
class SliderSetting extends StatelessWidget {
  const SliderSetting({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.tooltip,
    this.showInput = false,
    this.isInteger = false,
    this.decimalPlaces = 2,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final Function(double) onChanged;
  final int? divisions;
  final String? tooltip;
  final bool showInput;
  final bool isInteger;
  final int decimalPlaces;

  @override
  Widget build(BuildContext context) {
    if (!showInput) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: AppColors.textSecondary(
                      context,
                    ).withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isInteger
                    ? value.toInt().toString()
                    : value.toStringAsFixed(decimalPlaces),
                style: TextStyle(
                  color: AppColors.textSecondary(
                    context,
                  ).withValues(alpha: 0.5),
                  fontSize: 12,
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
          ),
        ],
      );
    }

    return SliderWithInput(
      label: label,
      value: value,
      min: min,
      max: max,
      onChanged: onChanged,
      context: context,
      divisions: divisions,
      tooltip: tooltip,
      isInteger: isInteger,
      decimalPlaces: decimalPlaces,
    );
  }
}
