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

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:path/path.dart' as p;

CharacterCard _mira() => CharacterCard(name: 'Mira', personality: 'tsundere');

DeskSession _session(String folder, DeskMode mode) =>
    DeskSession(folderRoot: folder, coworker: _mira(), mode: mode);

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('desk_e_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('todowrite stores items; todoread returns them', () async {
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
      const LlmToolResponse(
        calls: [LlmToolCall(name: 'todoread', arguments: {})],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'Listed.'),
    ]);
    final harness = DeskHarness(
      session: _session(root.path, DeskMode.yolo),
      llm: llm,
    );
    await harness.send('track the helper');
    expect(harness.todos.items, hasLength(1));
    expect(harness.todos.items.single.content, 'add helper');
    expect(llm.calls.last.prompt, contains('add helper'));
  });

  test('question pauses the loop until answered', () async {
    final gate = Completer<String>();
    var asked = 0;
    final llm = ScriptedDeskLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'question',
            arguments: {
              'prompt': 'Name the helper?',
              'choices': ['foo', 'bar'],
            },
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'You picked foo.'),
    ]);
    final harness = DeskHarness(
      session: _session(root.path, DeskMode.yolo),
      llm: llm,
      onQuestion: (req) async {
        asked++;
        expect(req.prompt, contains('helper'));
        expect(req.choices, contains('foo'));
        return gate.future;
      },
    );
    final done = harness.send('name it');
    for (var i = 0; i < 40 && asked == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(asked, 1);
    expect(harness.session.running, isTrue);
    gate.complete('foo');
    await done;
    expect(harness.session.transcript.last.text, contains('foo'));
  });

  test('@path is attached on the next generate', () async {
    await File(p.join(root.path, 'notes.txt')).writeAsString('secret-notes');
    final llm = ScriptedDeskLlm([
      const LlmToolResponse(calls: [], text: 'I read the notes.'),
    ]);
    final harness = DeskHarness(
      session: _session(root.path, DeskMode.yolo),
      llm: llm,
    );
    await harness.send('summarize @notes.txt');
    expect(llm.calls, isNotEmpty);
    expect(llm.calls.first.prompt, contains('secret-notes'));
    expect(llm.calls.first.prompt, contains('notes.txt'));
  });

  test('skill injects SKILL.md from .desk/skills', () async {
    final skillDir = Directory(p.join(root.path, '.desk', 'skills', 'review'));
    await skillDir.create(recursive: true);
    await File(p.join(skillDir.path, 'SKILL.md')).writeAsString('Be terse.');
    final llm = ScriptedDeskLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(name: 'skill', arguments: {'name': 'review'}),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'Loaded.'),
    ]);
    final harness = DeskHarness(
      session: _session(root.path, DeskMode.yolo),
      llm: llm,
    );
    await harness.send('use review skill');
    expect(llm.calls.last.prompt, contains('Be terse.'));
  });

  test('/init does not write AGENTS.md when Build denies', () async {
    final llm = ScriptedDeskLlm([
      const LlmToolResponse(calls: [], text: 'idle'),
    ]);
    final harness = DeskHarness(
      session: _session(root.path, DeskMode.build),
      llm: llm,
      onAsk: (req) async => DeskAskDecision.deny,
    );
    await harness.send('/init');
    expect(File(p.join(root.path, 'AGENTS.md')).existsSync(), isFalse);
  });

  test('/init writes AGENTS.md in Yolo', () async {
    final llm = ScriptedDeskLlm([
      const LlmToolResponse(calls: [], text: 'planted.'),
    ]);
    final harness = DeskHarness(
      session: _session(root.path, DeskMode.yolo),
      llm: llm,
    );
    await harness.send('/init');
    expect(await File(p.join(root.path, 'AGENTS.md')).exists(), isTrue);
    expect(
      await File(p.join(root.path, 'AGENTS.md')).readAsString(),
      contains('AGENTS.md'),
    );
  });
}
