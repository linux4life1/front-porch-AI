// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A reply that carries only the clock's stamp was not scored by the engine:
// Passage of Time runs without it. The bubble must not say "Bond unchanged"
// and "Trust unchanged" on it, which it did for every reply of a chat with
// Realism off (a user's report on v1.5.0).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a clock-only reply shows its time and no bond or trust', (
    tester,
  ) async {
    final msg = ChatMessage(
      text: 'She nods.',
      sender: 'Sophia',
      isUser: false,
      metadata: {'time_passed': '5 min'},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MessageBubble(message: msg, index: 1)),
      ),
    );
    expect(find.text('5 min'), findsOneWidget);
    expect(find.text('Bond unchanged'), findsNothing);
    expect(find.text('Trust unchanged'), findsNothing);
  });

  testWidgets('a time skip alone is not a scored reply either', (tester) async {
    final msg = ChatMessage(
      text: 'Morning came.',
      sender: 'Sophia',
      isUser: false,
      metadata: {'time_skip_to': 'the next morning'},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MessageBubble(message: msg, index: 1)),
      ),
    );
    expect(find.text('Bond unchanged'), findsNothing);
    expect(find.text('Trust unchanged'), findsNothing);
  });
}
