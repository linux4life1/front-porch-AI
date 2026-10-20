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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/settings/dialogs/color_picker_dialog.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'appearance_choice.dart';

/// The accent choice: the theme's own accent, twelve quick picks, or any
/// color from the wheel. A pick too faint for the theme is fitted, and the
/// note under the swatches says so.
class AccentPickerRow extends StatelessWidget {
  const AccentPickerRow({super.key});

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<StorageService>().appearance;
    final picked = appearance.accentOverride;
    final themeAccent = appearance.isDark
        ? appearance.theme.palettes.dark.amber
        : appearance.theme.palettes.light.amber;
    final custom = picked != null && !kAccentSwatches.contains(picked);
    final note = picked == null
        ? 'Theme accent'
        : appearance.accentAdjusted
        ? 'Custom accent, adjusted for readability'
        : 'Custom accent';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const AppearanceCaption('Accent'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 0,
          runSpacing: 0,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Swatch(
              key: const ValueKey('accent-theme'),
              color: themeAccent,
              label: 'Theme accent',
              selected: picked == null,
              icon: Icons.auto_awesome,
              onTap: () => appearance.setAccentOverride(null),
            ),
            for (final c in kAccentSwatches)
              _Swatch(
                key: ValueKey('accent-${accentHex(c)}'),
                color: c,
                label: 'Accent ${accentHex(c)}',
                selected: picked == c,
                onTap: () => appearance.setAccentOverride(c),
              ),
            _Swatch(
              key: const ValueKey('accent-any'),
              color: custom ? picked : AppColors.surfaceContainerOf(context),
              label: 'Any color',
              selected: custom,
              icon: Icons.colorize,
              onTap: () => showColorPicker(
                context,
                picked ?? themeAccent,
                appearance.setAccentOverride,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          note,
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    super.key,
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: InkResponse(
          onTap: onTap,
          radius: 20,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? AppColors.textPrimary(context)
                        : AppColors.borderOf(context),
                    width: selected ? 2.5 : 1,
                  ),
                ),
                child: icon == null
                    ? null
                    : Icon(icon, size: 15, color: inkOn(color)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
