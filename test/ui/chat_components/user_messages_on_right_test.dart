// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → General "My messages on the right": off, the user's row is laid out
// like the character's; on, it is mirrored — avatar on the right, the
// bubble against it, the name at the right and the buttons at the left.
// The character's row never moves, and the message number stays under the
// avatar either way.

import 'dart:async';
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

final _messages = [
  ChatMessage(text: 'Evening, stranger.', sender: 'Iris', isUser: false),
  ChatMessage(text: 'Pull up a chair.', sender: 'Sam', isUser: true),
];

(File?, Color?) _noSpeaker(ChatMessage _) => (null, null);

Future<void> _pump(WidgetTester tester, {required bool onRight}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService();
  addTearDown(storage.dispose);
  // Set before the first build: settings do not finish loading inside a
  // widget test, so there is nothing to notify and nothing to overwrite it.
  if (onRight) unawaited(storage.realismSettings.setUserMessagesOnRight(true));
  final tts = FakeTtsService();
  addTearDown(tts.dispose);
  final chat = FakeChatService(messages: _messages);
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

Finder _inBubble(int index, Finder matching) => find.descendant(
  of: find.byWidgetPredicate((w) => w is MessageBubble && w.index == index),
  matching: matching,
);

void main() {
  setupPathProviderMock();

  Rect avatar(WidgetTester t, int i) =>
      t.getRect(_inBubble(i, find.byType(CircleAvatar)));
  Rect body(WidgetTester t) => t.getRect(
    _inBubble(1, find.textContaining('Pull up a chair.', findRichText: true)),
  );
  Rect name(WidgetTester t) => t.getRect(_inBubble(1, find.text('Sam')));
  Rect edit(WidgetTester t) =>
      t.getRect(_inBubble(1, find.byIcon(Icons.edit_outlined)));

  testWidgets('off (the default): the user row is laid out like the '
      'character\'s', (tester) async {
    await _pump(tester, onRight: false);
    expect(avatar(tester, 1).left, closeTo(avatar(tester, 0).left, 1));
    expect(avatar(tester, 1).right, lessThan(body(tester).left));
    expect(name(tester).right, lessThan(edit(tester).left));
  });

  testWidgets('on: the user row is mirrored and the character row is not', (
    tester,
  ) async {
    await _pump(tester, onRight: true);
    // Avatar at the right edge with the bubble against it.
    expect(avatar(tester, 1).left, greaterThan(body(tester).right));
    expect(avatar(tester, 1).right, greaterThan(800));
    // Name on the right of the header, buttons on the left of it.
    expect(edit(tester).right, lessThan(name(tester).left));
    // The number is still under the avatar.
    final number = tester.getRect(
      _inBubble(1, find.byKey(const Key('message-number'))),
    );
    expect(number.center.dx, closeTo(avatar(tester, 1).center.dx, 2));
    // The character keeps the left.
    expect(avatar(tester, 0).left, lessThan(100));
  });
}
