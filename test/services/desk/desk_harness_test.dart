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

CharacterCard _mira() => CharacterCard(
  name: 'Mira',
  personality: 'tsundere, dry, teases then does the work anyway',
  scenario: 'SCENARIO_MUST_NOT_APPEAR — a rainy porch date',
);

DeskSession _session(String folder) =>
    DeskSession(folderRoot: folder, coworker: _mira());

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('desk_harness_');
    await File(p.join(root.path, 'notes.txt')).writeAsString('old notes');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'read-then-stop: two generates, one read, then her final text',
    () async {
      final llm = ScriptedDeskLlm([
        const LlmToolResponse(
          calls: [
            LlmToolCall(name: 'read', arguments: {'path': 'notes.txt'}),
          ],
          text: '',
        ),
        const LlmToolResponse(calls: [], text: 'Hmph. I read it. Fine.'),
      ]);
      final session = _session(root.path);
      final harness = DeskHarness(session: session, llm: llm);

      await harness.send('read the notes');

      expect(llm.calls, hasLength(2));
      expect(session.transcript.where((m) => m.isUser), hasLength(1));
      expect(session.transcript.last.isUser, isFalse);
      expect(session.transcript.last.text, contains('Hmph. I read it'));
      expect(session.transcript.last.chips, isNotEmpty);
      expect(session.transcript.last.chips.single.name, 'read');
    },
  );

  test('personality preamble is on every generate; scenario is not', () async {
    final llm = ScriptedDeskLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(name: 'read', arguments: {'path': 'notes.txt'}),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'done'),
    ]);
    final harness = DeskHarness(session: _session(root.path), llm: llm);
    await harness.send('look');

    expect(llm.calls, hasLength(2));
    for (final turn in llm.calls) {
      expect(turn.systemPrompt, contains(kDeskPreamble));
      expect(turn.systemPrompt, contains('tsundere'));
      expect(turn.systemPrompt, isNot(contains('SCENARIO_MUST_NOT_APPEAR')));
      expect(turn.tools, isNotEmpty);
    }
  });

  test('write records before-bytes on the work strip', () async {
    final llm = ScriptedDeskLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'write',
            arguments: {'path': 'notes.txt', 'contents': 'new notes'},
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'Wrote it. You are welcome.'),
    ]);
    final session = _session(root.path);
    final harness = DeskHarness(session: session, llm: llm);
    await harness.send('rewrite notes');

    expect(session.lastWrite, isNotNull);
    expect(session.lastWrite!.relativePath, 'notes.txt');
    expect(session.lastWrite!.before, 'old notes');
    expect(session.lastWrite!.after, 'new notes');
    expect(
      await File(p.join(root.path, 'notes.txt')).readAsString(),
      'new notes',
    );
  });

  test('max 20 steps then stop; no 21st generate', () async {
    final llm = ScriptedDeskLlm.repeat(
      const LlmToolResponse(
        calls: [
          LlmToolCall(name: 'read', arguments: {'path': 'notes.txt'}),
        ],
        text: '',
      ),
    );
    final session = _session(root.path);
    final harness = DeskHarness(session: session, llm: llm);
    await harness.send('loop forever');

    expect(llm.calls, hasLength(kDeskMaxSteps));
    expect(session.transcript.last.isUser, isFalse);
    expect(session.transcript.last.text.toLowerCase(), contains('step'));
  });

  test('abort stops further generates and does not roll back disk', () async {
    final gate = Completer<void>();
    final llm = ScriptedDeskLlm(
      [
        const LlmToolResponse(
          calls: [
            LlmToolCall(
              name: 'write',
              arguments: {'path': 'notes.txt', 'contents': 'from first tool'},
            ),
          ],
          text: '',
        ),
        const LlmToolResponse(calls: [], text: 'should not land'),
      ],
      beforeGenerate: (i) async {
        if (i == 1) await gate.future;
      },
    );
    final session = _session(root.path);
    final harness = DeskHarness(session: session, llm: llm);
    final done = harness.send('write then more');
    try {
      await pumpUntil(() => llm.waitingAt == 1);
      harness.abort();
    } finally {
      if (!gate.isCompleted) gate.complete();
    }
    await done;

    expect(llm.calls.length, 1);
    expect(
      session.transcript.any((m) => m.text.contains('should not land')),
      isFalse,
    );
    expect(
      await File(p.join(root.path, 'notes.txt')).readAsString(),
      'from first tool',
    );
  });

  test('null generateWithTools does not invent a patch', () async {
    final llm = ScriptedDeskLlm.unsupported();
    final session = _session(root.path);
    final harness = DeskHarness(session: session, llm: llm);
    await harness.send('add hello.txt');

    expect(File(p.join(root.path, 'hello.txt')).existsSync(), isFalse);
    expect(session.lastWrite, isNull);
    expect(session.transcript.last.isUser, isFalse);
    expect(session.transcript.last.text.toLowerCase(), contains('cannot'));
  });
}

Future<void> pumpUntil(bool Function() ok, {int tries = 40}) async {
  for (var i = 0; i < tries; i++) {
    if (ok()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('condition never became true');
}
