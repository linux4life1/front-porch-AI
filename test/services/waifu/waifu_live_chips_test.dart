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
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

CharacterCard _mira() => CharacterCard(name: 'Mira', personality: 'tsundere');

WaifuSession _session(String folder, WaifuMode mode) =>
    WaifuSession(folderRoot: folder, coworker: _mira(), mode: mode);

List<WaifuToolChip> _copyChips(WaifuSession session) => [
  for (final c in session.toolChips)
    WaifuToolChip(name: c.name, detail: c.detail, ok: c.ok, running: c.running),
];

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('waifu_live_chips_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('tool attempt emits a running chip before the ask returns', () async {
    final gate = Completer<WaifuAskDecision>();
    final session = _session(root.path, WaifuMode.build);
    var asked = 0;
    List<WaifuToolChip>? duringAsk;
    final llm = ScriptedWaifuLlm([
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
      const LlmToolResponse(calls: [], text: 'Tracked the helper.'),
    ]);
    final harness = WaifuHarness(
      session: session,
      llm: llm,
      onAsk: (req) async {
        asked++;
        duringAsk = _copyChips(session);
        return gate.future;
      },
    );
    final done = harness.send('track the helper');
    for (var i = 0; i < 40 && asked == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(asked, 1);
    expect(duringAsk, isNotNull);
    expect(duringAsk, hasLength(1));
    expect(duringAsk!.single.name, kWaifuToolTodoWrite);
    expect(duringAsk!.single.running, isTrue);
    expect(session.running, isTrue);

    gate.complete(WaifuAskDecision.allowOnce);
    await done;

    expect(session.toolChips, hasLength(1));
    expect(session.toolChips.single.name, kWaifuToolTodoWrite);
    expect(session.toolChips.single.running, isFalse);
    expect(session.toolChips.single.ok, isTrue);
  });

  test(
    'denied tool flips the running chip to fail, not a second row',
    () async {
      final session = _session(root.path, WaifuMode.build);
      final snaps = <List<WaifuToolChip>>[];
      final llm = ScriptedWaifuLlm([
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
        const LlmToolResponse(calls: [], text: 'They said no.'),
      ]);
      final harness = WaifuHarness(
        session: session,
        llm: llm,
        onChanged: () => snaps.add(_copyChips(session)),
        onAsk: (req) async => WaifuAskDecision.deny,
      );
      await harness.send('track the helper');

      expect(snaps.any((s) => s.any((c) => c.running)), isTrue);
      expect(session.toolChips, hasLength(1));
      expect(session.toolChips.single.name, kWaifuToolTodoWrite);
      expect(session.toolChips.single.running, isFalse);
      expect(session.toolChips.single.ok, isFalse);
    },
  );

  test(
    'spoken todo-done without a completed write gets a harness chip',
    () async {
      final session = _session(root.path, WaifuMode.yolo);
      final llm = ScriptedWaifuLlm([
        const LlmToolResponse(
          calls: [],
          text: 'I marked the first todo completed via todowrite.',
        ),
      ]);
      final harness = WaifuHarness(session: session, llm: llm);
      await harness.send('list the files');

      expect(
        session.toolChips.any(
          (c) =>
              c.name == kWaifuToolTodoWrite &&
              c.ok == false &&
              c.detail.contains('claimed without a completed write'),
        ),
        isTrue,
      );
    },
  );

  test(
    'successful completed todowrite does not scold a matching claim',
    () async {
      final session = _session(root.path, WaifuMode.yolo);
      final llm = ScriptedWaifuLlm([
        const LlmToolResponse(
          calls: [
            LlmToolCall(
              name: 'todowrite',
              arguments: {
                'todos': [
                  {'id': '1', 'content': 'add helper', 'status': 'completed'},
                ],
              },
            ),
          ],
          text: '',
        ),
        const LlmToolResponse(
          calls: [],
          text: 'I marked the first todo completed via todowrite.',
        ),
      ]);
      final harness = WaifuHarness(session: session, llm: llm);
      await harness.send('finish the first todo');
      expect(harness.todos.items.single.status, kWaifuTodoCompleted);
      expect(
        session.toolChips.where(
          (c) => c.detail.contains('claimed without a completed write'),
        ),
        isEmpty,
      );
      expect(session.toolChips.single.name, kWaifuToolTodoWrite);
      expect(session.toolChips.single.ok, isTrue);
    },
  );
}
