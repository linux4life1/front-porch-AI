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

import 'package:flutter/material.dart' show Brightness, Color;

import 'package:front_porch_ai/services/storage/storage.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// The desktop's resolved app theme for the web: its mode and both token
/// maps. Rides the settings snapshot as `theme` and every
/// `settings_changed` event, so the PWA repaints without asking. Additive:
/// an older PWA ignores the key.
Map<String, Object> webThemeWire(AppearanceSettings appearance) =>
    WebThemeTokens.wire(
      appearance.resolvedPalettes(),
      isDark: appearance.isDark,
    );

/// The tokens a theme card previews: the miniature chat's rail, ground, card,
/// two bubbles, accent bar and labels. The host resolves them per theme so
/// the web gallery paints each card without any colour math of its own.
const List<String> kWebThemePreviewTokens = [
  'bg',
  'surface',
  'card',
  'border',
  'text',
  'muted',
  'user-bubble',
  'ai-bubble',
  'porch-amber',
];

/// The appearance choices the web's Appearance tab edits, with the catalogs
/// it renders. Rides the snapshot and every `settings_changed` as
/// `appearance`, so a browser tab and the desktop stay one setting. Additive:
/// an older PWA ignores the key.
///
/// `accent` is null for the theme's own accent and `#RRGGBB` otherwise — the
/// same shape the desktop picker writes. `chatColors` are the colours the
/// chat actually paints (a pick, else the theme's default) and
/// `chatColorDefaults` the theme's own, so the PWA can leave an unpicked role
/// to the theme instead of pinning today's brightness.
Map<String, Object?> appearanceWire(
  AppearanceSettings appearance,
  UiSettings ui,
) {
  final defaults = appearance.chatDefaults;
  String hex(Color c) => accentHex(c);
  return {
    'themeId': appearance.theme.key,
    'accent': switch (appearance.accentOverride) {
      final pick? => hex(pick),
      null => null,
    },
    'accentAdjusted': appearance.accentAdjusted,
    'accentSwatches': [for (final c in kAccentSwatches) hex(c)],
    'uiFont': appearance.font.key,
    'uiFontFamily': appearance.font.fontFamily,
    'corners': appearance.corners.key,
    'cornerScale': appearance.corners.scale,
    'chatFont': ui.globalChatFontFamily,
    'chatFontChoices': [
      for (final (label, family) in kChatFontChoices)
        {'label': label, 'family': family},
    ],
    'chatColors': {
      'userBubble': hex(ui.globalUserBubbleColor),
      'userText': hex(ui.globalUserTextColor),
      'aiBubble': hex(ui.globalAiBubbleColor),
      'aiText': hex(ui.globalAiTextColor),
      'dialogue': hex(ui.globalDialogueColor),
      'action': hex(ui.globalActionColor),
    },
    'chatColorDefaults': {
      'userBubble': hex(defaults.userBubble),
      'userText': hex(defaults.userText),
      'aiBubble': hex(defaults.aiBubble),
      'aiText': hex(defaults.aiText),
      'dialogue': hex(defaults.dialogue),
      'action': hex(defaults.action),
    },
    'gallery': themeGalleryWire(appearance),
  };
}

/// Every built-in theme as the web's gallery card needs it: its name, tag,
/// blurb and the preview tokens at both brightnesses, resolved host-side.
/// Each card previews the user's custom accent, as the desktop grid does.
List<Map<String, Object>> themeGalleryWire(AppearanceSettings appearance) => [
  for (final theme in AppThemeId.values)
    {
      'key': theme.key,
      'label': theme.label,
      'tag': theme.tag,
      'blurb': theme.blurb,
      'dark': _previewTokens(
        appearance.palettesFor(theme).dark,
        Brightness.dark,
      ),
      'light': _previewTokens(
        appearance.palettesFor(theme).light,
        Brightness.light,
      ),
    },
];

Map<String, String> _previewTokens(AppPalette palette, Brightness brightness) {
  final all = WebThemeTokens.resolve(palette, brightness);
  return {for (final key in kWebThemePreviewTokens) key: all[key]!};
}
