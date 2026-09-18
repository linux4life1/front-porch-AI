// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Two Settings-page fixes that live in widget wiring, not in a callable unit:
// SettingsPage sits behind the whole provider graph (StorageService,
// KoboldService, HardwareService, ModelManager, LLMProvider, BackendManager)
// and its launch controls spawn a real process, so there is no seam to drive.
// These read the call sites instead — the same approach
// settings_launch_records_model_test.dart already uses for _toggleManagedBackend.
//
//  • The launch controllers are constructed with placeholders ('0' / '16384')
//    and used to be filled from storage ONLY inside _applyHardwareDefaults,
//    which never runs when GPU detection fails (hardwareInfo stays null
//    forever). "Start Backend" persists whatever the controllers hold, so on
//    such a box it wrote 0 GPU layers / 16384 context over the user's saved
//    values and relaunched CPU-only. _useRocm had the same shape: every other
//    acceleration flag was mirrored in initState, ROCm was not, so it was
//    written back as false.
//
//  • The Advanced Launch "Restart" button's Builder listens to KoboldService,
//    which notifies once per backend log line while a model loads. A bare
//    existsSync there stats a multi-GB GGUF on every one of those rebuilds —
//    the io-lint-banned per-frame sync I/O pattern.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('initState mirrors the persisted launch settings into the UI', () {
    final src = File('lib/ui/pages/settings_page.dart').readAsStringSync();

    final method = RegExp(
      r'void initState\(\) \{.*?\n  \}',
      dotAll: true,
    ).firstMatch(src);
    expect(
      method,
      isNotNull,
      reason:
          'could not read _SettingsPageState.initState — if it moved, move '
          'this guard with it rather than deleting it',
    );
    final body = method!.group(0)!;

    // Seeded here, not only inside _applyHardwareDefaults: that runs only
    // once HardwareService reports a GPU.
    expect(
      body.contains(
        '_gpuLayersController.text = storage.backendSettings.gpuLayers',
      ),
      isTrue,
      reason: 'GPU layers must be seeded from storage before any launch',
    );
    expect(
      body.contains('_contextSizeController.text'),
      isTrue,
      reason: 'context size must be seeded from storage before any launch',
    );
    // ROCm is the acceleration flag that was missing; the other three pin the
    // rule rather than the single instance.
    for (final flag in ['_useRocm', '_useCublas', '_useVulkan', '_useMetal']) {
      expect(
        body.contains('$flag = storage.'),
        isTrue,
        reason: '$flag is persisted by Start Backend, so it must be mirrored',
      );
    }
  });

  test('the restart Builder resolves the model path through the memo', () {
    final src = File(
      'lib/ui/pages/settings_page.launch.dart',
    ).readAsStringSync();

    expect(
      src.contains(
        '_launchModelExists(storage.backendSettings.lastUsedModelPath)',
      ),
      isTrue,
      reason: 'the KoboldService-listening Builder must use the memoized check',
    );
    // Every sync-I/O call in this file has to be the memo's own, which carries
    // the io-ok marker; a bare one anywhere else is the per-notify stat again.
    for (final line in src.split('\n')) {
      if (!line.contains('existsSync(')) continue;
      expect(
        line.contains('io-ok:'),
        isTrue,
        reason: 'unmemoized sync I/O in a build path: $line',
      );
    }
  });
}
