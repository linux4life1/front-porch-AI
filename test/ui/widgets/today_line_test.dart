// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// TimeStrip + TodayLine: sentence when present; omit when empty.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/time_strip.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/today_line.dart';

import '../../golden/support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Plans + line shows the sentence under TimeStrip', (tester) async {
    final chat = FakeChatService(timeOfDay: 'evening', dayCount: 3);
    addTearDown(chat.dispose);
    const line = "Get Saturday's errands done before Tuesday's review.";
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TimeStrip(chat: chat),
              const TodayLine(text: line),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text(line), findsOneWidget);
    expect(find.text('No plan yet.'), findsNothing);
  });

  testWidgets('empty TodayLine omits — zero extra height', (tester) async {
    final chat = FakeChatService(timeOfDay: 'evening', dayCount: 3);
    addTearDown(chat.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TimeStrip(chat: chat),
              const TodayLine(text: null),
              const TodayLine(text: '   '),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(TodayLine), findsNWidgets(2));
    expect(tester.getSize(find.byType(TodayLine).first), Size.zero);
    expect(tester.getSize(find.byType(TodayLine).at(1)), Size.zero);
    expect(find.text('No plan yet.'), findsNothing);
  });
}
