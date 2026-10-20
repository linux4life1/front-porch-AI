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

// App theme settings: what survives a restart, the move from the old
// dark_mode switch to Dark / Light / Match system, and chat colors that
// follow the theme until the user picks their own.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/app/launch_window.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/appearance_settings.dart';
import 'package:front_porch_ai/services/storage/settings/ui_settings.dart';
import 'package:front_porch_ai/services/storage/settings/user_bubble_dialogue.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

import '../golden/support/creator_test_support.dart';

/// A fresh app start on [values]: both settings objects wired as
/// StorageService wires them.
Future<(AppearanceSettings, UiSettings)> _boot([
  Map<String, Object> values = const {},
]) async {
  final probe = AppearanceSettings();
  SharedPreferences.setMockInitialValues({
    for (final e in values.entries) probe.k(e.key): e.value,
  });
  return _reload();
}

Future<(AppearanceSettings, UiSettings)> _reload() async {
  final prefs = await SharedPreferences.getInstance();
  final appearance = AppearanceSettings()..initializeBase(prefs, () {});
  final ui = UiSettings(appearance)..initializeBase(prefs, () {});
  appearance.load();
  ui.load();
  return (appearance, ui);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a first run is Porch, dark, with no customisations', () async {
    final (a, ui) = await _boot();
    expect(a.theme, AppThemeId.porch);
    expect(a.mode, AppThemeMode.dark);
    expect(a.accentOverride, isNull);
    expect(a.font, UiFont.inter);
    expect(a.corners, UiCorners.standard);
    expect(a.resolvedPalettes(), AppThemePalettes.porch);
    expect(ui.isDark, isTrue);
  });

  test('the old Dark Mode switch carries over and stays in step', () async {
    final (a, ui) = await _boot({'dark_mode': false});
    expect(a.mode, AppThemeMode.light);
    expect(ui.isDark, isFalse);

    await a.setMode(AppThemeMode.dark);
    final prefs = await SharedPreferences.getInstance();
    // An older build reading only dark_mode opens in the same brightness.
    expect(prefs.getBool(a.k('dark_mode')), isTrue);
    await ui.setIsDark(false);
    expect(a.mode, AppThemeMode.light);
    expect(prefs.getBool(a.k('dark_mode')), isFalse);
  });

  test('every choice survives a restart', () async {
    final (a, _) = await _boot();
    await a.setTheme(AppThemeId.harbor);
    await a.setMode(AppThemeMode.system);
    await a.setAccentOverride(const Color(0xFFA78BFA));
    await a.setFont(UiFont.atkinson);
    await a.setCorners(UiCorners.round);

    final (b, _) = await _reload();
    expect(b.theme, AppThemeId.harbor);
    expect(b.mode, AppThemeMode.system);
    expect(b.accentOverride, const Color(0xFFA78BFA));
    expect(b.font, UiFont.atkinson);
    expect(b.corners, UiCorners.round);
    expect(
      b.resolvedPalettes().dark.background,
      AppThemeId.harbor.palettes.dark.background,
    );
    expect(b.resolvedPalettes().dark.amber, const Color(0xFFA78BFA));

    await b.resetCustomisations();
    final (c, _) = await _reload();
    expect(c.theme, AppThemeId.harbor);
    expect(c.mode, AppThemeMode.system);
    expect(c.accentOverride, isNull);
    expect(c.font, UiFont.inter);
    expect(c.corners, UiCorners.standard);
  });

  test('Match system follows the OS and tells the app', () async {
    var notified = 0;
    final (a, ui) = await _boot({'theme_mode': 'system'});
    a.setPlatformBrightness(Brightness.light);
    a.initializeBase(await SharedPreferences.getInstance(), () => notified++);
    a.setPlatformBrightness(Brightness.dark);
    expect(ui.isDark, isTrue);
    a.setPlatformBrightness(Brightness.light);
    expect(ui.isDark, isFalse);
    expect(notified, 2);

    await a.setMode(AppThemeMode.light);
    notified = 0;
    a.setPlatformBrightness(Brightness.light);
    a.setPlatformBrightness(Brightness.dark);
    expect(notified, 0, reason: 'a fixed mode ignores the OS');
    expect(ui.isDark, isFalse);
  });

  test('unpicked chat colors follow the theme; picked ones win', () async {
    final (a, ui) = await _boot();
    expect(ui.globalUserBubbleColor, ChatDefaultColors.porchDark.userBubble);
    expect(ui.globalDialogueColorChosen, isFalse);

    await a.setTheme(AppThemeId.plum);
    expect(
      ui.globalUserBubbleColor,
      AppThemeId.plum.palettes.dark.chat.userBubble,
    );
    expect(ui.globalAiBubbleColor, AppThemeId.plum.palettes.dark.chat.aiBubble);
    expect(ui.getActionColor(null), AppThemeId.plum.palettes.dark.chat.action);
    await a.setMode(AppThemeMode.light);
    expect(
      ui.globalAiBubbleColor,
      AppThemeId.plum.palettes.light.chat.aiBubble,
    );

    const mine = Color(0xFF10B981);
    await ui.setGlobalAiBubbleColor(mine);
    await ui.setGlobalDialogueColor(mine);
    expect(ui.globalDialogueColorChosen, isTrue);
    await a.setTheme(AppThemeId.slate);
    expect(ui.globalAiBubbleColor, mine);
    // A pick is per mode: dark still follows the theme.
    await a.setMode(AppThemeMode.dark);
    expect(
      ui.globalAiBubbleColor,
      AppThemeId.slate.palettes.dark.chat.aiBubble,
    );

    await a.setMode(AppThemeMode.light);
    await ui.resetChatColors();
    expect(
      ui.globalAiBubbleColor,
      AppThemeId.slate.palettes.light.chat.aiBubble,
    );
    final (_, reloaded) = await _reload();
    expect(reloaded.globalDialogueColorChosen, isFalse);
  });

  testWidgets('the first frame is already in the saved theme', (tester) async {
    setupPathProviderMock();
    await _boot({
      'app_theme': 'harbor',
      'theme_mode': 'light',
      'ui_font': 'literata',
    });
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(bootPrefs: prefs);
    addTearDown(storage.dispose);
    // Read before the async settings load has run: this is what MyApp's
    // first build and the native window background see.
    expect(storage.appearance.theme, AppThemeId.harbor);
    expect(storage.appearance.mode, AppThemeMode.light);
    expect(storage.appearance.font, UiFont.literata);
    expect(
      launchBackground(prefs),
      AppThemeId.harbor.palettes.light.background,
    );
  });

  test(
    'action text in the user bubble reads in every theme until picked',
    () async {
      final (a, ui) = await _boot();
      for (final theme in AppThemeId.values) {
        await a.setTheme(theme);
        for (final mode in [AppThemeMode.dark, AppThemeMode.light]) {
          await a.setMode(mode);
          expect(
            contrastRatio(
              ui.userBubbleActionColorFor(null),
              ui.globalUserBubbleColor,
            ),
            greaterThanOrEqualTo(3.0),
            reason: '${theme.label} ${mode.label}',
          );
        }
      }
      const mine = Color(0xFF90CAF9);
      await ui.setGlobalActionColor(mine);
      expect(ui.userBubbleActionColorFor(null), mine);
    },
  );
}
