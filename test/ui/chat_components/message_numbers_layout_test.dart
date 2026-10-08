// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Every chat bubble carries its place in the whole chat under the avatar,
// counting from #1 — the same number the Journal and Growth receipts show.
// The user's bubble uses the character's layout: avatar on the left, name
// row on top, edit / fork / delete at the right of that row.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes.dart';

class _TailOpenChat extends FakeChatService {
  _TailOpenChat({required super.messages});

  /// 40 older lines are still loading behind the open tail.
  @override
  int get historyBasePosition => 40;
}

final _messages = [
  ChatMessage(text: 'Evening, stranger.', sender: 'Iris', isUser: false),
  ChatMessage(text: 'Pull up a chair.', sender: 'Sam', isUser: true),
  ChatMessage(text: 'Don’t mind if I do.', sender: 'Iris', isUser: false),
];

(File?, Color?) _noSpeaker(ChatMessage _) => (null, null);

Future<void> _pump(WidgetTester tester, FakeChatService chat) async {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService();
  addTearDown(storage.dispose);
  final tts = FakeTtsService();
  addTearDown(tts.dispose);
  addTearDown(chat.dispose);
  await tester.binding.setSurfaceSize(const Size(900, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
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
            sessionId: 's1',
            messages: chat.messages,
            chatService: chat,
            resolveSpeaker: _noSpeaker,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<String> _numbers(WidgetTester tester) => [
  for (final e in find.byKey(const Key('message-number')).evaluate())
    (e.widget as Text).data!,
];

Finder _inBubble(int index, Finder matching) => find.descendant(
  of: find.byWidgetPredicate((w) => w is MessageBubble && w.index == index),
  matching: matching,
);

void main() {
  setupPathProviderMock();

  testWidgets('first message is #1, and each bubble counts up', (tester) async {
    await _pump(tester, FakeChatService(messages: _messages));
    expect(_numbers(tester), ['#1', '#2', '#3']);
  });

  testWidgets('numbers count the older lines still loading', (tester) async {
    await _pump(tester, _TailOpenChat(messages: _messages));
    expect(_numbers(tester), ['#41', '#42', '#43']);
  });

  testWidgets('the number sits under the avatar', (tester) async {
    await _pump(tester, FakeChatService(messages: _messages));
    for (var i = 0; i < _messages.length; i++) {
      final avatar = tester.getRect(_inBubble(i, find.byType(CircleAvatar)));
      final number = tester.getRect(
        _inBubble(i, find.byKey(const Key('message-number'))),
      );
      expect(number.top, greaterThanOrEqualTo(avatar.bottom), reason: '#$i');
      expect(number.center.dx, closeTo(avatar.center.dx, 2), reason: '#$i');
    }
  });

  testWidgets('the user bubble matches the character layout', (tester) async {
    await _pump(tester, FakeChatService(messages: _messages));
    final charAvatar = tester.getRect(_inBubble(0, find.byType(CircleAvatar)));
    final userAvatar = tester.getRect(_inBubble(1, find.byType(CircleAvatar)));
    expect(userAvatar.left, closeTo(charAvatar.left, 1));

    final userName = tester.getRect(_inBubble(1, find.text('Sam')));
    final userEdit = tester.getRect(
      _inBubble(1, find.byIcon(Icons.edit_outlined)),
    );
    final userBody = tester.getRect(
      _inBubble(1, find.textContaining('Pull up a chair.', findRichText: true)),
    );
    expect(userName.left, greaterThan(userAvatar.right));
    expect(userEdit.left, greaterThan(userName.right));
    expect(userEdit.bottom, lessThanOrEqualTo(userBody.top + 1));

    final charEdit = tester.getRect(
      _inBubble(0, find.byIcon(Icons.edit_outlined)),
    );
    expect(userEdit.right, closeTo(charEdit.right, 1));
  });
}
