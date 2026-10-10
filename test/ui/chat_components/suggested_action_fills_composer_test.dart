// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tapping a "Suggest actions" pill puts its text in the message box (focused,
// cursor at the end) so the user can edit it before pressing Send. It used
// to send at once with no chance to edit. The bubble is the real one; the
// message box is a plain field wired through ComposerDraftScope exactly as
// the chat page wires its own box.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes.dart';

const _idea = 'Offer to help carry the chairs';

class _ChatWithIdeas extends FakeChatService {
  _ChatWithIdeas(List<ChatMessage> messages) : super(messages: messages);

  @override
  List<String> get suggestedActions => const [_idea];
}

void main() {
  setupPathProviderMock();

  Future<(TextEditingController, FocusNode)> pumpChat(
    WidgetTester tester, {
    String draft = '',
  }) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    addTearDown(storage.dispose);
    final tts = FakeTtsService();
    addTearDown(tts.dispose);
    final reply = ChatMessage(
      text: 'Bex eyes the stack of chairs.',
      sender: 'Bex',
      isUser: false,
    );
    final chat = _ChatWithIdeas([reply]);
    addTearDown(chat.dispose);
    final box = TextEditingController(text: draft);
    addTearDown(box.dispose);
    final focus = FocusNode();
    addTearDown(focus.dispose);
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
            child: Column(
              children: [
                ComposerDraftScope(
                  controller: box,
                  focusNode: focus,
                  child: SizedBox(
                    width: 680,
                    child: MessageBubble(
                      message: reply,
                      index: 0,
                      chatService: chat,
                    ),
                  ),
                ),
                TextField(controller: box, focusNode: focus),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return (box, focus);
  }

  testWidgets('tapping a suggestion fills the message box, does not send', (
    tester,
  ) async {
    final (box, focus) = await pumpChat(tester);
    expect(find.text(_idea), findsOneWidget);

    await tester.tap(find.text(_idea));
    await tester.pump();

    // FakeChatService cannot send (the real send would throw here), so a
    // clean run also proves nothing was sent.
    expect(tester.takeException(), isNull);
    expect(box.text, _idea);
    expect(box.selection, const TextSelection.collapsed(offset: _idea.length));
    expect(focus.hasFocus, isTrue);
  });

  testWidgets('a half-typed draft is kept; the suggestion goes after it', (
    tester,
  ) async {
    final (box, _) = await pumpChat(tester, draft: 'Sure,');
    await tester.tap(find.text(_idea));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(box.text, 'Sure, $_idea');
  });
}
