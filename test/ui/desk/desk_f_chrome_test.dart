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

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('desk_f_ui_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  testWidgets('MCP opt-in warns that the jail does not apply', (tester) async {
    final session = DeskSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Mira', personality: 'tsundere'),
    );
    final harness = DeskHarness(
      session: session,
      llm: ScriptedDeskLlm([const LlmToolResponse(calls: [], text: 'idle')]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DeskPage(session: session, harness: harness),
      ),
    );
    expect(find.byKey(const Key('desk-mcp-opt-in')), findsOneWidget);
    expect(find.textContaining('jail does not apply'), findsNothing);

    await tester.tap(find.byKey(const Key('desk-mcp-opt-in')));
    await tester.pump();
    expect(harness.mcpOptIn, isTrue);
    expect(find.textContaining('jail does not apply'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
  });
}
