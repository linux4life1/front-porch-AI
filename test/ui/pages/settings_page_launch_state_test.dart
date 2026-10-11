// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A Settings-page fix that lives in widget wiring, not in a callable unit:
// SettingsPage sits behind the whole provider graph and its launch controls
// spawn a real process, so this reads the call site instead.
//
// (The page no longer keeps launch values of its own: the context, layers and
// acceleration copies it had to mirror from storage are gone.)
//
//  • The Advanced Launch "Restart" button's Builder listens to KoboldService,
//    which notifies once per backend log line while a model loads. A bare
//    existsSync there stats a multi-GB GGUF on every one of those rebuilds —
//    the io-lint-banned per-frame sync I/O pattern.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
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
