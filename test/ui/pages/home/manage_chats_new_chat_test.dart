// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Focused widget test of the extracted Chat History dialog — rows, trash
// confirm, empty copy. Does not launch the full app.

//
// Manage Chats always offers Start New Chat — with zero or one saved chat
// too, not only when the list is long. Tapping it closes the dialog first,
// then hands off to the caller's new-chat flow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/pages/home/dialogs/chat_history_dialog.dart';

Future<void> _open(
  WidgetTester tester,
  List<Map<String, dynamic>> sessions,
  Future<void> Function() onNewChat,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => ChatHistoryDialog(
              initialSessions: sessions,
              loadSessions: () async => sessions,
              onOpen: (_) async {},
              onDelete: (_) async {},
              onSaveMeta: (_, _, _) async {},
              onNewChat: onNewChat,
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  for (final count in [0, 1]) {
    testWidgets('Start New Chat is offered with $count saved chat(s)', (
      tester,
    ) async {
      var started = 0;
      final sessions = [
        for (var i = 0; i < count; i++)
          {'id': 's$i', 'preview': 'Chat $i', 'date': DateTime(2026, 10, 11)},
      ];
      await _open(tester, sessions, () async => started++);

      expect(find.text('Manage Chats'), findsOneWidget);
      await tester.tap(find.text('Start New Chat'));
      await tester.pumpAndSettle();

      expect(started, 1);
      expect(find.text('Manage Chats'), findsNothing);
    });
  }
}
