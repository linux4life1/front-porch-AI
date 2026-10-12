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

/// Sort modes the home grid offers: (mode key, menu label).
const kHomeToolbarSortItems = <(String, String)>[
  ('name', 'Name (A\u2192Z)'),
  ('recent', 'Recent Activity'),
  ('importDate', 'Import Date'),
  ('messages', 'Messages Sent'),
];

/// The toolbar's sort control: a labeled dropdown, or an icon-only menu
/// when [labeled] is false (narrow windows).
class HomeToolbarSortControl extends StatelessWidget {
  const HomeToolbarSortControl({
    super.key,
    required this.sortMode,
    required this.labeled,
    required this.onSortChanged,
  });

  final String sortMode;
  final bool labeled;
  final void Function(String mode) onSortChanged;

  @override
  Widget build(BuildContext context) {
    if (!labeled) {
      return PopupMenuButton<String>(
        tooltip:
            'Sort: ${kHomeToolbarSortItems.where((e) => e.$1 == sortMode).firstOrNull?.$2 ?? sortMode}',
        icon: Icon(
          Icons.sort,
          size: 18,
          color: AppColors.iconSecondary(context),
        ),
        initialValue: sortMode,
        color: AppColors.surfaceContainerOf(context),
        onSelected: onSortChanged,
        itemBuilder: (_) => [
          for (final item in kHomeToolbarSortItems)
            PopupMenuItem(value: item.$1, child: Text(item.$2)),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: sortMode,
          icon: Icon(
            Icons.sort,
            size: 18,
            color: AppColors.iconSecondary(context),
          ),
          dropdownColor: AppColors.surfaceContainerOf(context),
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 13,
          ),
          isDense: true,
          items: [
            for (final item in kHomeToolbarSortItems)
              DropdownMenuItem(value: item.$1, child: Text(item.$2)),
          ],
          onChanged: (value) {
            if (value != null) onSortChanged(value);
          },
        ),
      ),
    );
  }
}

/// The grid card-size slider.
class HomeToolbarScaleSlider extends StatelessWidget {
  const HomeToolbarScaleSlider({
    super.key,
    required this.gridScale,
    required this.onChanged,
    this.onChangeEnd,
  });

  final double gridScale;
  final void Function(double scale) onChanged;
  final void Function(double scale)? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SizedBox(
        width: 100,
        child: Row(
          children: [
            Icon(
              Icons.grid_view,
              size: 16,
              color: AppColors.iconSecondary(context),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                  activeTrackColor: AppColors.porchHoneyOf(
                    context,
                  ).withValues(alpha: 0.7),
                  inactiveTrackColor: AppColors.borderOf(
                    context,
                  ).withValues(alpha: 0.4),
                  thumbColor: AppColors.porchHoneyOf(context),
                ),
                child: Slider(
                  value: gridScale,
                  min: 150,
                  max: 450,
                  onChanged: (v) => onChanged(v),
                  onChangeEnd: (v) => onChangeEnd?.call(v),
                ),
              ),
            ),
            Icon(
              Icons.view_module,
              size: 16,
              color: AppColors.iconSecondary(context),
            ),
          ],
        ),
      ),
    );
  }
}
