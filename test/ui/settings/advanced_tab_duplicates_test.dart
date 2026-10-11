// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Settings → Advanced kept a second copy of what the Backend tab's Local
// model card, the Model Settings dialog and the preset editor already set:
// the card's name and memory, the context, GPU layers and the KV cache.
// They are gone; acceleration moved into Advanced Launch Options. The Generation tab's Min Output Tokens was never sent to
// any backend, so it is gone too. The real Settings page.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/settings_page_harness.dart';

void main() {
  testWidgets('Advanced has no Hardware & GPU copy and no KV cache; '
      'acceleration is in Advanced Launch Options', (tester) async {
    await mountSettings(tester, lastUsedIsB: false);
    await openTab(tester, 'Advanced');

    expect(find.text('Hardware & GPU'), findsNothing);
    expect(find.text('Context Window'), findsNothing);
    expect(
      find.byKey(const ValueKey('gpu-layers-manual-switch')),
      findsNothing,
    );

    await tapVisible(tester, find.text('Advanced Launch Options'));
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);

    expect(find.textContaining('Acceleration:'), findsOneWidget);
    // The KV cache is set in the preset editor and the Model Settings
    // dialog.
    expect(find.byKey(const ValueKey('kv-quant-picker')), findsNothing);
    expect(find.text('Flash Attention'), findsOneWidget);
  });

  testWidgets('Generation offers no Min Output Tokens', (tester) async {
    await mountSettings(tester, lastUsedIsB: false);
    await openTab(tester, 'Generation');

    expect(find.text('Max Output Tokens'), findsOneWidget);
    expect(find.text('Min Output Tokens'), findsNothing);
  });
}
