// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/web/util/lorebook_json.dart';

void main() {
  test('from-wiki save carries recursion, depth, and token budget', () {
    final book = buildLorebookFromJson(
      [
        {
          'name': "Baker's Street",
          'key': "Baker's Street",
          'content': 'They keep the quay oven lit.',
        },
      ],
      bookFields: {
        'recursiveScanning': true,
        'scanDepth': 10,
        'tokenBudget': 2800,
      },
    )!;
    expect(book.recursiveScanning, isTrue);
    expect(book.scanDepth, 10);
    expect(book.tokenBudget, 2800);
  });

  test('omitted book fields stay unset so older clients do not force them', () {
    final book = buildLorebookFromJson([
      {
        'name': "Baker's Street",
        'key': "Baker's Street",
        'content': 'They keep the quay oven lit.',
      },
    ])!;
    expect(book.recursiveScanning, isNull);
    expect(book.scanDepth, isNull);
    expect(book.tokenBudget, isNull);
  });
}
