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

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/ui/desk/desk_page.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('desk_loop_ui_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  DeskSession session() => DeskSession(
    folderRoot: root.path,
    coworker: CharacterCard(name: 'Mira', personality: 'tsundere'),
  );

  testWidgets('Send writes a file and the work strip shows it', (tester) async {
    final llm = ScriptedDeskLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'write',
            arguments: {'path': 'hello.txt', 'contents': 'hello'},
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'Hmph. There. hello.txt.'),
    ]);
    final s = session();
    final harness = DeskHarness(session: s, llm: llm);
    await tester.pumpWidget(
      MaterialApp(
        home: DeskPage(session: s, harness: harness),
      ),
    );

    expect(find.text('Continue'), findsNothing);
    expect(find.text('Regenerate'), findsNothing);
    expect(find.byKey(const Key('desk-send')), findsOneWidget);
    expect(find.byKey(const Key('desk-abort')), findsNothing);

    await tester.runAsync(() => harness.send('add hello.txt'));
    await tester.pump();

    await tester.runAsync(() async {
      expect(
        await File(p.join(root.path, 'hello.txt')).readAsString(),
        'hello',
      );
    });
    expect(find.byKey(const Key('desk-work-strip')), findsOneWidget);
    expect(find.textContaining('hello.txt'), findsWidgets);
    expect(find.textContaining('Hmph. There'), findsOneWidget);
    expect(find.text('bash bash'), findsNothing);
    expect(find.text('Continue'), findsNothing);
    expect(find.text('Regenerate'), findsNothing);
  });

  testWidgets('Abort is visible while the loop is running', (tester) async {
    final gate = Completer<void>();
    final llm = ScriptedDeskLlm(
      [
        const LlmToolResponse(
          calls: [
            LlmToolCall(name: 'read', arguments: {'path': 'missing.txt'}),
          ],
          text: '',
        ),
        const LlmToolResponse(calls: [], text: 'should not land'),
      ],
      beforeGenerate: (i) async {
        if (i == 1) await gate.future;
      },
    );
    final s = session();
    final harness = DeskHarness(session: s, llm: llm);
    await tester.pumpWidget(
      MaterialApp(
        home: DeskPage(session: s, harness: harness),
      ),
    );

    late Future<void> done;
    try {
      await tester.runAsync(() async {
        done = harness.send('look around');
        for (var i = 0; i < 40 && llm.waitingAt != 1; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump();
      expect(find.byKey(const Key('desk-abort')), findsOneWidget);
      expect(find.byKey(const Key('desk-send')), findsNothing);

      await tester.tap(find.byKey(const Key('desk-abort')));
      await tester.pump();
    } finally {
      if (!gate.isCompleted) gate.complete();
    }
    await tester.runAsync(() => done);
    await tester.pump();

    expect(find.text('should not land'), findsNothing);
    expect(find.byKey(const Key('desk-send')), findsOneWidget);
  });
}
