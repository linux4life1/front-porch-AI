// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Proven red: openThinkBodyChars returned 0 on an unclosed <think>;
// thinkDumpExceeded stayed false when the body was past the cap.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/eval_stream_guards.dart';

void main() {
  test('open think body counts only the unclosed fence', () {
    expect(openThinkBodyChars('plain'), 0);
    expect(openThinkBodyChars('<think>abc</think>{"a":1}'), 0);
    expect(openThinkBodyChars('<think>${'n' * 40}'), 40);
  });

  test('think dump needs an open fence AND no JSON yet', () {
    expect(thinkDumpExceeded('<think>${'x' * 100}', cap: 80), isTrue);
    expect(
      thinkDumpExceeded(
        '<think>${'x' * 100}</think>{"relationship_delta":0}',
        cap: 80,
      ),
      isFalse,
    );
    expect(thinkDumpExceeded('<think>short', cap: 80), isFalse);
  });

  test('remaining budget hits zero', () {
    final sw = Stopwatch()..start();
    expect(remainingBudget(sw, Duration.zero), Duration.zero);
  });
}
