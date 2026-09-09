// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  test('old tool output is stubbed; newest stays', () {
    final old = '[read] ok\n${'x' * 40000}';
    final recent = '[bash] ok\nswift test passed';
    final out = waifuPruneToolTraces([old, recent], budget: 8192);
    expect(out.last, recent);
    expect(out.first.contains('pruned'), isTrue);
    expect(out.first.contains('x' * 20), isFalse);
    expect(out.first.contains('[read]'), isTrue);
  });

  test('tiny traces are left alone', () {
    const traces = ['[read] ok\nhi', '[bash] ok\nls'];
    expect(waifuPruneToolTraces(traces, budget: 8192), traces);
  });
}
