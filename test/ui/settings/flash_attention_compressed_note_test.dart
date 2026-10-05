// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Settings → Advanced → Advanced Launch Options. A compressed chat memory
// turns flash attention on wherever it can run (auto mode's rule, now every
// config's), so the Flash Attention switch could read off while KoboldCpp
// runs with it on. A line under the switch says so whenever that is the
// case. The real Settings page, with the real stored settings.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/services.dart';

import '../../helpers/settings_page_harness.dart';

void main() {
  Finder line() => find.text(kKoboldCompressedTurnsFlashOn);

  Future<SettingsPageRig> openLaunchOptions(
    WidgetTester tester, {
    required bool flash,
    required KvQuant cache,
  }) async {
    final rig = await mountSettings(
      tester,
      lastUsedIsB: true,
      before: (rig) async {
        await rig.store.backendSettings.setFlashAttentionEnabled(flash);
        await rig.store.backendSettings.setKvQuant(cache);
      },
    );
    await openTab(tester, 'Advanced');
    await tapVisible(tester, find.text('Advanced Launch Options'));
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    expect(find.text('Flash Attention'), findsOneWidget);
    return rig;
  }

  testWidgets('switched off with an 8-bit cache, the switch says the cache '
      'turns it on', (tester) async {
    await openLaunchOptions(tester, flash: false, cache: KvQuant.q8_0);

    expect(line(), findsOneWidget);
  });

  testWidgets('switched on, or with a full-size cache, nothing more is '
      'said', (tester) async {
    final rig = await openLaunchOptions(
      tester,
      flash: true,
      cache: KvQuant.q4_0,
    );
    expect(line(), findsNothing);

    await tester.runAsync(
      () => rig.store.backendSettings.setFlashAttentionEnabled(false),
    );
    await settle(tester);
    expect(line(), findsOneWidget, reason: 'switched off: the cache rules');

    await tester.runAsync(
      () => rig.store.backendSettings.setKvQuant(KvQuant.f16),
    );
    await settle(tester);
    expect(line(), findsNothing, reason: 'a full-size cache: the switch rules');
  });
}
