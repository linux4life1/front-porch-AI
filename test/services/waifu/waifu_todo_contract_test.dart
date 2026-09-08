// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('waifu_todo_contract_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  CharacterCard iris() =>
      CharacterCard(name: 'Iris', personality: 'proud, sharp, and teasing');

  test('todo-receipt detector wants a real todo claim, not generic done', () {
    expect(waifuLooksTodoReceiptClaim('I marked the todo completed.'), isTrue);
    expect(waifuLooksTodoReceiptClaim('Hmph. I ran todowrite.'), isTrue);
    expect(waifuLooksTodoReceiptClaim('I updated the todo list.'), isTrue);
    expect(waifuLooksTodoReceiptClaim('Hmph. Consider it fixed.'), isFalse);
    expect(waifuLooksTodoReceiptClaim('I completed the login page.'), isFalse);
    expect(waifuLooksTodoReceiptClaim('Done.'), isFalse);
  });

  test('decideFinal: todo claim without a todowrite chip is a soft fail', () {
    final turn = WaifuTurnContract.start('track the work', null);
    const claim = 'Hmph. I marked the todo completed.';
    expect(turn.decideFinal(claim), WaifuFinalAction.retryTodoWrite);
    turn.requestTodoWrite();
    expect(turn.decideFinal(claim), WaifuFinalAction.retryTodoWrite);
    turn.requestTodoWrite();
    expect(turn.decideFinal(claim), WaifuFinalAction.failTodoWrite);
    expect(turn.failureLine(claim), contains('did not actually update'));
  });

  test('decideFinal: todo claim with a successful todowrite chip passes', () {
    final turn = WaifuTurnContract.start('track the work', null);
    expect(
      turn.decideFinal(
        'Hmph. I marked the todo completed.',
        chips: const [
          WaifuToolChip(name: kWaifuToolTodoWrite, detail: '1 item', ok: true),
        ],
      ),
      WaifuFinalAction.accept,
    );
  });

  test('failed or pending todowrite chips are not receipts', () {
    final turn = WaifuTurnContract.start('track the work', null);
    const claim = 'Hmph. I marked the todo completed.';
    expect(
      turn.decideFinal(
        claim,
        chips: const [
          WaifuToolChip(
            name: kWaifuToolTodoWrite,
            detail: 'stopped',
            ok: false,
            pending: true,
          ),
        ],
      ),
      WaifuFinalAction.retryTodoWrite,
    );
    expect(
      turn.decideFinal(
        claim,
        chips: const [
          WaifuToolChip(name: kWaifuToolTodoWrite, detail: 'denied', ok: false),
        ],
      ),
      WaifuFinalAction.retryTodoWrite,
    );
  });

  test(
    'spoken todo-complete claim without todowrite is a red failure',
    () async {
      final llm = ScriptedWaifuLlm([
        for (var i = 0; i < 3; i++)
          const LlmToolResponse(
            calls: [],
            text: 'Hmph. I marked the todo completed.',
          ),
      ]);
      final session = WaifuSession(
        folderRoot: root.path,
        coworker: iris(),
        mode: WaifuMode.yolo,
      );
      final harness = WaifuHarness(session: session, llm: llm);

      await harness.send('track the work');

      expect(harness.todos.items, isEmpty);
      final reply = session.transcript.where((m) => !m.isUser).single;
      expect(reply.chips.last.ok, isFalse);
      expect(reply.chips.last.detail, contains('no todowrite receipt'));
      expect(reply.text, contains('did not actually update the todo list'));
      expect(reply.text, isNot(contains('marked the todo completed')));
      expect(
        llm.calls.skip(1).every((c) => c.prompt.contains('todowrite')),
        isTrue,
      );
    },
  );

  test(
    'spoken todo-complete claim with a successful todowrite chip passes',
    () async {
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
          text: 'Hmph. I marked the todo completed.',
        ),
      ]);
      final session = WaifuSession(
        folderRoot: root.path,
        coworker: iris(),
        mode: WaifuMode.yolo,
      );
      final harness = WaifuHarness(session: session, llm: llm);

      await harness.send('track the work');

      expect(harness.todos.items, hasLength(1));
      expect(harness.todos.items.single.status, 'completed');
      final reply = session.transcript.where((m) => !m.isUser).single;
      expect(
        reply.chips.any((c) => c.name == kWaifuToolTodoWrite && c.ok),
        isTrue,
      );
      expect(
        reply.chips.any((c) => c.detail.contains('no todowrite')),
        isFalse,
      );
      expect(reply.text, 'Hmph. I marked the todo completed.');
    },
  );

  test('think-block todowrite narration is not a spoken receipt', () async {
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [],
        text:
            '<think>I called todowrite and marked it complete</think>\n'
            'Hmph. I will look around first.',
        reasoning: 'I called todowrite and marked it complete',
      ),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: iris(),
      mode: WaifuMode.yolo,
    );

    await WaifuHarness(session: session, llm: llm).send('look around');

    final reply = session.transcript.where((m) => !m.isUser).single;
    expect(reply.text, contains('look around first'));
    expect(reply.chips.any((c) => c.detail.contains('no todowrite')), isFalse);
  });
}
