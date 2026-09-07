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
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:path/path.dart' as p;

CharacterCard _mira() => CharacterCard(name: 'Mira', personality: 'tsundere');

Set<String> _toolNames(List<Map<String, dynamic>> tools) => {
  for (final t in tools) ((t['function'] as Map?)?['name'] ?? '').toString(),
};

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('waifu_h_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('nested Explore cannot write', () async {
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'task',
            arguments: {'subagent': 'explore', 'prompt': 'find auth'},
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'write',
            arguments: {'path': 'hack.txt', 'contents': 'nope'},
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(
        calls: [],
        text: 'Explore: auth is in lib/auth.dart',
      ),
      const LlmToolResponse(calls: [], text: 'Hmph. Explore finished.'),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: _mira(),
      mode: WaifuMode.yolo,
    );
    final harness = WaifuHarness(session: session, llm: llm);
    await harness.send('have explore find the auth entrypoint');

    expect(File(p.join(root.path, 'hack.txt')).existsSync(), isFalse);
    expect(llm.calls, hasLength(4));
    final childTools = _toolNames(llm.calls[1].tools);
    expect(childTools, isNot(contains(kWaifuToolWrite)));
    expect(childTools, isNot(contains(kWaifuToolTask)));
    expect(childTools, contains(kWaifuToolRead));
    expect(session.toolChips.any((c) => c.name == kWaifuToolTask), isTrue);
  });

  test('child cannot read outside the jail root', () async {
    final outside = File(p.join(p.dirname(root.path), 'secret_h.txt'))
      ..writeAsStringSync('SECRET');
    addTearDown(() {
      if (outside.existsSync()) outside.deleteSync();
    });
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'task',
            arguments: {
              'subagent': 'explore',
              'prompt': 'read the secret next door',
            },
          ),
        ],
        text: '',
      ),
      LlmToolResponse(
        calls: [
          LlmToolCall(name: 'read', arguments: {'path': '../secret_h.txt'}),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'Could not leave the folder.'),
      const LlmToolResponse(calls: [], text: 'Hmph. Stayed put.'),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: _mira(),
      mode: WaifuMode.yolo,
    );
    await WaifuHarness(session: session, llm: llm).send('explore outside');
    final spoken = session.transcript.map((m) => m.text).join('\n');
    expect(spoken, isNot(contains('SECRET')));
    expect(
      llm.calls.map((c) => c.prompt).join('\n'),
      isNot(contains('SECRET')),
    );
  });

  test('general nested write stays in the jail', () async {
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'task',
            arguments: {'subagent': 'general', 'prompt': 'add hello.txt'},
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'write',
            arguments: {'path': 'hello.txt', 'contents': 'hi'},
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'write',
            arguments: {'path': '../escape.txt', 'contents': 'out'},
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'Wrote hello.txt'),
      const LlmToolResponse(calls: [], text: 'Hmph. General done.'),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: _mira(),
      mode: WaifuMode.yolo,
    );
    await WaifuHarness(
      session: session,
      llm: llm,
    ).send('write hello via general');
    expect(await File(p.join(root.path, 'hello.txt')).readAsString(), 'hi');
    expect(
      File(p.join(p.dirname(root.path), 'escape.txt')).existsSync(),
      isFalse,
    );
  });
}
