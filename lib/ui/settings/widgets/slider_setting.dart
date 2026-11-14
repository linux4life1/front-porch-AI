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
import 'package:front_porch_ai/ui/widgets/gen_presets/gen_presets.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import 'studio_slider_card.dart';

/// Slider setting widget extracted from settings_page (Stage 5).
/// Pure lift of _buildSlider with AppColors exclusive; delegates to
/// [StudioSliderCard] when studio track/card styling is requested.
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
    this.reset,
    this.defaultVal,
    this.dangerMin,
    this.dangerMax,
    this.studioStyle = false,
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

  /// Where a ↺ beside the value goes back to; shown only when the value
  /// differs from it.
  final ResetTarget? reset;

  final double? defaultVal;
  final double? dangerMin;
  final double? dangerMax;
  final bool studioStyle;

  String _format(double v) =>
      isInteger ? v.toInt().toString() : v.toStringAsFixed(decimalPlaces);

  Widget? _resetButton() {
    final target = reset;
    if (target == null) return null;
    final differs = isInteger
        ? value.round() != target.value.round()
        : (value - target.value).abs() > 1e-6;
    if (!differs) return null;
    return ValueResetButton(
      tooltip: 'Reset to ${_format(target.value)}, ${target.source}',
      onPressed: () => onChanged(target.value),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (studioStyle ||
        defaultVal != null ||
        dangerMin != null ||
        dangerMax != null) {
      return StudioSliderCard(
        label: label,
        value: value,
        min: min,
        max: max,
        defaultVal: defaultVal,
        dangerMin: dangerMin,
        dangerMax: dangerMax,
        onChanged: (v) => onChanged(v),
        divisions: divisions,
        isInteger: isInteger,
        decimalPlaces: decimalPlaces,
        reset: reset,
        tooltip: tooltip,
      );
    }
    final resetButton = _resetButton();
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
                _format(value),
                style: TextStyle(
                  color: AppColors.textSecondary(
                    context,
                  ).withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
              ?resetButton,
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
      trailing: resetButton,
    );
  }
}
