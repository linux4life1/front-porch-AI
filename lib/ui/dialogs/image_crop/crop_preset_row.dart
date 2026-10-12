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
import 'package:front_porch_ai/utils/utils.dart';

/// The aspect presets. Free is null; the circle guide rides 1:1.
const _presets = <(String, double?)>[
  ('Free', null),
  ('1:1', 1.0),
  ('2:3', 2 / 3),
  ('16:9', 16 / 9),
];

/// Chrome for the image crop dialog: the aspect-preset chips, the Face
/// circle-guide chip, and the fill swatches.
class CropPresetRow extends StatelessWidget {
  final double? aspect;
  final bool circle;
  final CropFill fill;
  final void Function(double? aspect, bool circle) onSelectPreset;
  final ValueChanged<CropFill> onSelectFill;

  const CropPresetRow({
    super.key,
    required this.aspect,
    required this.circle,
    required this.fill,
    required this.onSelectPreset,
    required this.onSelectFill,
  });

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final (label, presetAspect) in _presets)
            ChoiceChip(
              label: Text(label),
              selected: !circle && aspect == presetAspect,
              selectedColor: amber.withValues(alpha: 0.25),
              labelStyle: TextStyle(
                fontSize: 12,
                color: (!circle && aspect == presetAspect)
                    ? AppColors.textPrimary(context)
                    : AppColors.textSecondary(context),
              ),
              visualDensity: VisualDensity.compact,
              onSelected: (_) => onSelectPreset(presetAspect, false),
            ),
          ChoiceChip(
            avatar: Icon(
              Icons.circle_outlined,
              size: 14,
              color: circle ? amber : AppColors.iconSecondary(context),
            ),
            label: const Text('Face'),
            selected: circle,
            selectedColor: amber.withValues(alpha: 0.25),
            labelStyle: TextStyle(
              fontSize: 12,
              color: circle
                  ? AppColors.textPrimary(context)
                  : AppColors.textSecondary(context),
            ),
            visualDensity: VisualDensity.compact,
            tooltip:
                'Square crop with a circle guide — avatars render round '
                'in chat',
            onSelected: (_) => onSelectPreset(1.0, true),
          ),
          const SizedBox(width: 8),
          for (final f in CropFill.values) _fillSwatch(context, f),
        ],
      ),
    );
  }

  Widget _fillSwatch(BuildContext context, CropFill swatch) {
    final selected = fill == swatch;
    return Tooltip(
      message: switch (swatch) {
        CropFill.dark => 'Fill past the edges with dark',
        CropFill.white => 'Fill past the edges with white',
        CropFill.transparent => 'Transparent past the edges',
      },
      child: InkWell(
        onTap: () => onSelectFill(swatch),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: swatch == CropFill.transparent
                ? null
                : Color.fromARGB(255, swatch.r, swatch.g, swatch.b),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected
                  ? AppColors.porchAmberOf(context)
                  : AppColors.borderOf(context),
              width: selected ? 2 : 1,
            ),
          ),
          child: swatch == CropFill.transparent
              ? Icon(
                  Icons.grid_on,
                  size: 14,
                  color: AppColors.iconSecondary(context),
                )
              : null,
        ),
      ),
    );
  }
}
