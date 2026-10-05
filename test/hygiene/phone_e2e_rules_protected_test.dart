// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Two files decide whether a failing phone browser test can pass:
// web_ui/e2e/playwright.config.ts (one retry on CI, for the phone browser)
// and web_ui/e2e/support/fixtures.ts (a retry only after a browser crash,
// and every page error fails the test). That makes them test evidence, so
// test-integrity.yml's isProtected names each one: a PR that loosens either
// needs the maintainer's `approved-test-change` label, like any edit to a
// test.
//
// The workflow sees file names, not contents, so the names are the contract:
// a file moved without the workflow following it would be unguarded again.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const rules = [
    'web_ui/e2e/playwright.config.ts',
    'web_ui/e2e/support/fixtures.ts',
  ];

  /// The body of isProtected, as the workflow has it.
  String isProtected() {
    final text = File(
      '.github/workflows/test-integrity.yml',
    ).readAsStringSync();
    final start = text.indexOf('const isProtected = (p) =>');
    expect(start, isNot(-1), reason: 'isProtected is where it was');
    return text.substring(start, text.indexOf(';\n', start));
  }

  for (final file in rules) {
    test('$file is protected as test evidence', () {
      expect(
        File(file).existsSync(),
        isTrue,
        reason: 'the workflow names this exact path; a move needs both',
      );
      expect(isProtected(), contains("p === '$file'"));
    });
  }
}
