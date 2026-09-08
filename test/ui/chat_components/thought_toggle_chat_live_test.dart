// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes.dart';

ChatMessage _finishedThought(String plan) {
  return ChatMessage(
    text: '<think>$plan</think>\nhello there',
    sender: 'Iris',
    isUser: false,
  )..thinkingDurationMs = 1200;
}

ChatMessage _liveThought(String plan) {
  return ChatMessage(
    text: '<think>$plan</think>\nhello there',
    sender: 'Iris',
    isUser: false,
  )..thinkingStartTime = DateTime.now().millisecondsSinceEpoch;
}

Widget _bareBubble(ChatMessage msg, {bool? isGenerating}) {
  return MaterialApp(
    home: Scaffold(
      body: MessageBubble(message: msg, index: 0, isGenerating: isGenerating),
    ),
  );
}

Widget _provided({required FakeChatService chat, required Widget child}) {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService();
  addTearDown(storage.dispose);
  final tts = FakeTtsService();
  addTearDown(tts.dispose);
  return MaterialApp(
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
        child: SizedBox(width: 680, child: child),
      ),
    ),
  );
}

void main() {
  setupPathProviderMock();

  testWidgets('global generate does not expand a finished prior Thought', (
    tester,
  ) async {
    final chat = FakeChatService(isGenerating: true);
    addTearDown(chat.dispose);
    await tester.pumpWidget(
      _provided(
        chat: chat,
        child: MessageBubble(
          message: _finishedThought('old secret plan'),
          index: 0,
          chatService: chat,
        ),
      ),
    );
    expect(find.text('old secret plan'), findsNothing);
    expect(find.text('Thought'), findsOneWidget);
  });

  testWidgets('mid-think message auto-opens when isGenerating is omitted', (
    tester,
  ) async {
    await tester.pumpWidget(_bareBubble(_liveThought('live secret plan')));
    expect(find.text('live secret plan'), findsOneWidget);
    expect(find.textContaining('Thinking'), findsOneWidget);
  });

  testWidgets(
    'explicit isGenerating true auto-opens even without mid-think stamps',
    (tester) async {
      await tester.pumpWidget(
        _bareBubble(_finishedThought('waifu live plan'), isGenerating: true),
      );
      expect(find.text('waifu live plan'), findsOneWidget);
    },
  );

  testWidgets('chevron pin wins over mid-think auto-open', (tester) async {
    await tester.pumpWidget(_bareBubble(_liveThought('pinned secret plan')));
    expect(find.text('pinned secret plan'), findsOneWidget);

    await tester.tap(find.byKey(const Key('thought-toggle')));
    await tester.pump();
    expect(find.text('pinned secret plan'), findsNothing);
    expect(find.textContaining('Thinking'), findsOneWidget);

    await tester.tap(find.byKey(const Key('thought-toggle')));
    await tester.pump();
    expect(find.text('pinned secret plan'), findsOneWidget);
  });

  testWidgets(
    'chat list with global generate expands only the live mid-think bubble',
    (tester) async {
      final chat = FakeChatService(isGenerating: true);
      addTearDown(chat.dispose);
      await tester.pumpWidget(
        _provided(
          chat: chat,
          child: ChatMessageList(
            messages: [
              _finishedThought('old secret plan'),
              _liveThought('live secret plan'),
            ],
            resolveSpeaker: (_) => (null, null),
            chatService: chat,
          ),
        ),
      );
      expect(find.text('old secret plan'), findsNothing);
      expect(find.text('live secret plan'), findsOneWidget);
    },
  );
}
