// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu_context_bar.dart';

void main() {
  testWidgets('hot context bar tap folds old turns', (tester) async {
    var compact = 0;
    final hot =
        WaifuSession(
            folderRoot: '/tmp/waifu-bar',
            coworker: CharacterCard(name: 'Iris'),
          )
          ..tokensUsed = 7000
          ..contextBudget = 8192;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          body: WaifuContextBar(session: hot, onCompact: () => compact++),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('waifu-context-bar-compact')));
    expect(compact, 1);
  });

  testWidgets('cold context bar does not offer compact', (tester) async {
    var compact = 0;
    final cold =
        WaifuSession(
            folderRoot: '/tmp/waifu-bar',
            coworker: CharacterCard(name: 'Iris'),
          )
          ..tokensUsed = 100
          ..contextBudget = 8192;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          body: WaifuContextBar(session: cold, onCompact: () => compact++),
        ),
      ),
    );
    expect(find.byKey(const Key('waifu-context-bar-compact')), findsNothing);
    await tester.tap(
      find.byKey(const Key('waifu-context-bar')),
      warnIfMissed: false,
    );
    expect(compact, 0);
  });
}
