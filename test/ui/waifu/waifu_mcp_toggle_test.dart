// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu_page.dart';

void main() {
  testWidgets('MCP checkbox sticks before any harness exists', (tester) async {
    final session = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Iris'),
    );
    await tester.pumpWidget(MaterialApp(home: WaifuPage(session: session)));
    expect(session.mcpOptIn, isFalse);
    await tester.ensureVisible(find.byKey(const Key('waifu-mcp-opt-in')));
    await tester.tap(find.byKey(const Key('waifu-mcp-opt-in')));
    await tester.pump();
    expect(session.mcpOptIn, isTrue);
    expect(find.textContaining('folder jail covers'), findsOneWidget);
  });

  testWidgets('whole-disk MCP warning never claims a jail boundary', (
    tester,
  ) async {
    final session = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Iris'),
      pathMode: WaifuPathMode.wholeDisk,
      mcpOptIn: true,
    );
    await tester.pumpWidget(MaterialApp(home: WaifuPage(session: session)));
    expect(
      find.textContaining('Whole-disk access is already open'),
      findsOneWidget,
    );
    expect(find.textContaining('jail does not apply'), findsNothing);
  });

  testWidgets('Language help lives in the app bar only', (tester) async {
    final session = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Iris'),
    );
    await tester.pumpWidget(MaterialApp(home: WaifuPage(session: session)));
    expect(find.byKey(const Key('waifu-language-help')), findsOneWidget);
    expect(find.text('Language help'), findsNothing);
  });
}
