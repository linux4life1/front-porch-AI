// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Impersonate writes the user's next line into the input box. While it
// runs, the character's last reply must not say "Thinking Ns..." (a start
// left on it from an earlier reply counted half an hour), and the strip
// under the chat must say what is happening instead of "Idle".

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes.dart';

/// The last reply as the field report left it: a think start from half an
/// hour ago and no duration on the swipe now showing.
ChatMessage _staleReply() =>
    ChatMessage(text: 'She leans on the rail.', sender: 'Iris', isUser: false)
      ..thinkingStartTime = DateTime.now().millisecondsSinceEpoch - 1797000;

Future<void> _pump(WidgetTester tester, FakeChatService chat) async {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService();
  addTearDown(storage.dispose);
  final tts = FakeTtsService();
  addTearDown(tts.dispose);
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
              Expanded(
                child: ChatMessageList(
                  messages: chat.messages,
                  resolveSpeaker: (_) => (null, null),
                  chatService: chat,
                  replyStreaming: true,
                ),
              ),
              GenerationStatusBar(chatService: chat),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  testWidgets('Impersonate puts no thinking timer on the last reply', (
    tester,
  ) async {
    final chat = FakeChatService(
      isGenerating: true,
      generationPhase: GenerationPhase.impersonating,
      messages: [_staleReply()],
    );
    addTearDown(chat.dispose);
    await _pump(tester, chat);

    expect(find.textContaining('Thinking'), findsNothing);
    expect(find.text('Writing your reply…'), findsOneWidget);
    expect(find.text('Idle'), findsNothing);
    expect(find.textContaining('She leans on the rail'), findsOneWidget);
    // The bars tick on timers: take them down before the test ends.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a reply streaming into that bubble still shows its timer', (
    tester,
  ) async {
    // Control: the harness does see the timer when the bubble is the one
    // being written, so the case above is not passing by accident.
    final chat = FakeChatService(
      isGenerating: true,
      generationPhase: GenerationPhase.thinking,
      messages: [_staleReply()],
    );
    addTearDown(chat.dispose);
    await _pump(tester, chat);

    expect(find.textContaining('Thinking 17'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
