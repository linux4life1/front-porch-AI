// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A finished group speaker whose think never recorded a duration must not
// keep saying "Thinking…" for the whole time the next speaker generates.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  testWidgets(
    'an earlier open think does not tick while a later reply generates',
    (tester) async {
      final iris = ChatMessage(
        text: '<think>still planning the scene',
        sender: 'Iris',
        isUser: false,
      )..thinkingStartTime = DateTime.now().millisecondsSinceEpoch - 896000;
      final sophia = ChatMessage(
        text: 'I let out a soft laugh.',
        sender: 'Sophia',
        isUser: false,
      );
      final messages = [iris, sophia];
      final chat = FakeChatService(isGenerating: true, messages: messages);
      addTearDown(chat.dispose);
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      addTearDown(storage.dispose);
      final tts = FakeTtsService();
      addTearDown(tts.dispose);

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
              child: ChatMessageList(
                messages: messages,
                resolveSpeaker: (_) => (null, null),
                chatService: chat,
                replyStreaming: true,
              ),
            ),
          ),
        ),
      );

      expect(find.textContaining('Thinking'), findsNothing);
      expect(find.textContaining('Only thoughts this turn'), findsOneWidget);
      expect(find.textContaining('I let out a soft laugh'), findsOneWidget);
    },
  );
}
