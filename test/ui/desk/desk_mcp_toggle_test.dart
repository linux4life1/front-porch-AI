// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:front_porch_ai/ui/desk/desk_page.dart';

void main() {
  testWidgets('MCP checkbox sticks before any harness exists', (tester) async {
    final session = DeskSession(
      folderRoot: '/tmp/throwaway-desk',
      coworker: CharacterCard(name: 'Iris'),
    );
    await tester.pumpWidget(MaterialApp(home: DeskPage(session: session)));
    expect(session.mcpOptIn, isFalse);
    await tester.ensureVisible(find.byKey(const Key('desk-mcp-opt-in')));
    await tester.tap(find.byKey(const Key('desk-mcp-opt-in')));
    await tester.pump();
    expect(session.mcpOptIn, isTrue);
    expect(find.textContaining('jail does not apply'), findsOneWidget);
  });

  testWidgets('Language help lives in the app bar only', (tester) async {
    final session = DeskSession(
      folderRoot: '/tmp/throwaway-desk',
      coworker: CharacterCard(name: 'Iris'),
    );
    await tester.pumpWidget(MaterialApp(home: DeskPage(session: session)));
    expect(find.byKey(const Key('desk-language-help')), findsOneWidget);
    expect(find.text('Language help'), findsNothing);
  });
}
