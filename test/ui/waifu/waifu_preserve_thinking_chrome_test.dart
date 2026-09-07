// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu.dart';

void main() {
  testWidgets('Harness has a Preserve thinking toggle', (tester) async {
    final session = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Iris'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WaifuModeBar(
            mode: session.mode,
            onChanged: (m) => session.mode = m,
            preserveThinking: session.preserveThinking,
            onPreserveThinking: (v) => session.preserveThinking = v,
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('waifu-preserve-thinking')), findsOneWidget);
    expect(session.preserveThinking, isFalse);
    await tester.tap(find.byKey(const Key('waifu-preserve-thinking')));
    await tester.pump();
    expect(session.preserveThinking, isTrue);
  });
}
