// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The goal-check overlay offers "Skip goal check", and a tap reaches
// ChatService.skipObjectiveCheck (the service side is pinned in
// test/services/chat/objective_check_skip_test.dart).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/chat_components/chat_components.dart';

import '../../golden/support/fakes.dart';

class _CheckingChat extends FakeChatService {
  int skips = 0;

  @override
  bool get isCheckingCompletion => true;

  @override
  void skipObjectiveCheck() => skips++;
}

void main() {
  testWidgets(
    'Skip goal check on the objective overlay asks the chat to skip',
    (tester) async {
      final chat = _CheckingChat();
      addTearDown(chat.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(children: [ObjectiveCheckOverlay(chatService: chat)]),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      final skip = find.widgetWithText(OutlinedButton, 'Skip goal check');
      expect(skip, findsOneWidget);
      await tester.tap(skip);
      await tester.pump();
      expect(chat.skips, 1);
    },
  );
}
