// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  test('empty native calls salvage a leak in reasoning', () {
    const resp = LlmToolResponse(
      calls: [],
      text: 'Give me a moment.',
      reasoning:
          '◁tool_call_begin▷functions/write:0◁tool_call_argument_begin▷'
          '{"path": "a.txt", "contents": "hi"}◁tool_call_end▷',
    );
    final calls = waifuEffectiveToolCalls(resp);
    expect(calls, hasLength(1));
    expect(calls.single.name, 'write');
    expect(calls.single.arguments['path'], 'a.txt');
  });

  test('<function=write> is salvaged the same as MiniMax', () {
    const raw =
        '<function=write>{"path": "PageTurn.swift", "contents": "x"}</function>';
    final calls = waifuLeakedToolCalls(raw);
    expect(calls, hasLength(1));
    expect(calls.single.name, 'write');
    expect(calls.single.arguments['path'], 'PageTurn.swift');
    expect(waifuStripToolLeak('ok\n$raw'), 'ok');
  });

  test('unclosed <tool_call> is stripped so it is not wrap-up speech', () {
    const raw =
        'Working.\n<tool_call>\n{"name": "edit", "arguments": {"path": "a.swift"}}';
    expect(waifuStripToolLeak(raw), 'Working.');
    final calls = waifuLeakedToolCalls(raw);
    expect(calls.single.name, 'edit');
  });

  test('leaked protocol is stripped from reasoning before preserve inject', () {
    const dump =
        '◁tool_call_begin▷functions/write:0◁tool_call_argument_begin▷'
        '{"path": "a.txt"}◁tool_call_end▷';
    final last = const WaifuMessage.assistant('');
    final painted = waifuApplyChunk(
      last: last,
      priorReasoning: dump,
      streamBuf: '',
    );
    expect(painted.reasoning, isNot(contains('tool_call')));
    final merged = waifuMergeReasoning(
      last,
      const LlmToolResponse(calls: [], text: 'hi', reasoning: dump),
    );
    expect(merged, isNull);
  });

  test('untagged planning is not wrap-up speech', () {
    const dump =
        'The user wants two things:\n'
        '1. Images not loading in the EPUB.\n'
        'Let me look at the screenshot first, then fix both issues.';
    expect(waifuLooksThinkDump(dump), isTrue);
    expect(waifuSpokenLine(dump), isEmpty);
    expect(
      waifuSpokenLine('Hmph. Cover is still blank.'),
      'Hmph. Cover is still blank.',
    );
    final painted = waifuApplyChunk(
      last: const WaifuMessage.assistant(''),
      priorReasoning: '',
      streamBuf: dump,
      paintBody: true,
    );
    expect(painted.text, isEmpty);
    expect(painted.reasoning, contains('The user wants'));
  });
}
