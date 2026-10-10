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

// The pill, not the message box once it holds the same words.
Finder get _pill =>
    find.byTooltip('Click to put it in your message box. Hold to send it now.');

void main() {
  setupPathProviderMock();

  Future<(TextEditingController, FocusNode, List<String>)> pumpChat(
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
    final sent = <String>[];
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
                  onSend: sent.add,
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
    return (box, focus, sent);
  }

  testWidgets('tapping a suggestion fills the message box, does not send', (
    tester,
  ) async {
    final (box, focus, sent) = await pumpChat(tester);
    expect(find.text(_idea), findsOneWidget);

    await tester.tap(_pill);
    await tester.pump();

    // FakeChatService cannot send (the real send would throw here), so a
    // clean run also proves nothing was sent.
    expect(tester.takeException(), isNull);
    expect(box.text, _idea);
    expect(box.selection, const TextSelection.collapsed(offset: _idea.length));
    expect(focus.hasFocus, isTrue);
    expect(sent, isEmpty);
  });

  testWidgets('a half-typed draft is kept; the suggestion goes after it', (
    tester,
  ) async {
    final (box, _, _) = await pumpChat(tester, draft: 'Sure,');
    await tester.tap(_pill);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(box.text, 'Sure, $_idea');
  });

  testWidgets('tapping the same suggestion twice puts it in once', (
    tester,
  ) async {
    final (box, _, _) = await pumpChat(tester);
    await tester.tap(_pill);
    await tester.pump();
    await tester.tap(_pill);
    await tester.pump();
    expect(box.text, _idea);
  });

  testWidgets('tap then hold: sent once, and the box is emptied', (
    tester,
  ) async {
    final (box, _, sent) = await pumpChat(tester);
    await tester.tap(_pill);
    await tester.pump();
    await tester.longPress(_pill);
    await tester.pump();
    // The old hold called the service directly; the fake cannot send, so
    // that path throws here.
    expect(tester.takeException(), isNull);
    expect(sent, [_idea]);
    expect(box.text, isEmpty, reason: 'a second Send must not resend it');
  });

  testWidgets('hold with a typed draft: the draft stays in the box', (
    tester,
  ) async {
    final (box, _, sent) = await pumpChat(tester, draft: 'Sure,');
    await tester.longPress(_pill);
    await tester.pump();
    expect(sent, [_idea]);
    expect(box.text, 'Sure,');

    // Tapped onto the draft first, then held: only the suggestion leaves.
    await tester.tap(_pill);
    await tester.pump();
    expect(box.text, 'Sure, $_idea');
    await tester.longPress(_pill);
    await tester.pump();
    expect(sent, [_idea, _idea]);
    expect(box.text, 'Sure,');
  });
}
