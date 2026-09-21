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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes.dart';

ChatMessage _thoughtAndSpeech() {
  return ChatMessage(
    text: '<think>secret plan</think>\nspoken line here',
    sender: 'Iris',
    isUser: false,
  )..thinkingDurationMs = 1200;
}

Widget _withProviders({required Widget child, ChatService? chat}) {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService();
  addTearDown(storage.dispose);
  final tts = FakeTtsService();
  addTearDown(tts.dispose);
  final resolved = chat ?? FakeChatService();
  if (chat == null) addTearDown(resolved.dispose);
  return MaterialApp(
    home: Scaffold(
      body: MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<TtsService>.value(value: tts),
          ChangeNotifierProvider<ChatService>.value(value: resolved),
          ChangeNotifierProvider<UserPersonaService>.value(
            value: FakeUserPersonaService(),
          ),
        ],
        child: SizedBox(width: 680, child: child),
      ),
    ),
  );
}

void main() {
  setupPathProviderMock();

  testWidgets('StyledChatMessage does not own a SelectionArea', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    addTearDown(storage.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: storage,
        child: const MaterialApp(
          home: Scaffold(
            body: StyledChatMessage(text: 'hello speech', isUser: false),
          ),
        ),
      ),
    );
    expect(find.byType(SelectionArea), findsNothing);
    expect(find.text('hello speech'), findsOneWidget);
  });

  testWidgets('expanded thought and speech share one body SelectionArea', (
    tester,
  ) async {
    final chat = FakeChatService();
    addTearDown(chat.dispose);
    await tester.pumpWidget(
      _withProviders(
        chat: chat,
        child: MessageBubble(
          message: _thoughtAndSpeech(),
          index: 0,
          chatService: chat,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('thought-toggle')));
    await tester.pump();
    expect(find.text('secret plan'), findsOneWidget);
    expect(find.text('spoken line here'), findsOneWidget);
    final area = tester.element(find.text('spoken line here'));
    expect(area.findAncestorWidgetOfExactType<SelectionArea>(), isNotNull);
    final thought = tester.element(find.text('secret plan'));
    expect(thought.findAncestorWidgetOfExactType<SelectionArea>(), isNotNull);
  });

  testWidgets('thought chip still toggles under a selectable body', (
    tester,
  ) async {
    final chat = FakeChatService();
    addTearDown(chat.dispose);
    await tester.pumpWidget(
      _withProviders(
        chat: chat,
        child: MessageBubble(
          message: _thoughtAndSpeech(),
          index: 0,
          chatService: chat,
        ),
      ),
    );
    expect(find.text('secret plan'), findsNothing);
    await tester.tap(find.byKey(const Key('thought-toggle')));
    await tester.pump();
    expect(find.text('secret plan'), findsOneWidget);
  });
}
