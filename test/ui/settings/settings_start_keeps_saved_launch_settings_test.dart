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

  testWidgets('Reset to Automatic, then Start, stays automatic', (
    tester,
  ) async {
    final rig = await mountSettings(tester, lastUsedIsB: false);
    await openTab(tester, 'Advanced');
    await tapVisible(tester, find.text('Reset to Automatic'));
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
    expect(resolvedOn(rig, nvidiaGtx1060), GpuBackend.cuda);
    final config = await stagedConfigFor(tester, rig, nvidiaGtx1060);
    expect(config.containsKey('usecuda'), isTrue, reason: 'no GPU was staged');
  });

  group('turning an acceleration switch off', () {
    // One machine that offers all four switches, so each can be turned on
    // and off.
    final everything = HardwareInfo(
      gpuName: 'NVIDIA GeForce RTX 4090',
      vramMb: 24576,
      ramMb: 65536,
      vendor: 'Nvidia',
      hasCuda: true,
      hasRocm: true,
      hasMetal: true,
    );
    const chips = {
      'Use Vulkan': [false, true, false, false],
      'Use ROCm (AMD)': [false, false, false, true],
      'Use CuBLAS (Nvidia)': [true, false, false, false],
      'Use Metal (MacOS)': [false, false, true, false],
    };

    for (final MapEntry(key: label, value: only) in chips.entries) {
      testWidgets('"$label" on chooses it alone, off is CPU only through '
          'Start', (tester) async {
        final rig = await mountSettings(
          tester,
          lastUsedIsB: false,
          hardware: everything,
        );
        await openTab(tester, 'Advanced');
        await tapVisible(
          tester,
          find.text('Advanced: manual backend override'),
        );
        await tester.pump(const Duration(milliseconds: 400));
        await settle(tester);

        // Whatever the machine started on, this switch ends up chosen. A
        // switch nobody has set reads as off.
        final chip = find.widgetWithText(FilterChip, label);
        if (!tester.widget<FilterChip>(chip).selected) {
          await tapVisible(tester, chip);
          await settle(tester);
        }
        expect(
          [for (final on in switchesOf(rig)) on == true],
          only,
          reason: '"$label" on chooses it alone',
        );

        await tapVisible(tester, chip);
        await settle(tester);
        expect(
          switchesOf(rig),
          [false, false, false, false],
          reason: '"$label" off means no acceleration: all four are saved off',
        );

        await openTab(tester, 'Backend');
        await tapVisible(tester, find.text('Start Backend'));
        await settle(tester, () => rig.kobold.starts.isNotEmpty);
        expect(resolvedOn(rig, everything), GpuBackend.cpu);
        final config = await stagedConfigFor(tester, rig, everything);
        expect(config.containsKey('usecuda'), isFalse);
        expect(config.containsKey('usevulkan'), isFalse);
      });
    }
  });

  testWidgets('GPU layers typed on the Advanced tab are saved as typed', (
    tester,
  ) async {
    final rig = await mountSettings(tester, lastUsedIsB: false);
    final b = rig.store.backendSettings;
    await openTab(tester, 'Advanced');
    await tapVisible(
      tester,
      find.byKey(const ValueKey('gpu-layers-manual-switch')),
    );
    await settle(tester);
    final field = find.byKey(const ValueKey('gpu-layers-number'));
    await tester.ensureVisible(field);
    await tester.enterText(field, '20');
    await settle(tester);
    expect(b.gpuLayers, 20, reason: 'typing does not save the layer count');

    // Half-typed text that is not a number saves nothing.
    await tester.enterText(field, '');
    await settle(tester);
    expect(b.gpuLayers, 20);

    // The Advanced tab's own Start launches from what is saved.
    await tapVisible(tester, find.text('Advanced Launch Options'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    await tapVisible(tester, find.text('Start Backend'));
    await settle(tester, () => rig.kobold.starts.isNotEmpty);
    expect(rig.kobold.starts.single.layers, 20);
  });
}
