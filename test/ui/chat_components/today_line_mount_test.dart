// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// TodayLine sits under TimeStrip when the planner flag is on and a sentence
// is held. Omitted when the flag is off or the sentence is empty.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/character_state_group.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/time_strip.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/today_line.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<FakeChatService> pumpGroup(
    WidgetTester tester, {
    required bool plannerOn,
    String? today,
  }) async {
    final storage = FakeStorageService();
    if (plannerOn) {
      await storage.realismSettings.setPlannerEnabled(true);
    }
    final chat = FakeChatService(todaySentence: today);
    addTearDown(() {
      storage.dispose();
      chat.dispose();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ChatService>.value(value: chat),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CharacterStateGroup(
                chat: chat,
                isGroup: false,
                initiallyExpanded: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return chat;
  }

  testWidgets('TodayLine under TimeStrip when flag on and sentence present',
      (tester) async {
    await pumpGroup(
      tester,
      plannerOn: true,
      today: 'Finish the lighthouse log before the tide turns.',
    );
    expect(find.byType(TimeStrip), findsOneWidget);
    expect(find.byType(TodayLine), findsOneWidget);
    expect(
      find.text('Finish the lighthouse log before the tide turns.'),
      findsOneWidget,
    );
    expect(find.text('No plan yet.'), findsNothing);
  });

  testWidgets('TodayLine omitted when flag is off even if a sentence is held',
      (tester) async {
    await pumpGroup(
      tester,
      plannerOn: false,
      today: 'Finish the lighthouse log before the tide turns.',
    );
    expect(find.byType(TimeStrip), findsOneWidget);
    expect(find.text('Finish the lighthouse log before the tide turns.'),
        findsNothing);
    expect(find.text('No plan yet.'), findsNothing);
    expect(tester.getSize(find.byType(TodayLine)).height, 0);
  });

  testWidgets('TodayLine omitted when sentence is empty', (tester) async {
    await pumpGroup(tester, plannerOn: true, today: null);
    expect(find.byType(TimeStrip), findsOneWidget);
    expect(find.text('No plan yet.'), findsNothing);
    expect(tester.getSize(find.byType(TodayLine)).height, 0);
  });

  testWidgets('deleting the visible line clears the session sentence',
      (tester) async {
    final chat = await pumpGroup(
      tester,
      plannerOn: true,
      today: 'Hold the porch light.',
    );
    expect(chat.todaySentence, 'Hold the porch light.');
    await tester.tap(find.byTooltip("Clear today's plan"));
    await tester.pump();
    expect(chat.todaySentence, isNull);
    expect(find.text('Hold the porch light.'), findsNothing);
  });
}
