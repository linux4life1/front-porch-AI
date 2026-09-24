// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Chat settings Automatic Passage of Time is the live clock gate.
// A real ChatService cannot be driven under testWidgets (Drift hangs).
// This pin proves the toggle exists and writes TimeService.passageOfTimeEnabled
// — the same field _clockRunning reads. Send/regen gates live in
// one_to_one_clock_wear_chip_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/character_state_settings.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'chat-settings Automatic Passage of Time exists and flips the clock gate',
    (tester) async {
      final storage = FakeStorageService();
      final chat = FakeChatService();
      addTearDown(() {
        storage.dispose();
        chat.dispose();
      });
      expect(chat.timeService.passageOfTimeEnabled, isTrue);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<StorageService>.value(value: storage),
            ChangeNotifierProvider<ChatService>.value(value: chat),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ListenableBuilder(
                listenable: chat,
                builder: (_, _) =>
                    CharacterStateSettings(chat: chat, isGroup: false),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Automatic Passage of Time'), findsOneWidget);
      await tester.tap(find.byType(Switch).first);
      await tester.pump();

      expect(
        chat.timeService.passageOfTimeEnabled,
        isFalse,
        reason: 'the visible switch writes the same field _clockRunning reads',
      );

      await tester.tap(find.byType(Switch).first);
      await tester.pump();
      expect(chat.timeService.passageOfTimeEnabled, isTrue);
    },
  );
}
