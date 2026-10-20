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

// App themes, end to end: a user opens Settings → Appearance, picks Harbor,
// Light, a custom accent, Literata and Round corners with real taps, and the
// whole app's ThemeData follows each pick. Then the settings layer reloads
// from the same preferences, as a restart would, and every pick is still
// there.
//
// Run it with:
//   flutter test integration_test/app_theme_test.dart -d linux
//
// Isolation contract: identical to app_smoke_test.dart (sandboxed paths,
// mock prefs, fake OpenAI-compatible backend as a PseudoRemote).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:front_porch_ai/main.dart' as app;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/appearance_settings.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/ui/pages/pages.dart' show SettingsPage;
import 'package:front_porch_ai/ui/theme/theme.dart';

import 'support/e2e_sandbox.dart';
import 'support/fake_backend.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a theme picked in Settings repaints the app and survives a '
      'reload — sandboxed', (tester) async {
    try {
      final probe = await Socket.connect(
        InternetAddress.loopbackIPv4,
        5001,
        timeout: const Duration(milliseconds: 500),
      );
      probe.destroy();
      fail(
        'Something is listening on 127.0.0.1:5001 (a real KoboldCpp?). '
        'Close it before running the E2E suite.',
      );
    } on SocketException {
      // Nothing there — safe to proceed.
    }

    final sandbox = Directory.systemTemp.createTempSync('fpai_app_theme_');
    PathProviderPlatform.instance = SandboxPathProvider(sandbox.path);
    final backend = await FakeBackendServer.start(
      replyPieces: const ['the theme suite is not chatting'],
    );
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'import_llmerta_porch_memories': false,
      'backend_type': 'openRouter',
      'remote_api_url': '${backend.baseUrl}/v1',
      'remote_model_name': 'smoke-model',
    });

    app.main(const []);
    await pumpUntilFound(tester, find.byType(MainLayout));
    try {
      await windowManager.setSize(const Size(1200, 800));
    } catch (e) {
      debugPrint('[e2e] window_manager sizing skipped: $e');
    }
    await tester.pump(const Duration(seconds: 2));

    final ctx = tester.element(find.byType(MainLayout));
    final storage = Provider.of<StorageService>(ctx, listen: false);
    ThemeData live() => Theme.of(tester.element(find.byType(MainLayout)));

    expect(live().scaffoldBackgroundColor, AppPalette.porchDark.background);

    // ignore: use_build_context_synchronously — root MainLayout element.
    Navigator.of(
      ctx,
    ).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
    await pumpUntilFound(tester, find.text('Appearance'));
    await tester.tap(find.text('Appearance'));
    await pumpUntilFound(
      tester,
      find.byKey(const ValueKey('theme-card-harbor')),
    );

    Future<void> tapAndSettle(Finder f) async {
      await tester.ensureVisible(f);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(f);
      // Long enough for the theme's lerp animation to land.
      await tester.pump(const Duration(milliseconds: 600));
    }

    final harbor = AppThemeId.harbor.palettes;
    await tapAndSettle(find.byKey(const ValueKey('theme-card-harbor')));
    expect(storage.appearance.theme, AppThemeId.harbor);
    expect(live().scaffoldBackgroundColor, harbor.dark.background);
    expect(live().extension<AppThemePalettes>(), harbor);

    await tapAndSettle(find.text('Light'));
    expect(storage.appearance.mode, AppThemeMode.light);
    expect(live().brightness, Brightness.light);
    expect(live().scaffoldBackgroundColor, harbor.light.background);

    const violet = Color(0xFFA78BFA);
    await tapAndSettle(find.byKey(ValueKey('accent-${accentHex(violet)}')));
    final fitted = fitAccent(violet, harbor.light, dark: false);
    expect(storage.appearance.accentOverride, violet);
    expect(live().colorScheme.primary, fitted.accent);
    expect(
      find.text('Custom accent, adjusted for readability'),
      findsOneWidget,
    );

    await tapAndSettle(find.text('Literata'));
    expect(live().textTheme.bodyMedium?.fontFamily, 'Literata');
    await tapAndSettle(find.text('Round'));
    expect(live().extension<AppCorners>()?.corners, UiCorners.round);

    // A restart: a fresh settings layer over the same preferences.
    final reloaded = AppearanceSettings()
      ..initializeBase(await SharedPreferences.getInstance(), () {})
      ..load();
    expect(reloaded.theme, AppThemeId.harbor);
    expect(reloaded.mode, AppThemeMode.light);
    expect(reloaded.accentOverride, violet);
    expect(reloaded.font, UiFont.literata);
    expect(reloaded.corners, UiCorners.round);
    expect(reloaded.resolvedPalettes(), storage.appearance.resolvedPalettes());

    // Reset brings back the theme's own accent, font and corners.
    await tapAndSettle(find.byKey(const ValueKey('appearance-reset')));
    expect(live().colorScheme.primary, harbor.light.amber);
    expect(live().textTheme.bodyMedium?.fontFamily, 'Inter');
    expect(live().extension<AppCorners>()?.corners, UiCorners.standard);

    await backend.close();
  });
}
