// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Fused one-shot fire: tools retry, tight text, recovery. Deltas must
// still come back — never skip the turn.
//
// Proven red:
//   * prose tools miss without a retry → textCalls > 0 / second tools skipped
//   * think-dump text with no recovery tools → result null
//   * honest empty still firing recovery-text → textCalls == 2
//   * think-dump abort without recovery-text when tools miss → result null
//   * happy tools path still returns the call JSON

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart'
    show LlmToolCall, LlmToolResponse;

const _json =
    '{"relationship_delta":1,"trust_delta":0,"emotion":"calm","emotion_intensity":"mild"}';

void main() {
  const id =
      'Remote API|https://nano-gpt.com/api/v1|moonshotai/kimi-k2.6:thinking|';

  Future<
    ({String? result, int toolCalls, int textCalls, List<String> textPrompts})
  >
  run({
    required List<LlmToolResponse?> toolScript,
    String? textResult,
    List<FusedTextAttempt>? textScript,
    Duration budget = const Duration(seconds: 5),
  }) async {
    var toolCalls = 0;
    var textCalls = 0;
    final textPrompts = <String>[];
    final result = await fireFusedRealismEval(
      probe: ToolTransportProbe(),
      backendIdentity: id,
      debugLabel: kOneShotTool,
      tools: kOneShotEvalTools,
      toolChoice: kOneShotTool,
      buildPrompt: ({required bool toolsMode}) => toolsMode ? 'TOOLS' : 'TEXT',
      callToText: (resp) => realismToolCallToJson(kOneShotTool, resp.calls),
      fireToolEval: (_, _) async {
        final i = toolCalls;
        toolCalls++;
        if (i >= toolScript.length) return null;
        return toolScript[i];
      },
      fireTightText: (prompt, {onChunk, wallClockTimeout}) async {
        final i = textCalls;
        textCalls++;
        textPrompts.add(prompt);
        if (textScript != null) {
          return i < textScript.length
              ? textScript[i]
              : const FusedTextAttempt.empty();
        }
        return fusedTextFromRaw(textResult);
      },
      budget: budget,
    );
    return (
      result: result,
      toolCalls: toolCalls,
      textCalls: textCalls,
      textPrompts: textPrompts,
    );
  }

  test('happy tools path is one call and no text hose', () async {
    final r = await run(
      toolScript: [
        const LlmToolResponse(
          calls: [
            LlmToolCall(
              name: kOneShotTool,
              arguments: {
                'relationship_delta': 1,
                'trust_delta': 0,
                'emotion': 'calm',
                'emotion_intensity': 'mild',
              },
            ),
          ],
          text: '',
        ),
      ],
    );
    expect(r.result, contains('"relationship_delta":1'));
    expect(r.toolCalls, 1);
    expect(r.textCalls, 0);
  });

  test('prose on first tools retries tools, not text', () async {
    final r = await run(
      toolScript: [
        const LlmToolResponse(calls: [], text: 'I think she feels warm.'),
        const LlmToolResponse(
          calls: [
            LlmToolCall(
              name: kOneShotTool,
              arguments: {
                'relationship_delta': 2,
                'trust_delta': 0,
                'emotion': 'happy',
                'emotion_intensity': 'mild',
              },
            ),
          ],
          text: '',
        ),
      ],
    );
    expect(r.result, contains('"relationship_delta":2'));
    expect(r.toolCalls, 2);
    expect(r.textCalls, 0);
  });

  test('tools miss then tight text still yields JSON deltas', () async {
    final r = await run(
      toolScript: [
        const LlmToolResponse(calls: [], text: 'prose'),
        const LlmToolResponse(calls: [], text: 'still prose'),
      ],
      textResult: _json,
    );
    expect(r.result, _json);
    expect(r.toolCalls, 2);
    expect(r.textCalls, 1);
    expect(r.textPrompts.single, 'TEXT');
  });

  test(
    'think-dump / empty text recovers via tools and still applies',
    () async {
      final r = await run(
        toolScript: [
          const LlmToolResponse(calls: [], text: 'prose'),
          const LlmToolResponse(calls: [], text: 'prose'),
          const LlmToolResponse(
            calls: [
              LlmToolCall(
                name: kOneShotTool,
                arguments: {
                  'relationship_delta': 3,
                  'trust_delta': 1,
                  'emotion': 'sad',
                  'emotion_intensity': 'strong',
                },
              ),
            ],
            text: '',
          ),
        ],
        textScript: const [FusedTextAttempt.aborted()],
      );
      expect(r.result, contains('"relationship_delta":3'));
      expect(r.toolCalls, 3);
      expect(r.textCalls, 1);
    },
  );

  test('honest empty text does not fire a second LLM text call', () async {
    final r = await run(
      toolScript: [
        const LlmToolResponse(calls: [], text: 'prose'),
        const LlmToolResponse(calls: [], text: 'prose'),
        const LlmToolResponse(calls: [], text: 'prose'),
      ],
      textResult: null,
    );
    expect(r.result, isNull);
    expect(r.textCalls, 1);
    expect(r.toolCalls, 3);
  });

  test(
    'think-dump abort still fires JSON-only recovery when tools miss',
    () async {
      final r = await run(
        toolScript: [
          const LlmToolResponse(calls: [], text: 'prose'),
          const LlmToolResponse(calls: [], text: 'prose'),
          const LlmToolResponse(calls: [], text: 'prose'),
        ],
        textScript: [
          const FusedTextAttempt.aborted(),
          FusedTextAttempt.ok(_json),
        ],
      );
      expect(r.result, _json);
      expect(r.toolCalls, 3);
      expect(r.textCalls, 2);
      expect(r.textPrompts.last, contains('ONLY the JSON object'));
    },
  );
}
