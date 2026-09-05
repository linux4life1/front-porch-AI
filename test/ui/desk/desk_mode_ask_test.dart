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
import 'package:front_porch_ai/ui/desk/desk_ask_dialog.dart';
import 'package:front_porch_ai/ui/desk/desk_page.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('desk_mode_ui_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  testWidgets('session chrome shows Plan Build Yolo; no Continue or Regen', (
    tester,
  ) async {
    final session = DeskSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Mira', personality: 'tsundere'),
    );
    final llm = ScriptedDeskLlm([
      const LlmToolResponse(calls: [], text: 'idle'),
    ]);
    final harness = DeskHarness(session: session, llm: llm);
    await tester.pumpWidget(
      MaterialApp(
        home: DeskPage(session: session, harness: harness),
      ),
    );

    expect(find.byKey(const Key('desk-mode-plan')), findsOneWidget);
    expect(find.byKey(const Key('desk-mode-build')), findsOneWidget);
    expect(find.byKey(const Key('desk-mode-yolo')), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
    expect(find.text('Regenerate'), findsNothing);

    await tester.tap(find.byKey(const Key('desk-mode-yolo')));
    await tester.pump();
    expect(session.mode, DeskMode.yolo);
    expect(find.textContaining('folder jail still holds'), findsOneWidget);
  });

  testWidgets('ask dialog Deny / Allow once / Always are present', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DeskAskDialog(
          request: DeskAskRequest(toolName: 'write', summary: 'hello.txt'),
        ),
      ),
    );
    expect(find.byKey(const Key('desk-ask-deny')), findsOneWidget);
    expect(find.byKey(const Key('desk-ask-once')), findsOneWidget);
    expect(find.byKey(const Key('desk-ask-always')), findsOneWidget);

    await tester.tap(find.byKey(const Key('desk-ask-deny')));
    await tester.pump();
  });
}
