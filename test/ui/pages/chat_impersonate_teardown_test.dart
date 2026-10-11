// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ChatService is app-scoped, so an Impersonate keeps streaming after the
// user leaves the chat. Each token is written into the chat page's input
// box; once the page is gone that box is disposed, and the write threw
// inside the stream loop (ChatService logged it and dropped the rest of the
// reply). Here the real chat screen opens from the real library, Impersonate
// is tapped, and the page is closed while the reply is still arriving.
// The reply streams from the loopback FakeBackendServer the impersonate and
// chat-service suites already use; nothing asserts on its text.
// Proven red by dropping the `mounted` check in the impersonate token
// callback (chat_page.input_actions.dart).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/chat_page.dart';

import '../../../integration_test/support/fake_backend.dart';
import 'home/home_page_harness.dart';

void main() {
  testWidgets('leaving the chat mid-Impersonate does not write its input box', (
    tester,
  ) async {
    final rig = await HomeRig.build(
      tester,
      seed: (db) => seedCharacter(db, 'Ada', 'Ada.png'),
    );
    late FakeBackendServer backend;
    await tester.runAsync(() async {
      backend = await FakeBackendServer.start(
        replyPieces: [' I lean', ' on the rail', ' and wait', ' for dusk.'],
        chatChunkDelay: const Duration(milliseconds: 150),
      );
    });
    addTearDown(() => tester.runAsync(backend.close));
    rig.chat.testLlmServiceOverride = OpenRouterService(
      apiUrl: '${backend.baseUrl}/v1',
      modelName: 'smoke-model',
    );

    Future<void> realWait(int ms) async {
      await tester.runAsync(
        () => Future<void>.delayed(Duration(milliseconds: ms)),
      );
      await tester.pump();
    }

    await rig.pump(tester);
    await tester.tap(find.text('Ada').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 300 && rig.chat.isLoadingSession; i++) {
      await realWait(10);
    }
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ChatPage), findsOneWidget);

    final logs = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
      original(message, wrapWidth: wrapWidth);
    };
    try {
      await tester.tap(find.byIcon(Icons.auto_fix_high));
      await tester.pump();

      final typed = find.byWidgetPredicate(
        (w) =>
            w is TextField && (w.controller?.text.contains('I lean') ?? false),
      );
      for (var i = 0; i < 200 && typed.evaluate().isEmpty; i++) {
        await realWait(10);
      }
      expect(typed, findsOneWidget, reason: 'Impersonate is writing the box');
      expect(rig.chat.isGenerating, isTrue, reason: 'and is not done yet');

      Navigator.of(tester.element(find.byType(ChatPage))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(ChatPage), findsNothing);

      for (var i = 0; i < 300 && rig.chat.isGenerating; i++) {
        await realWait(10);
      }
    } finally {
      debugPrint = original;
    }

    expect(rig.chat.isGenerating, isFalse, reason: 'the stream ran out');
    expect(backend.unexpectedPaths, isEmpty);
    // Flutter's own disposed-controller assertion, so the check survives a
    // reworded app log line.
    expect(
      logs.where((l) => l.contains('used after being disposed')),
      isEmpty,
      reason: "the closed page's input controller was written after dispose",
    );
    expect(
      logs.where((l) => l.contains('Impersonate error')),
      isEmpty,
      reason:
          'a token arriving after the chat closed was written into the '
          "closed page's input box",
    );
  });
}
