// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/chat_components/bubbles/message_bubble.dart';

ChatMessage _thinking({required bool live}) {
  final msg = ChatMessage(
    text: '<think>secret plan</think>\nhello there',
    sender: 'Iris',
    isUser: false,
  );
  if (live) {
    msg.thinkingStartTime = DateTime.now().millisecondsSinceEpoch;
  } else {
    msg.thinkingDurationMs = 1200;
  }
  return msg;
}

Widget _app(ChatMessage msg, {required bool generating}) {
  return MaterialApp(
    home: Scaffold(
      body: MessageBubble(message: msg, index: 0, isGenerating: generating),
    ),
  );
}

void main() {
  testWidgets('chevron collapses live thinking; timer stays', (tester) async {
    final msg = _thinking(live: true);
    await tester.pumpWidget(_app(msg, generating: true));
    expect(find.text('secret plan'), findsOneWidget);
    expect(find.textContaining('Thinking'), findsOneWidget);

    await tester.tap(find.byKey(const Key('thought-toggle')));
    await tester.pump();
    expect(find.text('secret plan'), findsNothing);
    expect(find.textContaining('Thinking'), findsOneWidget);
    expect(find.text('hello there'), findsOneWidget);

    await tester.tap(find.byKey(const Key('thought-toggle')));
    await tester.pump();
    expect(find.text('secret plan'), findsOneWidget);
  });

  testWidgets('finished think stays collapsed until the chevron is tapped', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_thinking(live: false), generating: false));
    expect(find.text('secret plan'), findsNothing);
    await tester.tap(find.byKey(const Key('thought-toggle')));
    await tester.pump();
    expect(find.text('secret plan'), findsOneWidget);
  });

  testWidgets('later stream chunks do not re-open a collapsed live think', (
    tester,
  ) async {
    final first = _thinking(live: true);
    await tester.pumpWidget(_app(first, generating: true));
    await tester.tap(find.byKey(const Key('thought-toggle')));
    await tester.pump();
    expect(find.text('secret plan'), findsNothing);

    final next = ChatMessage(
      text: '<think>secret plan\nmore tokens</think>\nhello there',
      sender: 'Iris',
      isUser: false,
    )..thinkingStartTime = first.thinkingStartTime;
    await tester.pumpWidget(_app(next, generating: true));
    await tester.pump();
    expect(find.textContaining('secret plan'), findsNothing);
    expect(find.textContaining('Thinking'), findsOneWidget);
  });
}
