// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

void main() {
  test('failed write is FAILED in the next generate, not ok/error', () async {
    final root = await Directory.systemTemp.createTemp('waifu_fail_loop_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'write',
            arguments: {'path': '../outside.txt', 'contents': 'nope'},
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'Jail stopped that write.'),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Iris'),
    );
    await WaifuHarness(session: session, llm: llm).send('write outside');
    expect(llm.calls.length, greaterThanOrEqualTo(2));
    final next = llm.calls.skip(1).map((c) => c.prompt).join('\n');
    expect(next, contains('[tool write FAILED]'));
    expect(next, contains('Disk was not changed'));
    expect(next, isNot(contains('[tool write ok]')));
    expect(next, isNot(contains('[tool write error]')));
    final failChip = session.toolChips.where((c) => c.name == 'write');
    expect(failChip, isNotEmpty);
    expect(failChip.first.ok, isFalse);
    expect(failChip.first.detail, isNot('error'));
  });

  test('tool-only step with no think body does not stamp thinkingMs', () async {
    final root = await Directory.systemTemp.createTemp('waifu_think_empty_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    await File(p.join(root.path, 'notes.txt')).writeAsString('hi');
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(name: 'read', arguments: {'path': 'notes.txt'}),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'Read it.'),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Iris'),
    );
    await WaifuHarness(session: session, llm: llm).send('read notes');
    final toolBubble = session.transcript.where(
      (m) => m.kind == WaifuMsgKind.assistant && m.chips.isNotEmpty,
    );
    expect(toolBubble, isNotEmpty);
    expect(toolBubble.first.reasoning.trim(), isEmpty);
    expect(toolBubble.first.thinkingMs, 0);
    expect(toolBubble.first.toChatMessage('Iris').hasThinking, isFalse);
  });

  test('nested explore stays in folder jail on a whole-disk parent', () async {
    final sandbox = await Directory.systemTemp.createTemp('waifu_explore_');
    addTearDown(() async {
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    });
    final root = await Directory(p.join(sandbox.path, 'project')).create();
    await File(p.join(sandbox.path, 'outside.txt')).writeAsString('SECRET');
    await File(p.join(root.path, 'notes.txt')).writeAsString('inside');
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'task',
            arguments: {
              'subagent': 'explore',
              'prompt': 'read the sibling file',
            },
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(
        calls: [
          LlmToolCall(name: 'read', arguments: {'path': '../outside.txt'}),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'Could not leave the porch.'),
      const LlmToolResponse(calls: [], text: 'Parent wrap.'),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Iris'),
      mode: WaifuMode.yolo,
      pathMode: WaifuPathMode.wholeDisk,
    );
    await WaifuHarness(session: session, llm: llm).send('look outside');
    expect(llm.calls.length, greaterThanOrEqualTo(3));
    expect(llm.calls[1].prompt, isNot(contains('SECRET')));
    expect(
      llm.calls.skip(1).any((c) => c.prompt.contains('[tool read FAILED]')),
      isTrue,
    );
    expect(
      session.transcript.map((m) => m.text).join('\n'),
      isNot(contains('SECRET')),
    );
  });
}
