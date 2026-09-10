// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Proven red: Kimi leaked functions.write with Swift `}` in content.
// Non-greedy `{.*?}` stopped at the first brace; the write never ran.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

final _kimiWriteLeak =
    '<|tool_calls_section_begin|>'
    '<|tool_call_begin|>functions.write:1'
    '<|tool_call_argument_begin|>'
    '{"path": "Foo.swift", "content": "enum TurnDirection {\\n  case next\\n  case previous\\n}\\n"}'
    '<|tool_call_end|>'
    '<|tool_calls_section_end|>';

void main() {
  test('JSON object walker does not stop at a brace inside a string', () {
    expect(waifuTakeJsonObject('{"a":"{x}","b":1}', 0), '{"a":"{x}","b":1}');
  });

  test('Kimi write leak with Swift braces becomes a real tool call', () {
    final calls = waifuLeakedToolCalls(_kimiWriteLeak);
    expect(calls, hasLength(1));
    expect(calls.single.name, 'write');
    expect(calls.single.arguments['path'], 'Foo.swift');
    expect(calls.single.arguments['content'], contains('enum TurnDirection {'));
    expect(calls.single.arguments['content'], contains('case previous'));
  });

  test('visible speech drops the Kimi write dump', () {
    final visible = waifuVisibleText('Give me a moment.\n$_kimiWriteLeak');
    expect(visible, contains('Give me a moment.'));
    expect(visible, isNot(contains('tool_call')));
    expect(visible, isNot(contains('Foo.swift')));
  });

  test('leaked Kimi write actually lands on disk', () async {
    final root = await Directory.systemTemp.createTemp('waifu_kimi_write_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final llm = ScriptedWaifuLlm([
      LlmToolResponse(calls: const [], text: _kimiWriteLeak),
      const LlmToolResponse(calls: [], text: 'Patched, love.'),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Iris'),
      mode: WaifuMode.yolo,
    );
    await WaifuHarness(session: session, llm: llm).send('write Foo.swift');
    final file = File(p.join(root.path, 'Foo.swift'));
    expect(await file.exists(), isTrue);
    expect(await file.readAsString(), contains('enum TurnDirection {'));
    expect(
      session.transcript
          .where((m) => m.kind == WaifuMsgKind.assistant)
          .map((m) => m.text)
          .join('\n'),
      isNot(contains('tool_call')),
    );
  });
}
