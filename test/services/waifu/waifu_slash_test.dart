// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  test('slash prefix lists every command on a lone /', () {
    final all = waifuSlashMatches('/');
    expect(
      all.map((c) => c.name),
      containsAll(['help', 'review', 'stop', 'yolo']),
    );
  });

  test('slash prefix filters as you type', () {
    expect(waifuSlashMatches('/he').map((c) => c.name), ['help']);
    expect(waifuSlashMatches('/plan').map((c) => c.name), ['plan']);
    expect(waifuSlashMatches('hello'), isEmpty);
  });

  test('help text names every command', () {
    final help = waifuSlashHelpText();
    for (final c in kWaifuSlashCommands) {
      expect(help, contains(c.hint));
    }
  });

  test('review and test expand into agent tasks', () {
    expect(waifuSlashAgentTask('/review'), contains('Review this folder'));
    expect(waifuSlashAgentTask('/test'), contains('tests'));
  });
}
