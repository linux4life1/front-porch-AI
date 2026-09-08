// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu.dart';

void main() {
  testWidgets('todo list uses marks, not a status: content dump', (
    tester,
  ) async {
    final todos = WaifuTodos()
      ..write([
        {'id': '1', 'content': 'Debug the particle', 'status': 'in_progress'},
        {'id': '2', 'content': 'Write the note', 'status': 'pending'},
        {'id': '3', 'content': 'Ship the porch', 'status': 'completed'},
      ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WaifuTodoList(todos: todos)),
      ),
    );

    expect(find.byKey(const Key('waifu-todos')), findsOneWidget);
    expect(find.text('Debug the particle'), findsOneWidget);
    expect(find.text('Write the note'), findsOneWidget);
    expect(find.text('Ship the porch'), findsOneWidget);
    expect(find.textContaining('in_progress:'), findsNothing);
    expect(find.textContaining('pending:'), findsNothing);
    expect(find.textContaining('completed:'), findsNothing);
    expect(find.text('in_progress: Debug the particle'), findsNothing);

    expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
    expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
    expect(find.byIcon(Icons.check_box), findsOneWidget);

    final done = tester.widget<Text>(find.text('Ship the porch'));
    expect(done.style?.decoration, TextDecoration.lineThrough);
    final doing = tester.widget<Text>(find.text('Debug the particle'));
    expect(doing.style?.decoration, isNot(TextDecoration.lineThrough));
    expect(doing.style?.fontWeight, FontWeight.w600);
  });

  testWidgets('empty todo list stays hidden', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WaifuTodoList(todos: WaifuTodos())),
      ),
    );
    expect(find.byKey(const Key('waifu-todos')), findsNothing);
  });
}
