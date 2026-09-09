// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

const _yaml = '''
---
id: login-fix
slug: login-fix
title: fix: login
goal: Users can sign in
status: draft
steps:
- id: s1
  title: Add failing test
  status: pending
---

# fix: login
''';

void main() {
  test('plan title with a colon round-trips through JSON encode', () {
    final parsed = waifuPlanParse(
      _yaml,
      relativePath: '.waifu/plans/login-fix.md',
    );
    expect(parsed.title, 'fix: login');
    final encoded = waifuPlanEncode(parsed);
    expect(encoded, contains('```$kWaifuPlanJsonFence'));
    expect(encoded, isNot(contains('title: fix: login')));
    final again = waifuPlanParse(
      encoded,
      relativePath: '.waifu/plans/login-fix.md',
    );
    expect(again.title, 'fix: login');
    expect(again.id, 'login-fix');
    expect(again.steps.single.id, 's1');
  });

  test('old YAML plans still parse, next save is JSON', () {
    final parsed = waifuPlanParse(_yaml);
    expect(parsed.title, 'fix: login');
    expect(waifuPlanEncode(parsed).startsWith('```waifu-plan'), isTrue);
  });

  test('plan accept merges steps and keeps in-progress todos', () {
    final plan = waifuPlanParse(_yaml);
    final todos = WaifuTodos()
      ..write([
        {'id': 'keep', 'content': 'user task', 'status': 'in_progress'},
        {'id': 's1', 'content': 'old title', 'status': 'in_progress'},
      ]);
    waifuSyncPlanTodos(todos, plan);
    expect(todos.items.map((t) => t.id), ['keep', 's1']);
    expect(todos.items.firstWhere((t) => t.id == 's1').status, 'in_progress');
    expect(todos.items.firstWhere((t) => t.id == 'keep').content, 'user task');
  });
}
