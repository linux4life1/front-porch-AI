// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/desk/desk.dart';

void main() {
  test('slash prefix lists every command on a lone /', () {
    final all = deskSlashMatches('/');
    expect(
      all.map((c) => c.name),
      containsAll(['help', 'review', 'stop', 'yolo']),
    );
  });

  test('slash prefix filters as you type', () {
    expect(deskSlashMatches('/he').map((c) => c.name), ['help']);
    expect(deskSlashMatches('/plan').map((c) => c.name), ['plan']);
    expect(deskSlashMatches('hello'), isEmpty);
  });

  test('help text names every command', () {
    final help = deskSlashHelpText();
    for (final c in kDeskSlashCommands) {
      expect(help, contains(c.hint));
    }
  });

  test('review and test expand into agent tasks', () {
    expect(deskSlashAgentTask('/review'), contains('Review this folder'));
    expect(deskSlashAgentTask('/test'), contains('tests'));
  });
}
