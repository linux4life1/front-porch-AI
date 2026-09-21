// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';

ChatMessage _liveThink() {
  return ChatMessage(
    text: '<think>secret plan</think>\nhello there',
    sender: 'Iris',
    isUser: false,
  )..thinkingStartTime = DateTime.now().millisecondsSinceEpoch;
}

void main() {
  testWidgets('Waifu Thought stays folded until the chevron, then closes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageList(
            messages: [_liveThink()],
            resolveSpeaker: (_) => (null, null),
          ),
        ),
      ),
    );
    expect(find.text('secret plan'), findsNothing);
    expect(find.text('Thought'), findsOneWidget);

    await tester.tap(find.byKey(const Key('thought-toggle')));
    await tester.pump();
    expect(find.text('secret plan'), findsOneWidget);

    await tester.tap(find.byKey(const Key('thought-toggle')));
    await tester.pump();
    expect(find.text('secret plan'), findsNothing);
  });

  testWidgets('a tool row above the bubble does not re-open a closed Thought', (
    tester,
  ) async {
    var showTool = false;
    late VoidCallback revealTool;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              revealTool = () => setState(() => showTool = true);
              return ChatMessageList(
                messages: [_liveThink()],
                resolveSpeaker: (_) => (null, null),
                aboveBubble: (msg, index) {
                  if (!showTool || msg.isUser) return null;
                  return const Text('wrote main.dart');
                },
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('thought-toggle')));
    await tester.pump();
    expect(find.text('secret plan'), findsOneWidget);
    await tester.tap(find.byKey(const Key('thought-toggle')));
    await tester.pump();
    expect(find.text('secret plan'), findsNothing);

    revealTool();
    await tester.pump();
    expect(find.text('wrote main.dart'), findsOneWidget);
    expect(find.text('secret plan'), findsNothing);
  });
}
