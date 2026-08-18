// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Live hold is on Story Calendar. TimeStrip keeps Presence. No TodayLine.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/character_state_group.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/time_strip.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/today_line.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

CharacterCard _card() => CharacterCard(name: 'Ivy');

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
    final chat = FakeChatService(
      todaySentence: today,
      activeCharacter: _card(),
    );
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

  testWidgets('planner on does not park Today under TimeStrip', (tester) async {
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
    expect(find.text('No plan yet.'), findsNothing);
  });

  testWidgets('planner off still omits Today under TimeStrip', (tester) async {
    await pumpGroup(
      tester,
      plannerOn: false,
      today: 'Finish the lighthouse log before the tide turns.',
    );
    expect(find.byType(TimeStrip), findsOneWidget);
    expect(find.byType(TodayLine), findsNothing);
    expect(
      find.text('Finish the lighthouse log before the tide turns.'),
      findsNothing,
    );
    expect(find.text('No plan yet.'), findsNothing);
  });

  testWidgets('empty today still omits Today under TimeStrip', (tester) async {
    await pumpGroup(tester, plannerOn: true, today: null);
    expect(find.byType(TimeStrip), findsOneWidget);
    expect(find.byType(TodayLine), findsNothing);
    expect(find.text('No plan yet.'), findsNothing);
  });
}
