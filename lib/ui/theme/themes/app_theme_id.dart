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

import '../app_palette.dart';
import 'evergreen_theme.dart';
import 'graphite_theme.dart';
import 'harbor_theme.dart';
import 'high_contrast_theme.dart';
import 'midnight_theme.dart';
import 'plum_theme.dart';
import 'slate_theme.dart';

/// The built-in app themes, in picker order.
enum AppThemeId {
  porch('porch', 'Porch', 'Default', 'Warm studio brown with porch amber.'),
  slate('slate', 'Slate', 'Classic', 'The cool navy look from before.'),
  graphite('graphite', 'Graphite', 'Neutral', 'Plain grey with the amber.'),
  midnight('midnight', 'Midnight', 'OLED', 'True black with teal.'),
  evergreen('evergreen', 'Evergreen', 'Warm', 'Deep pine with old gold.'),
  plum('plum', 'Plum', 'Cozy', 'Dark aubergine with rose.'),
  harbor('harbor', 'Harbor', 'Cool', 'Deep sea teal with coral.'),
  highContrast(
    'high_contrast',
    'High Contrast',
    'AAA',
    'Pure black or white, strongest contrast.',
  );

  const AppThemeId(this.key, this.label, this.tag, this.blurb);

  /// The stored preference value.
  final String key;
  final String label;

  /// A one-word character, shown on the picker card.
  final String tag;
  final String blurb;

  AppThemePalettes get palettes => switch (this) {
    porch => AppThemePalettes.porch,
    slate => slateTheme,
    graphite => graphiteTheme,
    midnight => midnightTheme,
    evergreen => evergreenTheme,
    plum => plumTheme,
    harbor => harborTheme,
    highContrast => highContrastTheme,
  };

  static AppThemeId fromKey(String? key) =>
      values.firstWhere((t) => t.key == key, orElse: () => porch);
}
