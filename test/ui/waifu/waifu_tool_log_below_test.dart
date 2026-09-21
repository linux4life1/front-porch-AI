// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';

void main() {
  testWidgets('tool actions sit below the bubble, not above Thought', (
    tester,
  ) async {
    const toolKey = Key('tool-below');
    final msg = ChatMessage(
      text: '<think>secret plan</think>\nhello there',
      sender: 'Iris',
      isUser: false,
    )..thinkingStartTime = DateTime.now().millisecondsSinceEpoch;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageList(
            messages: [msg],
            resolveSpeaker: (_) => (null, null),
            belowBubble: (m, index) {
              if (m.isUser) return null;
              return const Text('bash pip show pygame', key: toolKey);
            },
          ),
        ),
      ),
    );
    final tool = tester.getTopLeft(find.byKey(toolKey));
    final thought = tester.getTopLeft(find.byKey(const Key('thought-toggle')));
    expect(tool.dy, greaterThan(thought.dy));
  });
}
