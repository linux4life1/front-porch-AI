// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The optional regen-critique field lives in a dialog that opens on Regen,
// not as always-on chrome under the bubble.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/tts_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/ui/chat_components/bubbles/message_bubble.dart';
import 'package:front_porch_ai/ui/chat_components/widgets/regen_critique_field.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes.dart';

StorageService _storage() {
  SharedPreferences.setMockInitialValues({});
  return StorageService();
}

const _fieldKey = Key('regen-critique-field');

void main() {
  setupPathProviderMock();

  Future<void> pumpBubble(
    WidgetTester tester, {
    required List<ChatMessage> messages,
    required int index,
  }) async {
    final character = CharacterCard(name: 'Mara');
    final chat = FakeChatService(
      activeCharacter: character,
      messages: messages,
    );
    addTearDown(chat.dispose);
    final tts = FakeTtsService();
    addTearDown(tts.dispose);
    final storage = _storage();
    addTearDown(storage.dispose);

    final bubble = MessageBubble(
      message: messages[index],
      index: index,
      character: character,
      chatService: chat,
    );

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
            child: SizedBox(width: 680, child: bubble),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('field is hidden until Regen is tapped', (tester) async {
    await pumpBubble(
      tester,
      messages: [
        ChatMessage(text: 'hi', sender: 'Sam', isUser: true),
        ChatMessage(
          text: 'He stands at the window.',
          sender: 'Mara',
          isUser: false,
        ),
      ],
      index: 1,
    );

    expect(find.byKey(_fieldKey), findsNothing);
    expect(find.text('why this take was wrong — optional'), findsNothing);

    await tester.tap(find.byTooltip('Regenerate'));
    await tester.pumpAndSettle();

    expect(find.byKey(_fieldKey), findsOneWidget);
    expect(find.text('why this take was wrong — optional'), findsOneWidget);
  });

  testWidgets('field is hidden on the opening greet', (tester) async {
    await pumpBubble(
      tester,
      messages: [
        ChatMessage(
          text: 'The porch light hums.',
          sender: 'Mara',
          isUser: false,
        ),
      ],
      index: 0,
    );
    expect(find.byKey(_fieldKey), findsNothing);
    expect(find.byTooltip('Regenerate'), findsNothing);
  });

  testWidgets('cancel closes the dialog without a field left behind', (
    tester,
  ) async {
    await pumpBubble(
      tester,
      messages: [
        ChatMessage(text: 'hi', sender: 'Sam', isUser: true),
        ChatMessage(
          text: 'He stands at the window.',
          sender: 'Mara',
          isUser: false,
        ),
      ],
      index: 1,
    );
    await tester.tap(find.byTooltip('Regenerate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byKey(_fieldKey), findsNothing);
  });

  testWidgets('blank confirm still starts regen', (tester) async {
    String? got;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => promptRegenCritiqueThen(context, (c) {
                got = c;
              }),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('regen-critique-confirm')));
    await tester.pumpAndSettle();
    expect(got, '');
  });

  testWidgets('long critique expands downward instead of scrolling sideways', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showRegenCritiqueDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byKey(_fieldKey));
    expect(field.maxLines, isNot(1));
    expect(field.minLines, greaterThanOrEqualTo(2));
    expect(field.maxLines, anyOf(isNull, greaterThanOrEqualTo(3)));
    final oneLineHeight = tester.getSize(find.byKey(_fieldKey)).height;
    await tester.enterText(
      find.byKey(_fieldKey),
      'This take was wrong because it lectured for a full page '
      'instead of answering, then repeated the lecture, then '
      'ignored the actual question about the keys on the table.',
    );
    await tester.pump();
    final grown = tester.getSize(find.byKey(_fieldKey));
    expect(
      grown.height,
      greaterThanOrEqualTo(oneLineHeight),
      reason: 'field must grow down (or stay a multi-line box), never one line',
    );
    expect(
      grown.width,
      lessThanOrEqualTo(tester.getSize(find.byType(AlertDialog)).width),
    );
  });

  testWidgets('dialog field is hittable when focused', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showRegenCritiqueDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final field = find.byKey(_fieldKey);
    expect(field.hitTestable(), findsOneWidget);
  });
}
