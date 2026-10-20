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
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'theme_preview_card.dart';

/// The eight built-in themes as preview cards: four across on a wide window,
/// fewer as it narrows. Each card shows the user's custom accent, if any, so
/// the grid previews what picking it would look like.
class ThemeCardGrid extends StatelessWidget {
  const ThemeCardGrid({super.key});

  static const double _gap = 12;

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<StorageService>().appearance;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 170).floor().clamp(1, 4);
        final width = (constraints.maxWidth - _gap * (columns - 1)) / columns;
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final theme in AppThemeId.values)
              SizedBox(
                width: width,
                child: ThemePreviewCard(
                  key: ValueKey('theme-card-${theme.key}'),
                  theme: theme,
                  palette: appearance.isDark
                      ? appearance.palettesFor(theme).dark
                      : appearance.palettesFor(theme).light,
                  selected: theme == appearance.theme,
                  onTap: () => appearance.setTheme(theme),
                ),
              ),
          ],
        );
      },
    );
  }
}
