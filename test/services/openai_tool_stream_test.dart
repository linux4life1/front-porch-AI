// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/openai_tool_stream.dart';

void main() {
  test('parser yields think-wrapped reasoning then a bash tool call', () {
    final parser = OpenAiToolStreamParser(wrap: true);
    final chunks = <String>[];
    chunks.add(
      parser.onDelta({'reasoning_content': 'look at the folder first'}),
    );
    chunks.add(
      parser.onDelta({
        'tool_calls': [
          {
            'index': 0,
            'id': 'c1',
            'function': {'name': 'bash', 'arguments': ''},
          },
        ],
      }),
    );
    chunks.add(
      parser.onDelta({
        'tool_calls': [
          {
            'index': 0,
            'function': {'arguments': '{"command":"ls"}'},
          },
        ],
      }),
    );
    final tail = parser.closeThink();
    final resp = parser.toResponse();
    expect(chunks.join(), contains('<think>look at the folder first'));
    expect(tail, contains('</think>'));
    expect(resp.calls.single.name, 'bash');
    expect(resp.calls.single.arguments['command'], 'ls');
    expect(resp.reasoning, 'look at the folder first');
  });

  test(
    'consumeOpenAiToolSse forwards live chunks then the tool call',
    () async {
      final sse = [
        'data: {"choices":[{"delta":{"reasoning_content":"hmm"}}]}\n',
        'data: {"choices":[{"delta":{"content":"done"}}]}\n',
        'data: [DONE]\n',
      ].join();
      final live = <String>[];
      final resp = await consumeOpenAiToolSse(
        Stream<List<int>>.fromIterable([utf8.encode(sse)]),
        wrap: true,
        onChunk: live.add,
      );
      expect(live.join(), contains('<think>hmm'));
      expect(live.join(), contains('done'));
      expect(resp!.text, 'done');
      expect(resp.reasoning, 'hmm');
    },
  );
}
