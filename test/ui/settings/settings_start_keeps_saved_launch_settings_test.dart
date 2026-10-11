// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Start Backend launches from what is saved. It used to write the page's own
// copy of the context, the GPU layers and the four acceleration switches
// into storage first, and that copy is older than the card, the phone and
// "Reset to Automatic":
//  - a context chosen on the Local model card was put back to the old one;
//  - "Reset to Automatic" followed by Start wrote four "off" switches, which
//    is "CPU only", not automatic;
//  - a GPU layer count typed on the Advanced tab was never saved.
//
// The real Settings page and the real launch; only the engine start is
// recorded (see settings_page_harness.dart).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/gpu_backend_resolver.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../helpers/settings_page_harness.dart';

/// What the launch would stage for the start the engine was just given: the
/// code every launch uses, on the switches as the page left them in storage.
Future<Map<String, dynamic>> stagedConfigFor(
  WidgetTester tester,
  SettingsPageRig rig,
  HardwareInfo hardware,
) async {
  final s = rig.kobold.starts.single;
  return (await tester.runAsync(
    () => koboldLaunchMap(
      storage: rig.store,
      modelPath: s.model,
      kcppsPath: s.kcpps,
      mmprojPath: null,
      gpuLayers: s.layers,
      contextSize: s.context,
      useVulkan: s.vulkan,
      useCublas: s.cublas,
      useMetal: s.metal,
      useRocm: s.rocm,
      hardware: hardware,
    ),
  ))!;
}

GpuBackend resolvedOn(SettingsPageRig rig, HardwareInfo hw) {
  final b = rig.store.backendSettings;
  return GpuBackendResolver.resolve(
    userCublas: b.useCublas,
    userVulkan: b.useVulkan,
    userRocm: b.useRocm,
    userMetal: b.useMetal,
    hasCuda: hw.hasCuda,
    vendor: hw.vendor,
    onMac: false,
  );
}

List<bool?> switchesOf(SettingsPageRig rig) {
  final b = rig.store.backendSettings;
  return [b.useCublas, b.useVulkan, b.useMetal, b.useRocm];
}

void main() {
  testWidgets('a context chosen on the Local model card survives Start', (
    tester,
  ) async {
    final rig = await mountSettings(tester, lastUsedIsB: false);
    await openTab(tester, 'Backend');
    final chip = find.descendant(
      of: find.byKey(const ValueKey('local-model-context')),
      matching: find.text('32,768'),
    );
    await settle(tester, () => chip.evaluate().isNotEmpty);
    await tapVisible(tester, chip);
    await settle(tester);
    expect(rig.store.backendSettings.contextSize, 32768);

    await tapVisible(tester, find.text('Start Backend'));
    await settle(tester, () => rig.kobold.starts.isNotEmpty);

    expect(
      rig.store.backendSettings.contextSize,
      32768,
      reason: 'Start wrote the page\'s older context over the card\'s',
    );
    expect(rig.kobold.starts.single.context, 32768);
  });

  testWidgets('ROCm switched on, then off, then Start, is automatic', (
    tester,
  ) async {
    final amd = HardwareInfo(
      gpuName: 'AMD Radeon RX 6900 XT',
      vramMb: 16368,
      ramMb: 64000,
      vendor: 'AMD',
      hasRocm: true,
    );
    final rig = await mountSettings(tester, lastUsedIsB: false, hardware: amd);
    await openLaunchOptions(tester);
    final rocm = find.byKey(const ValueKey('use-rocm-switch'));
    await tapVisible(tester, rocm);
    await settle(tester);
    expect(switchesOf(rig), [null, null, null, true]);
    expect(find.text('Acceleration: ROCm (AMD)'), findsOneWidget);

    await tapVisible(tester, rocm);
    await settle(tester);
    expect(switchesOf(rig), [null, null, null, null]);

    await openTab(tester, 'Backend');
    await tapVisible(tester, find.text('Start Backend'));
    await settle(tester, () => rig.kobold.starts.isNotEmpty);

    expect(switchesOf(rig), [
      null,
      null,
      null,
      null,
    ], reason: 'Start wrote four "off" switches, which is CPU only');
    expect(resolvedOn(rig, amd), GpuBackend.vulkan);
    final config = await stagedConfigFor(tester, rig, amd);
    expect(config.containsKey('usevulkan'), isTrue, reason: 'no GPU staged');
  });

  testWidgets('no backend picker is offered, only ROCm on an AMD card', (
    tester,
  ) async {
    await mountSettings(tester, lastUsedIsB: false);
    await openLaunchOptions(tester);
    expect(find.text('Advanced: manual backend override'), findsNothing);
    expect(find.byType(FilterChip), findsNothing);
    expect(find.byKey(const ValueKey('use-rocm-switch')), findsNothing);
  });
}
