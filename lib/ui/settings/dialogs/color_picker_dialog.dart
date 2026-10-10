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
import 'package:flex_color_picker/flex_color_picker.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Ink that stays legible over an arbitrary user-picked swatch (the swatches
/// and the current-color chips can be any hue, so no chrome color can
/// guarantee contrast).
Color swatchInkOn(Color bg) =>
    ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
    // theme-keep: contrast over a user-chosen color
    ? Colors.white
    // theme-keep: contrast over a user-chosen color
    : Colors.black87;

/// The one "Select Color" picker (Settings > Chat Appearance and the chat's
/// UI settings): [AppColors.presetColors] quick picks plus a color wheel, in
/// the warm-porch dialog.
Future<void> showColorPicker(
  BuildContext context,
  Color initialColor,
  void Function(Color) onChanged,
) async {
  Color selectedColor = initialColor;
  void Function(void Function())? setStateCallback;

  final picked = await showWarmDialogOf<Color>(
    context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        setStateCallback = setState;
        return WarmDialog(
          title: 'Select Color',
          icon: Icons.palette_outlined,
          accent: AppColors.porchAmberOf(context),
          width: 380,
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Preset colors row
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Quick Select',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary(context),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: AppColors.presetColors
                      .map(
                        (color) => GestureDetector(
                          onTap: () => Navigator.pop(context, color),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: color == selectedColor
                                    ? AppColors.porchAmberOf(context)
                                    : AppColors.borderOf(context),
                                width: 2,
                              ),
                            ),
                            child: color == selectedColor
                                ? Icon(
                                    Icons.check,
                                    size: 18,
                                    color: swatchInkOn(color),
                                  )
                                : null,
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 12),
                // Color picker - use wheel picker for full color spectrum
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ColorPicker(
                    color: selectedColor,
                    onColorChanged: (color) {
                      selectedColor = color;
                      setStateCallback?.call(() {});
                    },
                    wheelDiameter: 160,
                    pickersEnabled: const <ColorPickerType, bool>{
                      ColorPickerType.wheel: true,
                    },
                    showColorCode: true,
                    colorCodeHasColor: true,
                    copyPasteBehavior: const ColorPickerCopyPasteBehavior(
                      copyButton: true,
                      pasteButton: true,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          actions: [
            warmDialogCancel(context),
            warmDialogConfirm(
              context,
              label: 'OK',
              onPressed: () => Navigator.pop(context, selectedColor),
            ),
          ],
        );
      },
    ),
  );
  if (picked != null) {
    onChanged(picked);
  }
}
