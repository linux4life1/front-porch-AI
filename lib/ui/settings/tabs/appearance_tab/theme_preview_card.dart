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

/// One theme in the Appearance grid: a miniature chat drawn in that theme's
/// own colors at the current brightness, with its name underneath.
class ThemePreviewCard extends StatelessWidget {
  const ThemePreviewCard({
    super.key,
    required this.theme,
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final AppThemeId theme;
  final AppPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final corners = AppCorners.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '${theme.label} theme',
      excludeSemantics: true,
      child: Material(
        color: palette.card,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: corners.circular(10),
          side: BorderSide(
            color: selected
                ? AppColors.porchAmberOf(context)
                : AppColors.borderOf(context),
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 64, child: _MiniChat(palette: palette)),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        theme.label,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (selected)
                      Icon(Icons.check_circle, size: 16, color: palette.amber)
                    else
                      Text(
                        theme.tag,
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A rail, two bubbles and an accent bar, in [palette]'s colors.
class _MiniChat extends StatelessWidget {
  const _MiniChat({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    Widget bar(Color color, double widthFactor, Alignment align) => Align(
      alignment: align,
      child: FractionallySizedBox(
        widthFactor: widthFactor,
        child: Container(
          height: 9,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 14,
          decoration: BoxDecoration(
            color: palette.surface,
            border: Border(right: BorderSide(color: palette.border)),
          ),
        ),
        Expanded(
          child: Container(
            color: palette.background,
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                bar(palette.chat.aiBubble, 0.62, Alignment.centerLeft),
                bar(palette.chat.userBubble, 0.45, Alignment.centerRight),
                bar(palette.amber, 0.3, Alignment.centerLeft),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
