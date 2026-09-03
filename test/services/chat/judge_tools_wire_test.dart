// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Wire identity of the three prefix-sharing judges: identical tools list,
// named tool_choice per judge, one-shot stays on its own list, HTTP payload
// identity on both doors, EvalTraffic labels from spec.toolChoice.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/realism_evals.dart';
import 'package:front_porch_ai/services/chat/realism_tools.dart';
import 'package:front_porch_ai/services/chat/tool_eval_spec.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/openai_chat_stream.dart';
import 'package:front_porch_ai/services/tool_choice_style_probe.dart';

import 'realism_evals_test.dart' show createTestRealismEvals;

void main() {
  setUpAll(() => HttpOverrides.global = null);

  group('kJudgeEvalTools', () {
    test('is relationship + emotional + narrative, in that order', () {
      final names = kJudgeEvalTools
          .map((t) => (t['function'] as Map)['name'] as String)
          .toList();
      expect(names, [kRelationshipTool, kEmotionalTool, kNarrativeTool]);
    });
  });

  group('judge call sites', () {
    test(
      'all three judges send kJudgeEvalTools + their own toolChoice',
      () async {
        final specs = <ToolEvalSpec>[];
        final svc = _judges((spec) async {
          specs.add(spec);
          return LlmToolResponse(
            calls: [
              LlmToolCall(
                name: spec.toolChoice ?? '',
                arguments: {
                  'relationship_delta': 0,
                  'trust_delta': 0,
                  'emotion': 'neutral',
                  'emotion_intensity': 'mild',
                },
              ),
            ],
            text: '',
          );
        });
        await svc.evaluateRelationshipCall();
        await svc.evaluateEmotionalStateCall();
        await svc.evaluateNarrativeCall();
        expect(specs, hasLength(3));
        for (final spec in specs) {
          expect(jsonEncode(spec.tools), jsonEncode(kJudgeEvalTools));
        }
        expect(specs.map((s) => s.toolChoice).toList(), [
          kRelationshipTool,
          kEmotionalTool,
          kNarrativeTool,
        ]);
        expect(
          specs.map((s) => s.toolChoice).toSet(),
          hasLength(3),
          reason:
              'EvalTraffic labels come from spec.toolChoice — never '
              'three times report_relationship',
        );

        await svc.evaluateOneShotCall();
        expect(specs, hasLength(4));
        expect(
          jsonEncode(specs.last.tools),
          isNot(jsonEncode(kJudgeEvalTools)),
        );
        expect(specs.last.toolChoice, kOneShotTool);
      },
    );
  });

  group('HTTP payload', () {
    late HttpServer server;
    final requests = <Map<String, dynamic>>[];

    setUp(() async {
      requests.clear();
      ToolChoiceStyleProbe.instance.resetForTest();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        requests.add(
          jsonDecode(await utf8.decoder.bind(req).join())
              as Map<String, dynamic>,
        );
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.json;
        req.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'tool_calls': [
                    {
                      'function': {
                        'name': 'report_relationship',
                        'arguments': '{}',
                      },
                    },
                  ],
                },
              },
            ],
          }),
        );
        await req.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('postOpenAiChatWithTools: identical tools, named choice', () async {
      for (final name in [kRelationshipTool, kEmotionalTool, kNarrativeTool]) {
        await postOpenAiChatWithTools(
          'http://127.0.0.1:${server.port}',
          const GenerationParams(prompt: 'judge', maxLength: 512),
          kJudgeEvalTools,
          toolChoice: name,
        );
      }
      expect(requests, hasLength(3));
      final encoded = requests.map((r) => jsonEncode(r['tools'])).toSet();
      expect(encoded, hasLength(1), reason: 'tools arrays must be identical');
      expect(jsonDecode(encoded.single), kJudgeEvalTools);
      expect(requests.map((r) => r['tool_choice']).toList(), [
        {
          'type': 'function',
          'function': {'name': kRelationshipTool},
        },
        {
          'type': 'function',
          'function': {'name': kEmotionalTool},
        },
        {
          'type': 'function',
          'function': {'name': kNarrativeTool},
        },
      ]);
      expect(requests.any((r) => r['tool_choice'] == 'auto'), isFalse);
    });

    test(
      'OpenRouter generateWithTools: identical tools, named choice',
      () async {
        final svc = OpenRouterService(
          apiUrl: 'http://127.0.0.1:${server.port}/v1',
          modelName: 'test-model',
        );
        for (final name in [
          kRelationshipTool,
          kEmotionalTool,
          kNarrativeTool,
        ]) {
          await svc.generateWithTools(
            GenerationParams(prompt: 'judge', maxLength: 512, toolChoice: name),
            kJudgeEvalTools,
          );
        }
        expect(requests, hasLength(3));
        expect(
          requests.map((r) => jsonEncode(r['tools'])).toSet(),
          hasLength(1),
        );
        expect(
          requests.map((r) => (r['tool_choice'] as Map)['function']['name']),
          [kRelationshipTool, kEmotionalTool, kNarrativeTool],
        );
      },
    );
  });
}

RealismEvals _judges(FireToolEval fire) {
  final b = createTestRealismEvals();
  return RealismEvals(
    fireLLMEval: b.fireLLMEval,
    fireToolEval: fire,
    probe: b.probe,
    getBackendIdentity: b.getBackendIdentity,
    isEvalCancelled: b.isEvalCancelled,
    stripThinkBlocks: b.stripThinkBlocks,
    extractJsonInt: b.extractJsonInt,
    extractJsonBool: b.extractJsonBool,
    getActiveCharacter: b.getActiveCharacter,
    getActiveGroup: b.getActiveGroup,
    getIsObserverMode: b.getIsObserverMode,
    getUserName: b.getUserName,
    getRealismEnabled: b.getRealismEnabled,
    getMessages: b.getMessages,
    getPendingRealismMetadata: b.getPendingRealismMetadata,
    setPendingRealismMetadata: b.setPendingRealismMetadata,
    captureRealismState: b.captureRealismState,
    getCharacterEmotion: b.getCharacterEmotion,
    setCharacterEmotion: b.setCharacterEmotion,
    getEmotionIntensity: b.getEmotionIntensity,
    setEmotionIntensity: b.setEmotionIntensity,
    relationshipService: b.relationshipService,
    nsfwService: b.nsfwService,
    timeService: b.timeService,
    getExpressionEnabled: b.getExpressionEnabled,
    getCharacterDossier: b.getCharacterDossier,
    getPrimaryObjective: b.getPrimaryObjective,
    getActiveObjectives: b.getActiveObjectives,
    setObjective: b.setObjective,
  );
}
