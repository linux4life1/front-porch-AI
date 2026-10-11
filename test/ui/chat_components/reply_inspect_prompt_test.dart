// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Inspect prompt on a reply: the bubble shows the button only when the swipe
// carries a prompt record, and tapping it opens the Context viewer on that
// reply's send (not the chat's last one), with no live refresh. An older
// reply whose text was trimmed says so.
//
// Proven red: removing the header button fails the tap; dropping the
// snapshot argument in _showReplyContext shows "No budget" instead.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes.dart';

ChatMessage _reply(String text, Map<String, dynamic>? record) {
  final meta = record == null ? null : {kReplyContextKey: record};
  return ChatMessage(
    text: text,
    sender: 'Carmen',
    isUser: false,
    metadata: meta,
    swipeMetadata: [meta],
  );
}

void main() {
  setupPathProviderMock();

  Future<void> pumpReplies(WidgetTester tester, List<ChatMessage> msgs) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    addTearDown(storage.dispose);
    final chat = FakeChatService();
    addTearDown(chat.dispose);
    final tts = FakeTtsService();
    addTearDown(tts.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<TtsService>.value(value: tts),
          ChangeNotifierProvider<ChatService>.value(value: chat),
          ChangeNotifierProvider<UserPersonaService>.value(
            value: FakeUserPersonaService(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                for (var i = 0; i < msgs.length; i++)
                  MessageBubble(message: msgs[i], index: i, chatService: chat),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a reply with a record opens its own prompt', (tester) async {
    await pumpReplies(tester, [
      _reply('She hands you a peach.', {
        'budget': {'Chat History': 120, 'System Prompt': 40},
        'sections': {'Chat History': 'You: is that a peach?'},
        'contextLimit': 4096,
      }),
    ]);

    await tester.tap(find.byTooltip('Inspect prompt'));
    await tester.pumpAndSettle();

    expect(find.textContaining('This reply'), findsOneWidget);
    expect(find.text('Total: 160 / 4096 tokens'), findsOneWidget);
    expect(find.byTooltip('Refresh estimate from this chat'), findsNothing);

    await tester.tap(find.text('Chat History'));
    await tester.pumpAndSettle();
    expect(find.text('You: is that a peach?'), findsOneWidget);
  });

  testWidgets('an older reply says only counts were kept', (tester) async {
    await pumpReplies(tester, [
      _reply('She hands you a peach.', {
        'budget': {'Chat History': 120},
        'contextLimit': 4096,
      }),
    ]);

    await tester.tap(find.byTooltip('Inspect prompt'));
    await tester.pumpAndSettle();
    expect(
      find.text('Only the token counts are kept for older replies.'),
      findsOneWidget,
    );
  });

  testWidgets('a reply without a record has no button', (tester) async {
    await pumpReplies(tester, [_reply('She hands you a peach.', null)]);
    expect(find.byTooltip('Inspect prompt'), findsNothing);
  });
}
