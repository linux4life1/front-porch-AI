// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// fireStructuredEval must salvage JSON that landed in reasoning_content
// (empty tool_calls + think-channel JSON) instead of treating that as a
// failed tools attempt. #230 only looked at message.content.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart'
    show LlmToolCall, LlmToolResponse;

void main() {
  const id = 'Remote API|https://openrouter.ai/api/v1|grok|';

  Future<({String? result, int textCalls})> run({
    required Future<LlmToolResponse?> Function() toolAnswer,
  }) async {
    var textCalls = 0;
    final result = await fireStructuredEval(
      probe: ToolTransportProbe(),
      backendIdentity: id,
      debugLabel: 'relationship',
      tools: kRelationshipEvalTools,
      toolChoice: kRelationshipTool,
      buildPrompt: ({required bool toolsMode}) => toolsMode ? 'TOOLS' : 'TEXT',
      callToText: (resp) =>
          realismToolCallToJson(kRelationshipTool, resp.calls),
      fireToolEval: (_, _) => toolAnswer(),
      fireTextEval: (prompt, {onChunk}) async {
        textCalls++;
        return 'TEXT-RESULT';
      },
    );
    return (result: result, textCalls: textCalls);
  }

  test(
    'JSON only in reasoning_content is salvaged, no text fallback',
    () async {
      final r = await run(
        toolAnswer: () async => const LlmToolResponse(
          calls: [],
          text: '',
          reasoning: '{"relationship_delta":2,"trust_delta":1}',
        ),
      );
      expect(r.result, '{"relationship_delta":2,"trust_delta":1}');
      expect(r.textCalls, 0);
    },
  );

  test('JSON wrapped in think-prose is sliced before schema check', () async {
    final r = await run(
      toolAnswer: () async => const LlmToolResponse(
        calls: [],
        text: 'thinking...\n{"relationship_delta":8,"trust_delta":0}\n',
      ),
    );
    expect(r.result, '{"relationship_delta":8,"trust_delta":0}');
    expect(r.textCalls, 0);
  });

  test('real tool calls still win over leftover reasoning JSON', () async {
    final r = await run(
      toolAnswer: () async => const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: kRelationshipTool,
            arguments: {'relationship_delta': 1, 'trust_delta': 1},
          ),
        ],
        text: '',
        reasoning: '{"relationship_delta":99,"trust_delta":99}',
      ),
    );
    expect(r.result, '{"relationship_delta":1,"trust_delta":1}');
    expect(r.textCalls, 0);
  });
}
