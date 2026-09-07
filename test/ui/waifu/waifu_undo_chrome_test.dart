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
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('waifu_undo_ui_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  testWidgets('Undo and Redo keys exist; Continue and Regen do not', (
    tester,
  ) async {
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Mira', personality: 'tsundere'),
      mode: WaifuMode.yolo,
    );
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'write',
            arguments: {'path': 'foo.txt', 'contents': 'x'},
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'Hmph. Your file is written.'),
    ]);
    final harness = WaifuHarness(session: session, llm: llm);
    await tester.pumpWidget(
      MaterialApp(
        home: WaifuPage(session: session, harness: harness),
      ),
    );

    expect(find.byKey(const Key('waifu-undo')), findsOneWidget);
    expect(find.byKey(const Key('waifu-redo')), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
    expect(find.text('Regenerate'), findsNothing);

    await tester.runAsync(() => harness.send('write foo'));
    await tester.pump();
    expect(
      tester.widget<IconButton>(find.byKey(const Key('waifu-undo'))).onPressed,
      isNotNull,
    );

    await tester.runAsync(() => harness.undo());
    await tester.pump();
    expect(
      tester.widget<IconButton>(find.byKey(const Key('waifu-redo'))).onPressed,
      isNotNull,
    );
  });
}
