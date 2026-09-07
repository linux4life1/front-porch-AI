// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// fireStructuredEval verdict rules — the ONE tools-vs-text negotiation for
// realism/needs/scene-time/expression/cast evals. Pins the "empty answer is
// never a capability verdict" rule: a KoboldCpp server-side abort completes
// an in-flight tool call as a clean empty 200, and branding on that shape is
// what made the tool-calling pill fall to "not supported" after a Scene
// Guest joined (long mint generation + concurrent eval burst + abort/idle
// traffic on the single-slot backend).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart'
    show LlmToolCall, LlmToolResponse, LlmToolTransportException;

void main() {
  group('fireStructuredEval verdicts', () {
    const id = 'Kobold|model-a';

    Future<({String? result, ToolTransportProbe probe, int textCalls})> run({
      required Future<LlmToolResponse?> Function() toolAnswer,
      ToolTransportProbe? probe,
      List<Map<String, dynamic>>? evalTools,
      String toolChoice = kRelationshipTool,
    }) async {
      final p = probe ?? ToolTransportProbe();
      var textCalls = 0;
      final result = await fireStructuredEval(
        probe: p,
        backendIdentity: id,
        debugLabel: 'test',
        tools: evalTools ?? kRelationshipEvalTools,
        toolChoice: toolChoice,
        buildPrompt: ({required bool toolsMode}) =>
            toolsMode ? 'TOOLS' : 'TEXT',
        callToText: (resp) => realismToolCallToJson(toolChoice, resp.calls),
        fireToolEval: (_, _) => toolAnswer(),
        fireTextEval: (prompt, {onChunk}) async {
          textCalls++;
          return 'TEXT-RESULT';
        },
      );
      return (result: result, probe: p, textCalls: textCalls);
    }

    test('a real tool call → supported, converted text returned', () async {
      final r = await run(
        toolAnswer: () async => const LlmToolResponse(
          calls: [
            LlmToolCall(
              name: kRelationshipTool,
              arguments: {'relationship_delta': 0, 'trust_delta': 0},
            ),
          ],
          text: '',
        ),
      );
      expect(r.result, '{"relationship_delta":0,"trust_delta":0}');
      expect(r.probe.supportFor(id), ToolCallSupport.supported);
      expect(r.textCalls, 0);
    });

    test(
      'EMPTY answer (server-side abort shape) → text fallback, NO verdict',
      () async {
        final r = await run(
          toolAnswer: () async => const LlmToolResponse(calls: [], text: ''),
        );
        expect(r.result, 'TEXT-RESULT');
        expect(r.textCalls, 1);
        expect(
          r.probe.supportFor(id),
          ToolCallSupport.untested,
          reason: 'an aborted call answers as a clean empty 200 — never brand',
        );
      },
    );

    test('null answer → text fallback, NO verdict', () async {
      final r = await run(toolAnswer: () async => null);
      expect(r.result, 'TEXT-RESULT');
      expect(r.probe.supportFor(id), ToolCallSupport.untested);
    });

    test(
      'prose answer falls through to text without branding the model',
      () async {
        // OpenRouter can return ordinary prose while claiming the forced tool
        // parameter is supported. Returning it here used to skip the working
        // streaming JSON fallback, freezing Realism and scene Needs.
        final r = await run(
          toolAnswer: () async =>
              const LlmToolResponse(calls: [], text: 'bond_delta: 3'),
        );
        expect(r.result, 'TEXT-RESULT');
        expect(r.probe.supportFor(id), ToolCallSupport.untested);
        expect(r.textCalls, 1);
      },
    );

    test('complete JSON text remains a usable salvage response', () async {
      const json = '{"relationship_delta":3,"trust_delta":1}';
      final r = await run(
        toolAnswer: () async => const LlmToolResponse(calls: [], text: json),
      );
      expect(r.result, json);
      expect(r.probe.supportFor(id), ToolCallSupport.untested);
      expect(r.textCalls, 0);
    });

    test('JSON missing a required eval field falls through to text', () async {
      final r = await run(
        toolAnswer: () async =>
            const LlmToolResponse(calls: [], text: '{"relationship_delta":3}'),
      );
      expect(r.result, 'TEXT-RESULT');
      expect(r.probe.supportFor(id), ToolCallSupport.untested);
      expect(r.textCalls, 1);
    });

    test('invalid expression enum falls through to text', () async {
      final r = await run(
        evalTools: kExpressionEvalTools,
        toolChoice: kExpressionTool,
        toolAnswer: () async => const LlmToolResponse(
          calls: [],
          text: '{"label":"not-an-expression"}',
        ),
      );
      expect(r.result, 'TEXT-RESULT');
      expect(r.textCalls, 1);
    });

    test('unusable cast JSON falls through instead of meaning none', () async {
      for (final text in const [
        '{"error":"ignored tool"}',
        '{"descriptor":"the host\'s sister"}',
      ]) {
        final r = await run(
          evalTools: kCastDetectEvalTools,
          toolChoice: kCastDetectTool,
          toolAnswer: () async => LlmToolResponse(calls: const [], text: text),
        );
        expect(r.result, 'TEXT-RESULT', reason: text);
        expect(r.textCalls, 1, reason: text);
      }
    });

    test(
      'nested required fields are validated before Pockets salvage',
      () async {
        final r = await run(
          evalTools: PocketsEval.tools,
          toolChoice: PocketsEval.kPocketsTool,
          toolAnswer: () async => const LlmToolResponse(
            calls: [],
            text: '{"inventory_ops":[{"op":"pickup"}]}',
          ),
        );
        expect(r.result, 'TEXT-RESULT');
        expect(r.textCalls, 1);
      },
    );

    test('transport failure → text fallback, NO verdict', () async {
      final r = await run(
        toolAnswer: () async =>
            throw LlmToolTransportException('server busy 503'),
      );
      expect(r.result, 'TEXT-RESULT');
      expect(r.probe.supportFor(id), ToolCallSupport.untested);
    });

    test('non-transport rejection still brands XML-only', () async {
      final r = await run(
        toolAnswer: () async => throw StateError('tools field rejected'),
      );
      expect(r.result, 'TEXT-RESULT');
      expect(r.probe.supportFor(id), ToolCallSupport.unsupported);
    });

    test('an XML-only verdict skips the tools attempt entirely', () async {
      var toolCalls = 0;
      final r = await run(
        probe: ToolTransportProbe()..markXmlOnly(id),
        toolAnswer: () async {
          toolCalls++;
          return null;
        },
      );
      expect(r.result, 'TEXT-RESULT');
      expect(toolCalls, 0);
    });
  });

  group('evalBackendIdentityFor', () {
    test('same model slug on Nano-GPT and OpenRouter has distinct state', () {
      final nano = evalBackendIdentityFor(
        backendName: 'Remote API',
        remoteApiUrl: 'https://nano-gpt.com/api/v1',
        remoteModelName: 'shared/model',
        modelPath: null,
      );
      final openRouter = evalBackendIdentityFor(
        backendName: 'Remote API',
        remoteApiUrl: 'https://openrouter.ai/api/v1',
        remoteModelName: 'shared/model',
        modelPath: null,
      );
      expect(nano, isNot(openRouter));
    });

    test('ChatService includes the configured API URL at the call site', () {
      final wiring = File(
        'lib/services/chat/chat_service_wiring_evals.dart',
      ).readAsStringSync();
      expect(wiring, contains('return evalBackendIdentityFor('));
      expect(
        wiring,
        allOf(
          contains('_llmProvider?.activeApiUrl'),
          contains('remoteApiUrl: remoteApiUrl'),
        ),
        reason: 'the key must use the active oMLX/OpenRouter service endpoint',
      );
    });
  });
}
