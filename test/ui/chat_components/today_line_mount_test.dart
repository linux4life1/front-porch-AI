// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Live hold is on the Story Calendar, not under TimeStrip.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/calendar_today_hold.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/character_state_group.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/time_strip.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/today_line.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpGroup(
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
  }

  testWidgets('TimeStrip stays; TodayLine is not under it', (tester) async {
    await pumpGroup(
      tester,
      plannerOn: true,
      today: 'Finish the lighthouse log before the tide turns.',
    );
    expect(find.byType(TimeStrip), findsOneWidget);
    expect(find.byType(TodayLine), findsNothing);
    expect(
      find.text('Finish the lighthouse log before the tide turns.'),
      findsNothing,
    );
  });

  testWidgets('Calendar hold shows the sentence and X clears it', (tester) async {
    final chat = FakeChatService(
      todaySentence: 'Hold the porch light.',
    );
    addTearDown(chat.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalendarTodayHold(
            enabled: true,
            text: chat.todaySentence,
            onAbandon: chat.abandonToday,
          ),
        ),
      ),
    );
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('Hold the porch light.'), findsOneWidget);
    await tester.tap(find.byTooltip("Clear today's plan"));
    await tester.pump();
    expect(chat.todaySentence, isNull);
  });
}
