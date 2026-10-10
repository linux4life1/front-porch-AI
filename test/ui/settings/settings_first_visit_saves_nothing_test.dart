// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Opening Settings for the first time must not save an acceleration choice
// the user never made. On an NVIDIA card it used to save CUDA, on a Mac
// Metal, each with a "… enabled" toast, so a fresh install read "Manual".
// Nothing is saved now: the launch resolves the card itself, Settings shows
// "Automatic — …", and only a real pick in the override is stored. (The AMD
// card's twin is settings_amd_acceleration_test.dart.)
//
// The real Settings page and storage (see settings_page_harness.dart).

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/services.dart';

import '../../helpers/settings_page_harness.dart';

final _rtx = HardwareInfo(
  gpuName: 'NVIDIA GeForce RTX 4070',
  vramMb: 12282,
  ramMb: 32000,
  vendor: 'Nvidia',
  hasCuda: true,
  linuxDistro: 'ubuntu',
);

final _mac = HardwareInfo(
  gpuName: 'Apple M2 Pro',
  vramMb: 21845,
  ramMb: 32768,
  vendor: 'Apple',
  hasMetal: true,
);

List<bool?> _switches(SettingsPageRig rig) {
  final b = rig.store.backendSettings;
  return [b.useCublas, b.useVulkan, b.useMetal, b.useRocm];
}

void main() {
  for (final (label, hw, shown) in [
    ('an NVIDIA card', _rtx, 'CUDA (NVIDIA GPU detected)'),
    ('a Mac', _mac, 'Metal (Apple Silicon)'),
  ]) {
    testWidgets('on $label the first visit saves nothing and says nothing', (
      tester,
    ) async {
      final rig = await mountSettings(tester, lastUsedIsB: false, hardware: hw);
      await openTab(tester, 'Advanced');
      expect(_switches(rig), [null, null, null, null]);
      expect(find.textContaining('enabled'), findsNothing, reason: 'a toast');
      expect(find.text('Acceleration: Automatic — $shown'), findsOneWidget);
    });
  }

  testWidgets('a choice the user made stays theirs after a visit', (
    tester,
  ) async {
    final rig = await mountSettings(
      tester,
      lastUsedIsB: false,
      hardware: _rtx,
      before: (rig) async {
        final b = rig.store.backendSettings;
        await b.setUseCublas(false);
        await b.setUseVulkan(true);
        await b.setUseMetal(false);
        await b.setUseRocm(false);
      },
    );
    await openTab(tester, 'Advanced');
    expect(_switches(rig), [false, true, false, false]);
    expect(
      find.text('Acceleration: Manual — Vulkan (Nvidia GPU detected)'),
      findsOneWidget,
    );
  });
}
