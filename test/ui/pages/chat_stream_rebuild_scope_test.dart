// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A streaming reply rebuilds the transcript per token batch, not the whole
// chat page: the composer and the sidebar sit out the streamed-text ticks.
// Each wasted rebuild is UI work competing with a local model for the machine.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/pages/chat_page.dart';
import 'package:front_porch_ai/ui/pages/chat_page.input.dart';
import 'package:front_porch_ai/ui/pages/chat_page.sidebar.dart';

import '../../../integration_test/support/fake_backend.dart';
import 'home/home_page_harness.dart';

void main() {
  testWidgets('streamed text rebuilds the transcript, not the composer or '
      'the sidebar', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final rig = await HomeRig.build(
      tester,
      seed: (db) => seedCharacter(db, 'Ada', 'Ada.png'),
    );
    late FakeBackendServer backend;
    await tester.runAsync(() async {
      backend = await FakeBackendServer.start(
        replyPieces: [for (var i = 0; i < 30; i++) ' word$i'],
        chatChunkDelay: const Duration(milliseconds: 60),
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
    expect(find.byType(ChatRightSidebar), findsOneWidget);

    final rebuilds = <Type, int>{};
    late Future<void> sending;
    await tester.runAsync(() async {
      sending = rig.chat.sendMessage('Tell me a long story.');
    });
    // Count only while reply text is streaming in.
    for (var i = 0; i < 500 && !_streaming(rig.chat); i++) {
      await realWait(10);
    }
    expect(_streaming(rig.chat), isTrue, reason: 'the reply started');
    debugOnRebuildDirtyWidget = (element, _) {
      final t = element.widget.runtimeType;
      rebuilds[t] = (rebuilds[t] ?? 0) + 1;
    };
    try {
      for (var i = 0; i < 500 && rig.chat.isGenerating; i++) {
        await realWait(15);
      }
    } finally {
      debugOnRebuildDirtyWidget = null;
    }
    await tester.runAsync(() => sending);
    await tester.pump();

    final transcript = rebuilds[ChatMessageList] ?? 0;
    expect(
      transcript,
      greaterThanOrEqualTo(10),
      reason: 'the transcript follows the stream ($rebuilds)',
    );
    for (final chrome in [ChatInputArea, ChatRightSidebar]) {
      expect(
        rebuilds[chrome] ?? 0,
        lessThanOrEqualTo(transcript ~/ 4),
        reason: '$chrome rebuilt on streamed-text ticks ($rebuilds)',
      );
    }
    expect(backend.unexpectedPaths, isEmpty);
  });
}

bool _streaming(ChatService chat) {
  if (!chat.isGenerating || chat.messages.isEmpty) return false;
  final last = chat.messages.last;
  return !last.isUser && last.text.contains('word');
}
