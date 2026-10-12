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
    // The page owns a PathExistsMemo and hands its `of` to the launch
    // options; the launch options only call the callback it was given.
    final page = File('lib/ui/pages/settings_page.dart').readAsStringSync();
    final launch = File(
      'lib/ui/pages/settings_page.launch.dart',
    ).readAsStringSync();

    expect(
      page.contains('final _launchModelExists = PathExistsMemo();'),
      isTrue,
      reason: 'the page must keep one memo for the relaunch model path',
    );
    expect(
      page.contains('launchModelExists: _launchModelExists.of,'),
      isTrue,
      reason: 'the launch options must be handed the memo, not a bare check',
    );
    expect(
      launch.contains(
        '_launchModelExists(storage.backendSettings.lastUsedModelPath)',
      ),
      isTrue,
      reason: 'the KoboldService-listening Builder must use the memoized check',
    );
    // No sync I/O on the page's build paths unless it carries the io-ok
    // marker; a bare one is the per-notify stat again.
    final sources = <String, String>{
      'lib/ui/pages/settings_page.dart': page,
      'lib/ui/pages/settings_page.launch.dart': launch,
      for (final f in Directory('lib/ui/pages/settings_page').listSync())
        if (f is File && f.path.endsWith('.dart')) f.path: f.readAsStringSync(),
    };
    for (final MapEntry(key: path, value: src) in sources.entries) {
      for (final line in src.split('\n')) {
        if (!line.contains('existsSync(')) continue;
        expect(
          line.contains('io-ok:'),
          isTrue,
          reason: 'unmemoized sync I/O in a build path ($path): $line',
        );
      }
    }
  });
}
