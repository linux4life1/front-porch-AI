// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// THE STORY CLOCK HAS TWO DRIVERS, AND THE SIDEBAR ONLY KNEW ABOUT ONE.
//
// TimeStrip (clock, date, period dots, weather chip) was rendered under
// `if (realismOn || isGroup)`. But the clock also runs on the opt-in
// standalone driver — ChatService._clockRunning is
// `passageOfTimeEnabled && (realismEnabled || standaloneClockEnabled)` — and
// Porch Life only OFFERS that switch when the engine is OFF. So the one
// configuration in which a user can turn the standalone clock on was exactly
// the configuration in which the sidebar showed no clock at all: an extra
// model call every turn with nothing on screen to show for it.
//
// This drives the real CharacterStateGroup with the real StorageService flag
// and asserts the strip appears/disappears with the standalone switch.

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
  required bool standaloneClock,
}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService();
  addTearDown(storage.dispose);
  await storage.realismSettings.setStandaloneClockEnabled(standaloneClock);

  final chat = FakeChatService(realismEnabled: realismEnabled);
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

  testWidgets('engine off + standalone clock on → the strip is visible', (
    tester,
  ) async {
    await _pumpPanel(tester, realismEnabled: false, standaloneClock: true);
    expect(find.byType(TimeStrip), findsOneWidget);
  });

  testWidgets('engine off + standalone clock off → no strip', (tester) async {
    await _pumpPanel(tester, realismEnabled: false, standaloneClock: false);
    expect(find.byType(TimeStrip), findsNothing);
  });

  testWidgets('engine on → the strip is visible regardless of the switch', (
    tester,
  ) async {
    await _pumpPanel(tester, realismEnabled: true, standaloneClock: false);
    expect(find.byType(TimeStrip), findsOneWidget);
  });
}
