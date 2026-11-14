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

// The web Settings POST's Appearance branches, split out of [SettingsWriter]
// because that file sits near the size limit. Each key mirrors the desktop
// control it belongs to, and an unknown value is ignored rather than stored
// (the desktop's pickers only offer keys the build knows; an older phone may
// send one it does not). The setters own validation and notification.

import 'package:flutter/material.dart' show Color;

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// Applies the Appearance tab's keys of a web Settings POST body: the theme
/// gallery pick, the accent (theme default or a custom `#RRGGBB`), the UI
/// font, corners, the reset, the chat font and the six chat colours. Additive
/// — an older PWA ignores every key.
Future<void> applyAppearanceWrite(
  StorageService storage,
  Map<String, dynamic> body,
) async {
  final appearance = storage.appearance;

  final themeId = body['themeId'];
  if (themeId is String && AppThemeId.values.any((t) => t.key == themeId)) {
    await appearance.setTheme(AppThemeId.fromKey(themeId));
  }

  // An empty or malformed string is the theme's own accent; the picker's
  // "theme accent" swatch sends ''.
  final accent = body['accent'];
  if (accent is String) {
    await appearance.setAccentOverride(parseAccentHex(accent));
  }

  final font = body['uiFont'];
  if (font is String && UiFont.values.any((f) => f.key == font)) {
    await appearance.setFont(UiFont.fromKey(font));
  }

  // The wire key is the stored one: `default` for the standard corners, not
  // the enum's name.
  final corners = body['corners'];
  if (corners is String && UiCorners.values.any((c) => c.key == corners)) {
    await appearance.setCorners(UiCorners.fromKey(corners));
  }

  // Clears the accent, font and corner picks; the theme and mode stay.
  if (body['resetAppearance'] == true) {
    await appearance.resetCustomisations();
  }

  final ui = storage.uiSettings;
  final chatFont = body['chatFont'];
  if (chatFont is String && isChatFontFamily(chatFont)) {
    await ui.setGlobalChatFontFamily(chatFont);
  }

  // One colour at a time, as the desktop's six rows are. Each writes for the
  // brightness on screen, exactly like the desktop's ColorRows.
  final colors = body['chatColors'];
  if (colors is Map) {
    final setters = <String, Future<void> Function(Color)>{
      'userBubble': ui.setGlobalUserBubbleColor,
      'userText': ui.setGlobalUserTextColor,
      'aiBubble': ui.setGlobalAiBubbleColor,
      'aiText': ui.setGlobalAiTextColor,
      'dialogue': ui.setGlobalDialogueColor,
      'action': ui.setGlobalActionColor,
    };
    for (final MapEntry(key: key, value: set) in setters.entries) {
      final color = parseAccentHex(colors[key]?.toString());
      if (color != null) await set(color);
    }
  }

  // "Use the theme's chat colors": forget this brightness's picks.
  if (body['resetChatColors'] == true) await ui.resetChatColors();
}
