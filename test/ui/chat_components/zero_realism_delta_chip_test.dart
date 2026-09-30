// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A scored turn keeps Bond and Trust on the bubble even when the judge
// returned 0. A missing key stays hidden so an older unscored reply does
// not grow a fake +0.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a recorded zero bond and trust stay on the bubble', (
    tester,
  ) async {
    final msg = ChatMessage(
      text: 'She nods.',
      sender: 'Sophia',
      isUser: false,
      metadata: {
        'bond_delta': 0,
        'trust_delta': 0,
        'emotion_label': 'amusement',
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MessageBubble(message: msg, index: 1)),
      ),
    );
    expect(find.text('Bond unchanged'), findsOneWidget);
    expect(find.text('Trust unchanged'), findsOneWidget);
    expect(find.text('Mood: amusement'), findsOneWidget);
  });

  testWidgets('a mood-only reply says bond and trust were unchanged', (
    tester,
  ) async {
    final msg = ChatMessage(
      text: 'She nods.',
      sender: 'Sophia',
      isUser: false,
      metadata: {'emotion_label': 'amusement'},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MessageBubble(message: msg, index: 1)),
      ),
    );
    expect(find.text('Bond unchanged'), findsOneWidget);
    expect(find.text('Trust unchanged'), findsOneWidget);
    expect(find.text('Mood: amusement'), findsOneWidget);
  });
}
