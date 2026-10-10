// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Editing your own message must not offer a "Thinking" section: user
// messages have no model reasoning. A character's message keeps it. Driven
// from the real bubble's Edit button, so the call site is what is pinned.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes.dart';

Future<void> _openEditor(WidgetTester tester, ChatMessage message) async {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService();
  addTearDown(storage.dispose);
  final tts = FakeTtsService();
  addTearDown(tts.dispose);
  final chat = FakeChatService();
  addTearDown(chat.dispose);
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
          child: SizedBox(
            width: 680,
            child: MessageBubble(message: message, index: 0, chatService: chat),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byTooltip('Edit message'));
  await tester.pumpAndSettle();
  expect(find.text('Edit Message'), findsOneWidget);
}

Finder _inEditor(Finder f) =>
    find.descendant(of: find.byType(Dialog), matching: f);

void main() {
  setupPathProviderMock();

  testWidgets('editing your own message shows no Thinking section', (
    tester,
  ) async {
    await _openEditor(
      tester,
      ChatMessage(text: 'I brought peaches.', sender: 'You', isUser: true),
    );
    expect(_inEditor(find.text('Thinking')), findsNothing);
    expect(
      _inEditor(find.text('Edit model reasoning (no tags needed)')),
      findsNothing,
    );
    expect(_inEditor(find.text('Message')), findsOneWidget);
  });

  testWidgets('editing a character message keeps the Thinking section', (
    tester,
  ) async {
    await _openEditor(
      tester,
      ChatMessage(text: 'Evening, neighbor.', sender: 'Carmen', isUser: false),
    );
    expect(_inEditor(find.text('Thinking')), findsOneWidget);
  });
}
