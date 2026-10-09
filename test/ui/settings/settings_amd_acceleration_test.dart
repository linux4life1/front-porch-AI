// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// An AMD card on Linux, as detection now reports it. Opening Settings used to
// save an acceleration choice by itself (Vulkan, or ROCm whenever rocminfo
// answered) and say "Vulkan enabled", so a fresh install read "Manual".
// Automatic stays automatic: nothing is saved until the user picks, and
// Automatic (or "Reset to Automatic") runs Vulkan on the card, never the
// processor. ROCm is only ever a choice.
//
// The real Settings page and storage (see settings_page_harness.dart).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/services.dart';

import '../../helpers/settings_page_harness.dart';

final _rx6900xt = HardwareInfo(
  gpuName: 'AMD Radeon RX 6900 XT',
  vramMb: 16368,
  ramMb: 64000,
  vendor: 'AMD',
  hasRocm: true,
  linuxDistro: 'debian',
);

List<bool?> _switches(SettingsPageRig rig) {
  final b = rig.store.backendSettings;
  return [b.useCublas, b.useVulkan, b.useMetal, b.useRocm];
}

Future<void> _openOverride(WidgetTester tester) async {
  await openTab(tester, 'Advanced');
  await tapVisible(tester, find.text('Advanced: manual backend override'));
  await tester.pump(const Duration(milliseconds: 400));
  await settle(tester);
}

void main() {
  testWidgets('the first visit saves no acceleration choice and says nothing', (
    tester,
  ) async {
    final rig = await mountSettings(
      tester,
      lastUsedIsB: false,
      hardware: _rx6900xt,
    );
    await openTab(tester, 'Advanced');
    expect(_switches(rig), [null, null, null, null]);
    expect(find.textContaining('enabled'), findsNothing, reason: 'a toast');
    expect(
      find.text('Acceleration: Automatic — Vulkan (AMD GPU detected)'),
      findsOneWidget,
    );
  });

  testWidgets('Reset to Automatic after picking ROCm runs Vulkan on the card', (
    tester,
  ) async {
    final rig = await mountSettings(
      tester,
      lastUsedIsB: false,
      hardware: _rx6900xt,
    );
    await _openOverride(tester);
    await tapVisible(tester, find.widgetWithText(FilterChip, 'Use ROCm (AMD)'));
    await settle(tester);
    expect(_switches(rig), [false, false, false, true]);
    expect(
      find.text('Acceleration: Manual — ROCm (expert override)'),
      findsOneWidget,
    );

    await tapVisible(tester, find.text('Reset to Automatic'));
    await settle(tester);
    expect(_switches(rig), [null, null, null, null]);
    expect(
      find.text('Acceleration: Automatic — Vulkan (AMD GPU detected)'),
      findsOneWidget,
    );
  });
}
