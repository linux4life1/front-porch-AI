// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

const _widgetFixture = '''
---
id: empty-email
slug: empty-email
title: Empty email fix
goal: Make the empty-email test pass
status: draft
steps:
- id: s1
  title: Add failing test
  status: pending
---

# Empty email fix
''';

void main() {
  test('encode then parse of the Accept panel fixture', () {
    const rel = '.waifu/plans/empty-email.md';
    final seeded = waifuPlanParse(_widgetFixture, relativePath: rel);
    final encoded = waifuPlanEncode(seeded);
    final again = waifuPlanParse(encoded, relativePath: rel);
    expect(again.id, seeded.id);
    expect(again.steps, hasLength(1));
    expect(again.steps.single.id, 's1');
    expect(again.status, WaifuPlanStatus.draft);
    final accepted = waifuPlanEncode(
      again.copyWith(status: WaifuPlanStatus.accepted),
    );
    expect(
      waifuPlanParse(accepted, relativePath: rel).status,
      WaifuPlanStatus.accepted,
    );
  }, timeout: const Timeout(Duration(seconds: 3)));
}
