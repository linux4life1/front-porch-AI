// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:front_porch_ai/services/llm_service.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('desk_bubbles_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('each loop step keeps its own speech and think', () async {
    final llm = ScriptedDeskLlm([
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
      const LlmToolResponse(calls: [], text: 'Done.'),
    ]);
    final session = DeskSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Iris'),
      mode: DeskMode.yolo,
    );
    await DeskHarness(session: session, llm: llm).send('scaffold');
    final spoken = session.transcript.where((m) => !m.isUser).toList();
    expect(spoken, hasLength(3));
    expect(spoken[0].text, contains('On it.'));
    expect(spoken[0].reasoning, contains('look around'));
    expect(spoken[0].reasoning, isNot(contains('write the file')));
    expect(spoken[0].chips.single.name, 'bash');
    expect(spoken[1].text, contains('Wrote a.txt.'));
    expect(spoken[1].reasoning, contains('write the file'));
    expect(spoken[1].reasoning, isNot(contains('look around')));
    expect(spoken[1].chips.single.name, 'write');
    expect(spoken[2].text, 'Done.');
    expect(spoken[2].chips, isEmpty);
  });
}
