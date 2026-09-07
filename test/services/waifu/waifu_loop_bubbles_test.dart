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
    root = await Directory.systemTemp.createTemp('waifu_bubbles_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('one assistant bubble holds every tool and the last line', () async {
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(name: 'bash', arguments: {'command': 'ls'}),
        ],
        text: '<think>look around</think>\nOn it.',
        reasoning: 'look around',
      ),
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'write',
            arguments: {'path': 'a.txt', 'contents': 'x'},
          ),
        ],
        text: '<think>write the file</think>\nWrote a.txt.',
        reasoning: 'write the file',
      ),
      const LlmToolResponse(calls: [], text: 'Hmph. Your scaffold is on disk.'),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Iris'),
      mode: WaifuMode.yolo,
    );
    await WaifuHarness(session: session, llm: llm).send('scaffold');
    final spoken = session.transcript.where((m) => !m.isUser).toList();
    expect(spoken, hasLength(1));
    expect(spoken.single.chips.map((c) => c.name), ['bash', 'write']);
    expect(spoken.single.text, 'Hmph. Your scaffold is on disk.');
    expect(spoken.single.reasoning, contains('write the file'));
    expect(spoken.single.reasoning, isNot(contains('look around')));
  });
}
