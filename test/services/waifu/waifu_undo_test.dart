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

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('waifu_undo_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('undo restores her write; redo reapplies; user files stay', () async {
    await File(p.join(root.path, 'mine.txt')).writeAsString('user');
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'write',
            arguments: {'path': 'foo.txt', 'contents': 'from her'},
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'Hmph. Your foo file is on disk.'),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Mira', personality: 'tsundere'),
      mode: WaifuMode.yolo,
    );
    final harness = WaifuHarness(session: session, llm: llm);
    await harness.send('write foo');

    expect(await File(p.join(root.path, 'foo.txt')).readAsString(), 'from her');
    expect(harness.canUndo, isTrue);
    expect(harness.canRedo, isFalse);

    await harness.undo();
    expect(File(p.join(root.path, 'foo.txt')).existsSync(), isFalse);
    expect(await File(p.join(root.path, 'mine.txt')).readAsString(), 'user');
    expect(harness.canUndo, isFalse);
    expect(harness.canRedo, isTrue);

    await harness.redo();
    expect(await File(p.join(root.path, 'foo.txt')).readAsString(), 'from her');
    expect(await File(p.join(root.path, 'mine.txt')).readAsString(), 'user');
  });
}
