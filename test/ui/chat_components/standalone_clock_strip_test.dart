// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// TimeStrip visibility follows Passage of Time, the only story-clock
// driver. Realism, Needs, and the leftover standalone pref do not hide
// a live clock.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/character_state_group.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/time_strip.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes.dart';

Future<void> _pumpPanel(
  WidgetTester tester, {
  required bool realismEnabled,
  bool passageOfTime = true,
}) async {
  SharedPreferences.setMockInitialValues({
    'passage_of_time_default': passageOfTime,
  });
  final storage = StorageService();
  addTearDown(storage.dispose);
  await storage.realismSettings.setPassageOfTimeDefault(passageOfTime);

  final chat = FakeChatService(realismEnabled: realismEnabled);
  chat.timeService.setPassageOfTimeEnabled(passageOfTime);
  addTearDown(chat.dispose);

  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ChatService>.value(value: chat),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 340,
              child: CharacterStateGroup(
                chat: chat,
                isGroup: false,
                initiallyExpanded: true,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setupPathProviderMock();

  testWidgets('engine off + PoT on → the strip is visible', (tester) async {
    await _pumpPanel(tester, realismEnabled: false);
    expect(find.byType(TimeStrip), findsOneWidget);
  });

  testWidgets('engine off + PoT off → no strip', (tester) async {
    await _pumpPanel(tester, realismEnabled: false, passageOfTime: false);
    expect(find.byType(TimeStrip), findsNothing);
  });

  testWidgets('engine on + PoT on → the strip is visible', (tester) async {
    await _pumpPanel(tester, realismEnabled: true);
    expect(find.byType(TimeStrip), findsOneWidget);
  });
}
