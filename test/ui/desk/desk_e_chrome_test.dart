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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/ui/desk/desk_page.dart';
import 'package:front_porch_ai/ui/desk/desk_question_dialog.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('desk_e_ui_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  testWidgets('todo list appears after todowrite; no Continue', (tester) async {
    final session = DeskSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Mira', personality: 'tsundere'),
      mode: DeskMode.yolo,
    );
    final llm = ScriptedDeskLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'todowrite',
            arguments: {
              'todos': [
                {'id': '1', 'content': 'add helper', 'status': 'pending'},
              ],
            },
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'Tracked.'),
    ]);
    final harness = DeskHarness(session: session, llm: llm);
    await tester.pumpWidget(
      MaterialApp(
        home: DeskPage(session: session, harness: harness),
      ),
    );
    expect(find.text('Continue'), findsNothing);
    expect(find.text('Regenerate'), findsNothing);

    await tester.runAsync(() => harness.send('track it'));
    await tester.pump();
    expect(find.byKey(const Key('desk-todos')), findsOneWidget);
    expect(find.textContaining('add helper'), findsOneWidget);
  });

  testWidgets('question dialog has choice keys', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DeskQuestionDialog(
          request: DeskQuestionRequest(
            prompt: 'Name the helper?',
            choices: ['foo', 'bar'],
          ),
        ),
      ),
    );
    expect(find.text('Name the helper?'), findsOneWidget);
    expect(find.byKey(const Key('desk-question-foo')), findsOneWidget);
    await tester.tap(find.byKey(const Key('desk-question-foo')));
    await tester.pump();
  });
}
