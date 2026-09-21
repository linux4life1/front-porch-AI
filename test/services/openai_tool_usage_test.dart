// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/llm_tool_parsing.dart';
import 'package:front_porch_ai/services/openai_tool_payload.dart';
import 'package:front_porch_ai/services/openai_tool_stream.dart';

void main() {
  test('parseOpenAiToolResponse reads usage.prompt_tokens', () {
    final resp = parseOpenAiToolResponse(
      jsonEncode({
        'usage': {
          'prompt_tokens': 1200,
          'completion_tokens': 80,
          'total_tokens': 1280,
        },
        'choices': [
          {
            'message': {'content': 'ok', 'tool_calls': []},
          },
        ],
      }),
    )!;
    expect(resp.promptTokens, 1200);
    expect(resp.completionTokens, 80);
    expect(resp.totalTokens, 1280);
    expect(resp.usedTokens, 1280);
  });

  test('SSE usage-only chunk is not dropped', () async {
    final sse = [
      'data: {"choices":[{"delta":{"content":"hi"}}]}\n',
      'data: {"choices":[],"usage":{"prompt_tokens":500,'
          '"completion_tokens":2,"total_tokens":502}}\n',
      'data: [DONE]\n',
    ].join();
    final resp = await consumeOpenAiToolSse(
      Stream<List<int>>.fromIterable([utf8.encode(sse)]),
      wrap: false,
    );
    expect(resp!.text, 'hi');
    expect(resp.promptTokens, 500);
    expect(resp.completionTokens, 2);
    expect(resp.totalTokens, 502);
    expect(resp.usedTokens, 502);
  });

  test('streamed attachTools asks for usage on the last SSE event', () {
    final payload = attachTools(
      <String, dynamic>{},
      tools: const [
        {
          'type': 'function',
          'function': {'name': 'read'},
        },
      ],
      stream: true,
      includeUsage: true,
    );
    expect(payload['stream'], isTrue);
    expect(payload['stream_options'], {'include_usage': true});
  });

  test('non-stream attachTools does not send stream_options', () {
    final payload = attachTools(
      <String, dynamic>{},
      tools: const [
        {
          'type': 'function',
          'function': {'name': 'read'},
        },
      ],
    );
    expect(payload['stream'], isFalse);
    expect(payload.containsKey('stream_options'), isFalse);
  });
}
