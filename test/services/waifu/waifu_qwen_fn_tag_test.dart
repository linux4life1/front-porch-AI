// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Qwen <function=write>{...}</function> was stripped from speech but never
// salvaged, so leaked writes never hit disk.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

const _qwenWriteLeak =
    'Give me a moment.\n'
    '<function=write>{"path": "Foo.swift", "contents": '
    '"enum TurnDirection {\\n  case next\\n  case previous\\n}\\n"}'
    '</function>';

void main() {
  test('Qwen function tag becomes a real tool call', () {
    final calls = waifuLeakedToolCalls(_qwenWriteLeak);
    expect(calls, hasLength(1));
    expect(calls.single.name, 'write');
    expect(calls.single.arguments['path'], 'Foo.swift');
    expect(calls.single.arguments['contents'], contains('enum TurnDirection {'));
  });

  test('visible speech drops the Qwen dump', () {
    final visible = waifuVisibleText(_qwenWriteLeak);
    expect(visible, contains('Give me a moment.'));
    expect(visible, isNot(contains('function=write')));
    expect(visible, isNot(contains('Foo.swift')));
  });

  test('native tool_calls still win over the Qwen dump', () {
    const native = LlmToolCall(name: 'read', arguments: {'path': 'a.swift'});
    final resp = LlmToolResponse(calls: const [native], text: _qwenWriteLeak);
    expect(waifuEffectiveToolCalls(resp).single.name, 'read');
  });

  test('leaked Qwen write lands on disk through decide/jail', () async {
    final root = await Directory.systemTemp.createTemp('waifu_qwen_write_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(calls: [], text: _qwenWriteLeak),
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
  });
}
