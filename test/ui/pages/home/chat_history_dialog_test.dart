// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Focused widget test of the extracted Chat History dialog — rows, trash
// confirm, empty copy. Does not launch the full app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/pages/home/dialogs/chat_history_dialog.dart';

Widget _app(Widget child) => MaterialApp(home: child);

Map<String, dynamic> _session({
  required String id,
  required String preview,
  DateTime? date,
}) => {
  'id': id,
  'preview': preview,
  'date': date ?? DateTime(2026, 8, 21, 14, 5),
};

void main() {
  testWidgets('shows session rows', (tester) async {
    await tester.pumpWidget(
      _app(
        ChatHistoryDialog(
          initialSessions: [
            _session(id: 's1', preview: 'Adventure in the forest'),
            _session(id: 's2', preview: 'Coffee on the porch'),
          ],
          loadSessions: () async => const [],
          onOpen: (_) async {},
          onDelete: (_) async {},
          onSaveMeta: (_, _, _) async {},
        ),
      ),
    );

    expect(find.text('Chat History'), findsOneWidget);
    expect(find.text('Adventure in the forest'), findsOneWidget);
    expect(find.text('Coffee on the porch'), findsOneWidget);
    expect(find.text('No previous chats found.'), findsNothing);
  });

  testWidgets('trash opens Delete Chat?', (tester) async {
    await tester.pumpWidget(
      _app(
        ChatHistoryDialog(
          initialSessions: [_session(id: 's1', preview: 'Doomed chat')],
          loadSessions: () async => const [],
          onOpen: (_) async {},
          onDelete: (_) async {},
          onSaveMeta: (_, _, _) async {},
        ),
      ),
    );

    await tester.tap(find.byTooltip('Delete chat'));
    await tester.pumpAndSettle();

    expect(find.text('Delete Chat?'), findsOneWidget);
    expect(find.textContaining('Doomed chat'), findsWidgets);
  });

  testWidgets('empty state copy', (tester) async {
    await tester.pumpWidget(
      _app(
        ChatHistoryDialog(
          initialSessions: const [],
          loadSessions: () async => const [],
          onOpen: (_) async {},
          onDelete: (_) async {},
          onSaveMeta: (_, _, _) async {},
        ),
      ),
    );

    expect(find.text('No previous chats found.'), findsOneWidget);
    expect(find.byTooltip('Delete chat'), findsNothing);
  });
}
