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

LlmToolResponse _write(String path, String contents) => LlmToolResponse(
  calls: [
    LlmToolCall(name: 'write', arguments: {'path': path, 'contents': contents}),
  ],
  text: '',
);

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('desk_perm_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  DeskSession session(DeskMode mode) =>
      DeskSession(folderRoot: root.path, coworker: _mira(), mode: mode);

  test('Plan write does not touch disk and does not ask', () async {
    var asked = 0;
    final llm = ScriptedDeskLlm([
      _write('hello.txt', 'nope'),
      const LlmToolResponse(calls: [], text: 'Plan only. I did not write.'),
    ]);
    final harness = DeskHarness(
      session: session(DeskMode.plan),
      llm: llm,
      onAsk: (req) async {
        asked++;
        return DeskAskDecision.allowOnce;
      },
    );
    await harness.send('add hello.txt');
    expect(File(p.join(root.path, 'hello.txt')).existsSync(), isFalse);
    expect(asked, 0);
    expect(harness.session.transcript.last.text, contains('did not write'));
  });

  test('Build write waits; Deny leaves the file absent', () async {
    final gate = Completer<DeskAskDecision>();
    var asked = 0;
    final llm = ScriptedDeskLlm([
      _write('hello.txt', 'secret'),
      const LlmToolResponse(calls: [], text: 'You would not let me.'),
    ]);
    final harness = DeskHarness(
      session: session(DeskMode.build),
      llm: llm,
      onAsk: (req) async {
        asked++;
        return gate.future;
      },
    );
    final done = harness.send('add hello.txt');
    for (var i = 0; i < 40 && asked == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(asked, 1);
    expect(File(p.join(root.path, 'hello.txt')).existsSync(), isFalse);
    gate.complete(DeskAskDecision.deny);
    await done;
    expect(File(p.join(root.path, 'hello.txt')).existsSync(), isFalse);
    expect(harness.session.transcript.last.text, contains('would not let me'));
  });

  test('Build Allow once writes the file', () async {
    final llm = ScriptedDeskLlm([
      _write('hello.txt', 'ok'),
      const LlmToolResponse(calls: [], text: 'Wrote it.'),
    ]);
    final harness = DeskHarness(
      session: session(DeskMode.build),
      llm: llm,
      onAsk: (req) async => DeskAskDecision.allowOnce,
    );
    await harness.send('add hello.txt');
    expect(await File(p.join(root.path, 'hello.txt')).readAsString(), 'ok');
  });

  test('Yolo write does not ask', () async {
    var asked = 0;
    final llm = ScriptedDeskLlm([
      _write('hello.txt', 'yolo'),
      const LlmToolResponse(calls: [], text: 'Done.'),
    ]);
    final harness = DeskHarness(
      session: session(DeskMode.yolo),
      llm: llm,
      onAsk: (req) async {
        asked++;
        return DeskAskDecision.deny;
      },
    );
    await harness.send('add hello.txt');
    expect(asked, 0);
    expect(await File(p.join(root.path, 'hello.txt')).readAsString(), 'yolo');
  });

  test('Yolo still refuses git checkout --', () async {
    final llm = ScriptedDeskLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'bash',
            arguments: {'command': 'git checkout -- .'},
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'That command is denied.'),
    ]);
    final harness = DeskHarness(session: session(DeskMode.yolo), llm: llm);
    await harness.send('reset the repo');
    final chips = harness.session.transcript.last.chips;
    expect(chips, isNotEmpty);
    expect(chips.single.ok, isFalse);
    expect(chips.single.detail.toLowerCase(), contains('denied'));
  });

  test('.env read and write are denied even in Yolo', () async {
    await File(p.join(root.path, '.env')).writeAsString('SECRET=1');
    final llm = ScriptedDeskLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(name: 'read', arguments: {'path': '.env'}),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'I cannot open that.'),
    ]);
    final harness = DeskHarness(session: session(DeskMode.yolo), llm: llm);
    await harness.send('read env');
    expect(
      harness.session.transcript.last.chips.single.detail,
      isNot(contains('SECRET')),
    );
    expect(harness.session.transcript.last.chips.single.ok, isFalse);
  });

  test('doom-loop: third identical Yolo write asks', () async {
    var asked = 0;
    final llm = ScriptedDeskLlm([
      _write('a.txt', '1'),
      _write('a.txt', '1'),
      _write('a.txt', '1'),
      const LlmToolResponse(calls: [], text: 'Stopped repeating.'),
    ]);
    final harness = DeskHarness(
      session: session(DeskMode.yolo),
      llm: llm,
      onAsk: (req) async {
        asked++;
        expect(req.doomLoop, isTrue);
        return DeskAskDecision.deny;
      },
    );
    await harness.send('write three times');
    expect(asked, 1);
  });
}
