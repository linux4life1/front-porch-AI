// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// Quoted speech inside the user's own bubble must read on that bubble. With
// a green user bubble and the default orange dialogue tint the quotes were
// near-invisible (contrast ~2:1). The real MessageBubble is pumped with the
// real StorageService; the quote's span colour is read off the rendered
// text and measured against the bubble colour the settings resolve to.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/bubbles/message_bubble.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes.dart';

const _emerald = Color(0xFF10B981);
const _darkInk = Color(0xFF1F1F1F);
const _quote = '"They\'re amazing,"';

/// Colour of the span that carries [quote] inside the bubble at [index].
Color _quoteColor(WidgetTester tester, String quote) {
  Color? found;
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    final root = text.textSpan;
    if (root == null) continue;
    root.visitChildren((span) {
      if (span is TextSpan && span.text == quote) {
        found = span.style?.color;
        return false;
      }
      return true;
    });
    if (found != null) break;
  }
  expect(found, isNotNull, reason: 'the quote $quote was not rendered');
  return found!;
}

Future<StorageService> _pump(
  WidgetTester tester, {
  required bool isUser,
  Color? dialogue,
}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService();
  addTearDown(storage.dispose);
  // Light mode with the user's own green bubble and dark text (Chat
  // Appearance), the dialogue tint left at its default unless [dialogue].
  unawaited(storage.uiSettings.setIsDark(false));
  unawaited(storage.uiSettings.setGlobalUserBubbleColor(_emerald));
  unawaited(storage.uiSettings.setGlobalUserTextColor(_darkInk));
  if (dialogue != null) {
    unawaited(storage.uiSettings.setGlobalDialogueColor(dialogue));
  }
  final msg = ChatMessage(
    text: 'I sit down. $_quote I say, smiling.',
    sender: isUser ? 'User' : 'Carmen',
    isUser: isUser,
  );
  final chat = FakeChatService(messages: [msg]);
  addTearDown(chat.dispose);
  final tts = FakeTtsService();
  addTearDown(tts.dispose);
  await tester.binding.setSurfaceSize(const Size(900, 400));
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
          child: MessageBubble(
            message: msg,
            index: 0,
            character: CharacterCard(name: 'Carmen'),
            chatService: chat,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return storage;
}

void main() {
  setupPathProviderMock();

  testWidgets('default dialogue tint is re-tinted to read on a green '
      'user bubble', (tester) async {
    await _pump(tester, isUser: true);
    final color = _quoteColor(tester, _quote);
    expect(
      contrastRatio(color, _emerald),
      greaterThanOrEqualTo(kMinUserDialogueContrast),
      reason:
          'the default orange quote on the green bubble measured '
          '${contrastRatio(AppColors.dialogueLight, _emerald).toStringAsFixed(2)}:1; '
          'the drawn quote must reach $kMinUserDialogueContrast:1',
    );
    // Same hue family, darker: dark text sits on this bubble, so the quote
    // goes dark with it rather than flipping to a stranger colour.
    expect(
      color.computeLuminance(),
      lessThan(AppColors.dialogueLight.computeLuminance()),
    );
    // The sender name in the bubble header uses the same tint.
    final name = tester.widget<Text>(find.text('User'));
    expect(name.style?.color, color);
  });

  testWidgets('a dialogue colour the user picked is kept as is', (
    tester,
  ) async {
    const picked = Color(0xFFE65100);
    await _pump(tester, isUser: true, dialogue: picked);
    expect(_quoteColor(tester, _quote), picked);
  });

  testWidgets("the character's bubble keeps the default dialogue tint", (
    tester,
  ) async {
    await _pump(tester, isUser: false);
    expect(_quoteColor(tester, _quote), AppColors.dialogueLight);
  });
}
