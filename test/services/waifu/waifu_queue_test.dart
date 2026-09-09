// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  test('send while running queues and drains after the turn', () async {
    final root = await Directory.systemTemp.createTemp('waifu_queue_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final gate = Completer<void>();
    final llm = ScriptedWaifuLlm(
      [
        const LlmToolResponse(calls: [], text: 'first done'),
        const LlmToolResponse(calls: [], text: 'second done'),
      ],
      beforeGenerate: (i) async {
        if (i == 0) await gate.future;
      },
    );
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Iris'),
    );
    final harness = WaifuHarness(session: session, llm: llm);
    final first = harness.send('first');
    for (var i = 0; i < 40 && !session.running; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(session.running, isTrue);
    await harness.send('second');
    expect(session.queued, ['second']);
    expect(session.transcript.where((m) => m.isUser).map((m) => m.text), [
      'first',
    ]);
    gate.complete();
    await first;
    expect(session.queued, isEmpty);
    expect(session.transcript.where((m) => m.isUser).map((m) => m.text), [
      'first',
      'second',
    ]);
    expect(
      session.transcript
          .where((m) => m.kind == WaifuMsgKind.assistant)
          .map((m) => m.text),
      containsAll(['first done', 'second done']),
    );
  });
}
