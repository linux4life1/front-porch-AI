// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A group has no host. Mid-turn its passes lend the active character to the
// member who is speaking; your bubbles took that member's text colour and
// font, and the chat showed their expression picture, until the pass ended.
// The chat page and the bubbles read the host through bubbleHost, which a
// group answers with nobody.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';

import '../../golden/support/fakes.dart';

/// A group mid-turn: a pass has lent the active character to [speaker].
class _GroupMidTurn extends FakeChatService {
  _GroupMidTurn(CharacterCard speaker) : super(activeCharacter: speaker);

  @override
  bool get isGroupMode => true;
}

const _zinnaInk = Color(0xFFE53935);

CharacterCard _zinna() => CharacterCard(
  name: 'Zinna',
  frontPorchExtensions: FrontPorchExtensions(
    userTextColor: _zinnaInk,
    chatFontFamily: 'Zinna Hand',
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a group has no host while a pass lends the pointer', () {
    final zinna = _zinna();
    expect(bubbleHost(_GroupMidTurn(zinna)), isNull);
    expect(
      bubbleHost(FakeChatService(activeCharacter: zinna)),
      same(zinna),
      reason: '1:1 keeps its host',
    );
  });

  testWidgets('your bubble keeps your colour and font mid-turn', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    final chat = _GroupMidTurn(_zinna());
    addTearDown(chat.dispose);
    final yours = ChatMessage(
      text: 'Evening, both of you.',
      sender: 'User',
      isUser: true,
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<TtsService>.value(value: FakeTtsService()),
          ChangeNotifierProvider<ChatService>.value(value: chat),
          ChangeNotifierProvider<UserPersonaService>.value(
            value: FakeUserPersonaService(),
          ),
        ],
        // The transcript hands a user bubble its page's host: none in a
        // group, so the bubble falls back to bubbleHost.
        child: MaterialApp(
          home: Scaffold(
            body: MessageBubble(message: yours, index: 0, chatService: chat),
          ),
        ),
      ),
    );

    // The style your words are drawn in, as the bubble's spans resolve it.
    TextStyle? drawn;
    void walk(InlineSpan span, TextStyle? outer) {
      final style = outer?.merge(span.style) ?? span.style;
      if (span is! TextSpan) return;
      if ((span.text ?? '').contains('Evening')) drawn ??= style;
      for (final child in span.children ?? const <InlineSpan>[]) {
        walk(child, style);
      }
    }

    walk(
      tester
          .widget<RichText>(
            find.textContaining('Evening, both of you.', findRichText: true),
          )
          .text,
      null,
    );
    expect(drawn?.color, storage.uiSettings.getUserTextColor(null));
    expect(drawn?.color, isNot(_zinnaInk));
    expect(drawn?.fontFamily, isNot('Zinna Hand'));
  });
}
