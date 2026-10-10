// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A reply that repeats the last one word for word, landing together with
// the message before it, is new rows at the bottom, not older history at
// the top. Read as older history, it slid the mounted rows down and the
// first lines of a short chat left the screen with no way back: nothing
// to scroll, so nothing to reveal them.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';

(File?, Color?) _noSpeaker(ChatMessage _) => (null, null);

const _reply = 'The same reply, word for word.';

Future<void> _pumpList(WidgetTester tester, List<ChatMessage> messages) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageList(
            key: const ValueKey('list'),
            sessionId: 's1',
            messages: messages,
            resolveSpeaker: _noSpeaker,
          ),
        ),
      ),
    );

Iterable<ChatMessage> _built() => find
    .byType(MessageBubble)
    .evaluate()
    .map((e) => (e.widget as MessageBubble).message);

void main() {
  testWidgets('a repeated reply landing with its prompt keeps the first '
      'lines of a short chat on screen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final greeting = ChatMessage(
      text: 'Welcome to the porch.',
      sender: 'Iris',
      isUser: false,
    );
    final firstLine = ChatMessage(
      text: 'The swing creaks.',
      sender: 'You',
      isUser: true,
    );
    final messages = [
      greeting,
      firstLine,
      ChatMessage(text: _reply, sender: 'Iris', isUser: false),
    ];
    await _pumpList(tester, messages);
    await tester.pumpAndSettle();
    expect(_built(), contains(same(greeting)));

    // A fast backend: the next line and its reply both land before the
    // list rebuilds, and the reply is the last one again.
    messages
      ..add(ChatMessage(text: 'Tell me more.', sender: 'You', isUser: true))
      ..add(ChatMessage(text: _reply, sender: 'Iris', isUser: false));
    await _pumpList(tester, messages);
    await tester.pumpAndSettle();

    final built = _built().toList();
    expect(
      built.length,
      messages.length,
      reason:
          'a five-line chat fits on screen; every line must be built, '
          'got ${built.map((m) => m.text).toList()}',
    );
    expect(built, contains(same(greeting)));
    expect(built, contains(same(firstLine)));
  });
}
