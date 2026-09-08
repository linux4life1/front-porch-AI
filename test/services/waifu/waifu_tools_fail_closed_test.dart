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
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

void main() {
  test('resolve + can-use fail closed on unsupported or paused', () {
    expect(
      waifuResolveToolsSupported(knownUnsupported: true, paused: false),
      isFalse,
    );
    expect(
      waifuResolveToolsSupported(knownUnsupported: false, paused: true),
      isFalse,
    );
    expect(
      waifuResolveToolsSupported(knownUnsupported: false, paused: false),
      isTrue,
    );
    expect(
      waifuCanUseTools(sessionToolsSupported: true, llmToolsSupported: false),
      isFalse,
    );
    expect(
      waifuCanUseTools(sessionToolsSupported: false, llmToolsSupported: true),
      isFalse,
    );
    expect(
      waifuCanUseTools(sessionToolsSupported: true, llmToolsSupported: true),
      isTrue,
    );
  });

  test('send does not loop when session.toolsSupported is false', () async {
    final root = await Directory.systemTemp.createTemp('waifu_tools_fc_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    await File(p.join(root.path, 'notes.txt')).writeAsString('old');
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(name: 'write', arguments: {
            'path': 'hello.txt',
            'contents': 'nope',
          }),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'I wrote it.'),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Mira', personality: 'dry'),
      toolsSupported: false,
    );
    final harness = WaifuHarness(session: session, llm: llm);

    await harness.send('add hello.txt');

    expect(llm.calls, isEmpty);
    expect(File(p.join(root.path, 'hello.txt')).existsSync(), isFalse);
    expect(session.lastWrite, isNull);
    expect(session.transcript.last.isUser, isFalse);
    expect(session.transcript.last.text, kWaifuToolsUnsupported);
    expect(session.transcript.last.text.toLowerCase(), contains('cannot'));
  });

  test('two successful writes this turn fill turnWrites in order', () async {
    final root = await Directory.systemTemp.createTemp('waifu_writes_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'write',
            arguments: {'path': 'a.txt', 'contents': 'A'},
          ),
          LlmToolCall(
            name: 'write',
            arguments: {'path': 'b.txt', 'contents': 'B'},
          ),
          LlmToolCall(name: 'read', arguments: {'path': 'a.txt'}),
          LlmToolCall(name: 'read', arguments: {'path': 'b.txt'}),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'Both files are down.'),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Mira', personality: 'dry'),
      mode: WaifuMode.yolo,
    );
    await WaifuHarness(session: session, llm: llm).send('add a.txt and b.txt');

    expect(
      session.turnWrites.map((w) => w.relativePath).toList(),
      ['a.txt', 'b.txt'],
    );
    expect(session.lastWrite?.relativePath, 'b.txt');
    expect(waifuTurnReceiptHeadline(session.turnWrites), '2 files this turn');
    expect(session.turnVerifyPaths, containsAll(['a.txt', 'b.txt']));
  });

  test('send does not loop when the LLM door is toolsSupported false', () async {
    final root = await Directory.systemTemp.createTemp('waifu_tools_llm_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final llm = ScriptedWaifuLlm(
      [
        const LlmToolResponse(calls: [], text: 'I can code just fine.'),
      ],
      toolsSupported: false,
    );
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Mira', personality: 'dry'),
    );
    await WaifuHarness(session: session, llm: llm).send('fix the test');

    expect(llm.calls, isEmpty);
    expect(session.transcript.last.text, kWaifuToolsUnsupported);
    expect(
      session.transcript.any((m) => m.text.contains('I can code just fine')),
      isFalse,
    );
  });

  test('store round-trips toolsSupported false', () async {
    final dir = await Directory.systemTemp.createTemp('waifu_tools_store_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final folder = p.join(dir.path, 'Kabbage');
    final store = WaifuStore(dir.path);
    final session = WaifuSession(
      folderRoot: folder,
      coworker: CharacterCard(name: 'Iris'),
      toolsSupported: false,
    );
    await store.saveLast(session);
    final loaded = await store.loadSession(folder);
    expect(loaded, isNotNull);
    expect(loaded!.toolsSupported, isFalse);
  });
}
