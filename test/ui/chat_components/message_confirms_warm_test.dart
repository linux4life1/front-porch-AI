// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// The bubble's Delete Message and Fork Conversation confirms were plain stock
// dialogs. They now open in the warm-porch dialog like the app's other
// confirms: Delete as a destructive one, Fork in porch amber. The delete
// itself is driven end to end by integration_test/message_actions_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes.dart';

void main() {
  setupPathProviderMock();

  Future<void> pumpBubbles(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    addTearDown(storage.dispose);
    final chat = FakeChatService();
    addTearDown(chat.dispose);
    final tts = FakeTtsService();
    addTearDown(tts.dispose);
    final banner = ChatMessage(
      text: '[🎰 CHANCE TIME! A raccoon steals the pie]',
      sender: 'System',
      isUser: false,
      metadata: const {'is_chance_time_narration': true},
    );
    final reply = ChatMessage(
      text: 'She hands you a peach.',
      sender: 'Carmen',
      isUser: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MultiProvider(
            providers: [
              ChangeNotifierProvider<StorageService>.value(value: storage),
              ChangeNotifierProvider<TtsService>.value(value: tts),
              ChangeNotifierProvider<ChatService>.value(value: chat),
              ChangeNotifierProvider<UserPersonaService>.value(
                value: FakeUserPersonaService(),
              ),
            ],
            child: ListView(
              children: [
                MessageBubble(message: banner, index: 0, chatService: chat),
                MessageBubble(message: reply, index: 1, chatService: chat),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('Delete Message is a warm destructive confirm; Cancel closes '
      'it', (tester) async {
    await pumpBubbles(tester);
    await tester.longPress(find.textContaining('A raccoon steals the pie'));
    await tester.pumpAndSettle();

    final dialog = find.widgetWithText(WarmDialog, 'Delete Message');
    expect(dialog, findsOneWidget);
    expect(tester.widget<WarmDialog>(dialog).destructive, isTrue);
    expect(
      find.descendant(
        of: dialog,
        matching: find.widgetWithText(ElevatedButton, 'Delete'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Message'), findsNothing);
  });

  testWidgets('Fork Conversation is a warm confirm; Cancel closes it', (
    tester,
  ) async {
    await pumpBubbles(tester);
    await tester.tap(find.byIcon(Icons.call_split).first);
    await tester.pumpAndSettle();

    final dialog = find.widgetWithText(WarmDialog, 'Fork Conversation');
    expect(dialog, findsOneWidget);
    expect(tester.widget<WarmDialog>(dialog).destructive, isFalse);
    expect(find.textContaining('message #2'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Fork Conversation'), findsNothing);
  });
}
