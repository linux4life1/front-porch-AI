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
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

CharacterCard _mira() => CharacterCard(
  name: 'Mira',
  personality: 'tsundere, dry, teases then does the work anyway',
  scenario: 'SCENARIO_MUST_NOT_APPEAR — a rainy porch date',
);

WaifuSession _session(String folder) =>
    WaifuSession(folderRoot: folder, coworker: _mira());

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('waifu_harness_');
    await File(p.join(root.path, 'notes.txt')).writeAsString('old notes');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'read-then-stop: two generates, one read, then her final text',
    () async {
      final llm = ScriptedWaifuLlm([
        const LlmToolResponse(
          calls: [
            LlmToolCall(name: 'read', arguments: {'path': 'notes.txt'}),
          ],
          text: '',
        ),
        const LlmToolResponse(calls: [], text: 'Hmph. I read it. Fine.'),
      ]);
      final session = _session(root.path);
      final harness = WaifuHarness(session: session, llm: llm);

      await harness.send('read the notes');

      expect(llm.calls, hasLength(2));
      expect(session.transcript.where((m) => m.isUser), hasLength(1));
      final spoken = session.transcript.where((m) => !m.isUser).toList();
      expect(spoken, hasLength(1));
      expect(spoken.single.chips.single.name, 'read');
      expect(spoken.single.chips.single.detail, 'notes.txt');
      expect(spoken.single.text, contains('Hmph. I read it'));
    },
  );

  test(
    'bash chip names the command; reasoning is kept off the spoken line',
    () async {
      final llm = ScriptedWaifuLlm([
        const LlmToolResponse(
          calls: [
            LlmToolCall(name: 'bash', arguments: {'command': 'ls -la'}),
          ],
          text: '<think>I should list the folder</think>',
          reasoning: 'look around first',
        ),
        const LlmToolResponse(calls: [], text: 'Hmph. Empty. Typical.'),
      ]);
      final session = _session(root.path);
      final harness = WaifuHarness(session: session, llm: llm);
      await harness.send('what is here');
      final spoken = session.transcript.where((m) => !m.isUser).toList();
      expect(spoken, hasLength(1));
      expect(spoken.single.chips.single.name, 'bash');
      expect(spoken.single.chips.single.detail, 'ls -la');
      expect(spoken.single.reasoning, contains('look around first'));
      expect(spoken.single.text, 'Hmph. Empty. Typical.');
      expect(spoken.single.text, isNot(contains('<think>')));
    },
  );

  test(
    'think tokens land on the live bubble before generate returns',
    () async {
      late WaifuSession session;
      session = _session(root.path);
      final llm = ScriptedWaifuLlm(
        const [LlmToolResponse(calls: [], text: 'Hmph. Done.')],
        streamDuring: (i, onChunk) async {
          onChunk('<think>counting the files');
          expect(
            session.transcript.last.reasoning,
            contains('counting the files'),
          );
          onChunk('</think>\nHmph. Done.');
        },
      );
      final harness = WaifuHarness(session: session, llm: llm);
      await harness.send('look');
      expect(session.transcript.last.reasoning, contains('counting the files'));
      expect(session.transcript.last.text, 'Hmph. Done.');
    },
  );

  test('personality preamble is on every generate; scenario is not', () async {
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(name: 'read', arguments: {'path': 'notes.txt'}),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'Hmph. I found your notes.'),
    ]);
    final harness = WaifuHarness(session: _session(root.path), llm: llm);
    await harness.send('look');

    expect(llm.calls, hasLength(2));
    for (final turn in llm.calls) {
      expect(turn.systemPrompt, contains(kWaifuPreamble));
      expect(turn.systemPrompt, contains('tsundere'));
      expect(turn.systemPrompt, isNot(contains('SCENARIO_MUST_NOT_APPEAR')));
      expect(turn.tools, isNotEmpty);
    }
  });

  test('write records before-bytes on the work strip', () async {
    final llm = ScriptedWaifuLlm([
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
    final harness = WaifuHarness(session: session, llm: llm);
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

  test('max steps then stop; no extra generate', () async {
    final llm = ScriptedWaifuLlm.repeat(
      const LlmToolResponse(
        calls: [
          LlmToolCall(name: 'read', arguments: {'path': 'notes.txt'}),
        ],
        text: '',
      ),
    );
    final session = _session(root.path);
    final harness = WaifuHarness(session: session, llm: llm);
    await harness.send('loop forever');

    expect(llm.calls, hasLength(kWaifuMaxSteps));
    expect(session.transcript.last.isUser, isFalse);
    expect(session.transcript.last.text, isNotEmpty);
    expect(session.transcript.last.text, isNot(contains('Stopped after')));
    expect(session.transcript.last.chips.last.ok, isFalse);
    expect(session.transcript.last.chips.last.detail, contains('runaway fuse'));
  });

  test('abort stops further generates and does not roll back disk', () async {
    final gate = Completer<void>();
    final llm = ScriptedWaifuLlm(
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
    final harness = WaifuHarness(session: session, llm: llm);
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
    final llm = ScriptedWaifuLlm.unsupported();
    final session = _session(root.path);
    final harness = WaifuHarness(session: session, llm: llm);
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
