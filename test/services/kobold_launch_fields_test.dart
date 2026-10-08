// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The one-time note for people who had a GPU layer count before the app
// moved everyone to Automatic: who sees it, and that it goes away for good.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/storage/settings/backend_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<BackendSettings> _open([Map<String, Object>? initial]) async {
  final probe = BackendSettings();
  if (initial != null) {
    SharedPreferences.setMockInitialValues({
      for (final e in initial.entries) probe.k(e.key): e.value,
    });
  }
  final settings = BackendSettings()
    ..initializeBase(await SharedPreferences.getInstance(), () {});
  return settings..load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a fresh install has nothing to be told, even after a launch has '
      'stored a layer count for it', () async {
    final s = await _open({});
    expect(s.gpuLayersManual, isFalse);
    expect(s.retiredGpuLayers, isNull);

    // Starting the engine saves the count shown in Settings.
    await s.setGpuLayers(0);
    expect(s.retiredGpuLayers, isNull);
    expect((await _open()).retiredGpuLayers, isNull);
  });

  test('someone with a stored layer count is on Automatic and is told what '
      'their number was, until they say "Got it"', () async {
    final s = await _open({'gpu_layers': 40});
    expect(s.gpuLayersManual, isFalse);
    expect(s.retiredGpuLayers, 40);
    // The number itself is kept for "Set layers myself".
    expect(s.gpuLayers, 40);

    await s.dismissGpuLayersNote();
    expect(s.retiredGpuLayers, isNull);
    // And stays gone after a restart.
    expect((await _open()).retiredGpuLayers, isNull);
    expect((await _open()).gpuLayers, 40);
  });

  test('a stored zero (model kept off the card) is told too: Automatic now '
      'puts the model on the card', () async {
    expect((await _open({'gpu_layers': 0})).retiredGpuLayers, 0);
  });

  test(
    'taking the number back into use counts as having seen the note',
    () async {
      final s = await _open({'gpu_layers': 33});
      await s.setGpuLayersManual(true);
      expect(s.retiredGpuLayers, isNull);
      await s.setGpuLayersManual(false);
      expect(s.retiredGpuLayers, isNull);
      expect((await _open()).retiredGpuLayers, isNull);
    },
  );
}
