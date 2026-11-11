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

    final corners = AppCorners.of(context);
    final themeName = appearance.theme.label;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: corners.circular(12),
        border: Border.all(
          color: AppColors.borderOf(context),
          width: 1,
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 10,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              Text(
                'ACCENT',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.textSecondary(context),
                ),
              ),
              // Theme default accent pill (Mockup: ★ Porch Amber)
              InkWell(
                key: const ValueKey('accent-theme'),
                onTap: () => appearance.setAccentOverride(null),
                borderRadius: corners.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: picked == null
                        ? themeAccent.withValues(alpha: 0.15)
                        : AppColors.surfaceContainerOf(context),
                    borderRadius: corners.circular(16),
                    border: Border.all(
                      color: picked == null
                          ? themeAccent
                          : AppColors.borderOf(context),
                      width: picked == null ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        size: 13,
                        color: picked == null
                            ? themeAccent
                            : AppColors.textSecondary(context),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$themeName Amber',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: picked == null
                              ? AppColors.textPrimary(context)
                              : AppColors.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Swatches list
              Wrap(
                spacing: 0,
                runSpacing: 0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
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
            ],
          ),
          Text(
            note,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 11,
            ),
          ),
        ],
      ),
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
