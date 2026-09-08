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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu.dart';

void main() {
  testWidgets('completed todos are struck through and dim', (tester) async {
    final todos = WaifuTodos()
      ..write([
        {'id': '1', 'content': 'add helper', 'status': 'completed'},
        {'id': '2', 'content': 'next step', 'status': 'in_progress'},
      ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WaifuTodoList(todos: todos)),
      ),
    );
    expect(find.byKey(const Key('waifu-todos')), findsOneWidget);
    expect(find.text('completed: add helper'), findsOneWidget);
    expect(find.text('in_progress: next step'), findsOneWidget);

    final done = tester.widget<Text>(find.byKey(const Key('waifu-todo-1')));
    expect(done.style?.decoration, TextDecoration.lineThrough);
    final live = tester.widget<Text>(find.byKey(const Key('waifu-todo-2')));
    expect(live.style?.decoration, TextDecoration.none);
  });
}
