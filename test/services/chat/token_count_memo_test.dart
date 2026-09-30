// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Unchanged history lines are not re-counted. A second lookup of the same
// string must not need another tokenizer call.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/token_count_memo.dart';

void main() {
  test('the second lookup of the same string is remembered', () {
    final memo = TokenCountMemo();
    var calls = 0;
    int count(String text) {
      final hit = memo.lookup(text, 'kobold');
      if (hit != null) return hit;
      calls++;
      final n = text.length;
      memo.remember(text, 'kobold', n);
      return n;
    }

    expect(count('hello there'), 11);
    expect(count('hello there'), 11);
    expect(calls, 1);
    expect(count('hello there!'), isNot(11));
    expect(calls, 2);
    expect(memo.lookup('hello there', 'estimate'), isNull);
  });

  test('history consults the memo before the Kobold tokenizer', () {
    final src = File(
      'lib/services/chat/chat_service_history.dart',
    ).readAsStringSync();
    final start = src.indexOf('Future<int> _countTokens');
    final body = src.substring(start, src.indexOf('\n  }', start));
    expect(body.contains('_tokenCountMemo.lookup'), isTrue);
    expect(
      body.indexOf('_tokenCountMemo.lookup'),
      lessThan(body.indexOf('_koboldService.countTokens')),
    );
    expect(body.contains('_tokenCountMemo.remember'), isTrue);
  });
}
