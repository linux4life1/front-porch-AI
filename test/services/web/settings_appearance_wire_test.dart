// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The web's Appearance tab edits host settings. This pins the wire that
// carries them: the picks, the catalogs it renders, and the per-theme
// preview tokens the gallery cards paint — resolved here, never in
// TypeScript. Additive contract: an older PWA ignores the whole `appearance`
// key.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/storage/settings/appearance_settings.dart';
import 'package:front_porch_ai/services/storage/settings/ui_settings.dart';
import 'package:front_porch_ai/services/web/facade/settings/settings.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<(AppearanceSettings, UiSettings)> _settings() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final appearance = AppearanceSettings()..initializeBase(prefs, () {});
  appearance.load();
  final ui = UiSettings(appearance)..initializeBase(prefs, () {});
  ui.load();
  return (appearance, ui);
}

void main() {
  test(
    'the wire carries the desktop picks and the catalogs to render',
    () async {
      final (appearance, ui) = await _settings();
      final w = appearanceWire(appearance, ui);

      expect(w['themeId'], 'porch');
      expect(w['accent'], isNull);
      expect(w['accentAdjusted'], isFalse);
      expect(w['uiFont'], 'inter');
      expect(w['uiFontFamily'], 'Inter');
      expect(w['corners'], 'default');
      expect(w['cornerScale'], 1);
      expect(w['chatFont'], '');
      expect(w['accentSwatches'], [
        for (final c in kAccentSwatches) accentHex(c),
      ]);

      final choices = w['chatFontChoices']! as List;
      expect(choices, hasLength(kChatFontChoices.length));
      expect((choices.first as Map)['label'], 'Same as the UI font');
      expect((choices.first as Map)['family'], '');

      final gallery = w['gallery']! as List;
      expect(gallery, hasLength(AppThemeId.values.length));
      expect(gallery.map((g) => (g as Map)['key']), [
        for (final t in AppThemeId.values) t.key,
      ]);
    },
  );

  test(
    'each gallery card previews its own theme, not the active one',
    () async {
      final (appearance, ui) = await _settings();
      await appearance.setTheme(AppThemeId.harbor);
      final gallery = appearanceWire(appearance, ui)['gallery']! as List;
      for (final card in gallery.cast<Map<String, Object>>()) {
        final theme = AppThemeId.fromKey(card['key'] as String?);
        for (final (brightness, map) in [
          (Brightness.dark, card['dark']! as Map),
          (Brightness.light, card['light']! as Map),
        ]) {
          expect(
            map.keys.toSet(),
            kWebThemePreviewTokens.toSet(),
            reason: '${theme.key} ${brightness.name}',
          );
          expect(
            map['bg'],
            WebThemeTokens.css(
              brightness == Brightness.dark
                  ? theme.palettes.dark.background
                  : theme.palettes.light.background,
            ),
            reason: '${theme.key} ${brightness.name} bg',
          );
        }
      }
    },
  );

  test('a custom accent reaches the picks and every card', () async {
    final (appearance, ui) = await _settings();
    await appearance.setAccentOverride(const Color(0xFF2E7D32));
    final w = appearanceWire(appearance, ui);
    expect(w['accent'], '#2E7D32');
    final gallery = w['gallery']! as List;
    for (final card in gallery.cast<Map<String, Object>>()) {
      final theme = AppThemeId.fromKey(card['key'] as String?);
      expect(
        (card['dark']! as Map)['porch-amber'],
        WebThemeTokens.css(appearance.palettesFor(theme).dark.amber),
        reason: '${theme.key} dark accent',
      );
      expect(
        (card['light']! as Map)['porch-amber'],
        WebThemeTokens.css(appearance.palettesFor(theme).light.amber),
        reason: '${theme.key} light accent',
      );
      expect(
        (card['dark']! as Map)['porch-amber'],
        isNot(WebThemeTokens.css(theme.palettes.dark.amber)),
        reason: '${theme.key} shows the pick, not the theme accent',
      );
    }
  });

  test('labels ride the card and the system font has no family', () async {
    final (appearance, ui) = await _settings();
    await appearance.setFont(UiFont.system);
    final w = appearanceWire(appearance, ui);
    expect(w['uiFont'], 'system');
    expect(w['uiFontFamily'], isNull);
    final porch = (w['gallery']! as List).cast<Map<String, Object>>().first;
    expect(porch['label'], 'Porch');
    expect(porch['tag'], 'Default');
    expect(porch['blurb'], isNotEmpty);
  });

  test('a faint accent is reported as adjusted for readability', () async {
    final (appearance, ui) = await _settings();
    // Near-black on a dark theme cannot read; the desktop nudges it.
    await appearance.setAccentOverride(const Color(0xFF111111));
    expect(appearance.accentAdjusted, isTrue);
    expect(appearanceWire(appearance, ui)['accentAdjusted'], isTrue);
  });

  test('chat colours are the resolved paints, defaults kept apart', () async {
    final (appearance, ui) = await _settings();
    var w = appearanceWire(appearance, ui);
    expect(w['chatColors'], w['chatColorDefaults']);

    await ui.setGlobalAiBubbleColor(const Color(0xFF101010));
    w = appearanceWire(appearance, ui);
    expect((w['chatColors']! as Map)['aiBubble'], '#101010');
    expect(
      (w['chatColorDefaults']! as Map)['aiBubble'],
      accentHex(appearance.chatDefaults.aiBubble),
    );

    // The picks are per brightness, as the desktop's own controls are.
    await appearance.setMode(AppThemeMode.light);
    w = appearanceWire(appearance, ui);
    expect(
      (w['chatColors']! as Map)['aiBubble'],
      accentHex(appearance.chatDefaults.aiBubble),
    );
  });
}
