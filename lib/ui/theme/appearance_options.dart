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

/// Light, dark, or follow the operating system.
enum AppThemeMode {
  dark('dark', 'Dark'),
  light('light', 'Light'),
  system('system', 'Match system');

  const AppThemeMode(this.key, this.label);

  /// The stored preference value.
  final String key;
  final String label;

  static AppThemeMode fromKey(String? key) =>
      values.firstWhere((m) => m.key == key, orElse: () => dark);
}

/// The UI typeface. Every choice but [system] is bundled with the app.
enum UiFont {
  inter('inter', 'Inter', 'Inter'),
  system('system', 'System', null),
  atkinson('atkinson', 'Atkinson', 'Atkinson Hyperlegible Next'),
  literata('literata', 'Literata', 'Literata');

  const UiFont(this.key, this.label, this.fontFamily);

  /// The stored preference value.
  final String key;
  final String label;

  /// The bundled family, or null for the platform's own UI font.
  final String? fontFamily;

  static UiFont fromKey(String? key) =>
      values.firstWhere((f) => f.key == key, orElse: () => inter);
}

/// Corner roundness, one scale shared by cards, dialogs, bubbles and buttons.
enum UiCorners {
  sharp('sharp', 'Sharp', 0.25),
  standard('default', 'Default', 1),
  round('round', 'Round', 1.6);

  const UiCorners(this.key, this.label, this.scale);

  /// The stored preference value.
  final String key;
  final String label;

  /// Multiplies every themed radius; [standard] leaves today's radii as is.
  final double scale;

  static UiCorners fromKey(String? key) =>
      values.firstWhere((c) => c.key == key, orElse: () => standard);
}
