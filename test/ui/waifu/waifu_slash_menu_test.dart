// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu_page.dart';

void main() {
  testWidgets('typing / lists slash commands with blurbs', (tester) async {
    final session = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Iris'),
    );
    await tester.pumpWidget(MaterialApp(home: WaifuPage(session: session)));
    await tester.enterText(find.byKey(const Key('waifu-composer')), '/');
    await tester.pump();
    expect(find.byKey(const Key('waifu-slash-menu')), findsOneWidget);
    expect(find.byKey(const Key('waifu-slash-help')), findsOneWidget);
    expect(find.textContaining('List every slash command'), findsOneWidget);
    await tester.tap(find.byKey(const Key('waifu-slash-help')));
    await tester.pump();
    expect(session.transcript, isNotEmpty);
    expect(session.transcript.last.text, contains('/stop'));
  });

  testWidgets('sidebar shows used vs max context', (tester) async {
    final session =
        WaifuSession(
            folderRoot: '/tmp/throwaway-waifu',
            coworker: CharacterCard(name: 'Iris'),
          )
          ..tokensUsed = 1200
          ..contextBudget = 8192;
    await tester.pumpWidget(MaterialApp(home: WaifuPage(session: session)));
    expect(find.byKey(const Key('waifu-context-bar')), findsOneWidget);
    expect(find.text('1200 / 8192'), findsOneWidget);
  });
}
