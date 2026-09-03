// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// attachTools + attachToolsWithStyleRetry: named tool_choice on both doors,
// a tool_choice 400 steps named → required, an unrelated 400 does not step.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/openai_chat_stream.dart';
import 'package:front_porch_ai/services/openai_tool_payload.dart';
import 'package:front_porch_ai/services/tool_choice_style_probe.dart';

void main() {
  setUpAll(() => HttpOverrides.global = null);

  group('attachTools', () {
    test('named function is an object, null is auto', () {
      final named = attachTools(
        <String, dynamic>{},
        tools: const [
          {
            'type': 'function',
            'function': {'name': 'report_relationship'},
          },
        ],
        toolChoice: 'report_relationship',
      );
      expect(named['tool_choice'], {
        'type': 'function',
        'function': {'name': 'report_relationship'},
      });
      expect(named['stream'], false);

      final auto = attachTools(
        <String, dynamic>{},
        tools: const [
          {
            'type': 'function',
            'function': {'name': 'add_memory'},
          },
        ],
      );
      expect(auto['tool_choice'], 'auto');
    });
  });

  group('attachToolsWithStyleRetry', () {
    late HttpServer server;
    final requests = <Map<String, dynamic>>[];
    final statuses = <int>[];
    final bodies = <String>[];

    setUp(() async {
      requests.clear();
      statuses.clear();
      bodies.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        requests.add(
          jsonDecode(await utf8.decoder.bind(req).join())
              as Map<String, dynamic>,
        );
        final i = requests.length - 1;
        req.response.statusCode = i < statuses.length ? statuses[i] : 200;
        req.response.headers.contentType = ContentType.json;
        req.response.write(i < bodies.length ? bodies[i] : '{}');
        await req.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    Future<http.Response> post(Map<String, dynamic> payload) => http.post(
      Uri.parse('http://127.0.0.1:${server.port}/v1/chat/completions'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    test('tool_choice 400 steps named → required on the helper', () async {
      final probe = ToolChoiceStyleProbe();
      statuses.addAll([400, 200]);
      bodies.addAll([
        jsonEncode({
          'error': {'message': 'unknown tool_choice value'},
        }),
        jsonEncode({
          'choices': [
            {
              'message': {'content': 'ok'},
            },
          ],
        }),
      ]);
      final resp = await attachToolsWithStyleRetry(
        identity: 'id-a',
        tools: const [
          {
            'type': 'function',
            'function': {'name': 'report_ping'},
          },
        ],
        toolChoice: 'report_ping',
        basePayload: {'model': 'x'},
        post: post,
        probe: probe,
      );
      expect(resp.statusCode, 200);
      expect(requests, hasLength(2));
      expect(requests[0]['tool_choice'], {
        'type': 'function',
        'function': {'name': 'report_ping'},
      });
      expect(requests[1]['tool_choice'], 'required');
      expect(probe.styleFor('id-a'), ToolChoiceStyle.required);
    });

    test('unrelated 400 does not step the style', () async {
      final probe = ToolChoiceStyleProbe();
      statuses.add(400);
      bodies.add(
        jsonEncode({
          'error': {
            'message':
                'Kimi K2 Thinking is a mandatory-reasoning model. Use '
                'reasoning.exclude=true to hide reasoning output.',
          },
        }),
      );
      final resp = await attachToolsWithStyleRetry(
        identity: 'id-b',
        tools: const [
          {
            'type': 'function',
            'function': {'name': 'report_ping'},
          },
        ],
        toolChoice: 'report_ping',
        basePayload: {'model': 'x'},
        post: post,
        probe: probe,
      );
      expect(resp.statusCode, 400);
      expect(requests, hasLength(1));
      expect(probe.styleFor('id-b'), ToolChoiceStyle.named);
    });

    test('local door (postOpenAiChatWithTools) sends named choice', () async {
      statuses.add(200);
      bodies.add(
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
      ToolChoiceStyleProbe.instance.resetForTest();
      await postOpenAiChatWithTools(
        'http://127.0.0.1:${server.port}',
        const GenerationParams(prompt: 'eval', maxLength: 512),
        const [
          {
            'type': 'function',
            'function': {'name': 'report_relationship'},
          },
        ],
        toolChoice: 'report_relationship',
      );
      expect(requests.single['tool_choice'], {
        'type': 'function',
        'function': {'name': 'report_relationship'},
      });
      expect(requests.single['max_tokens'], 512);
    });

    test('OpenRouter door sends named choice from params.toolChoice', () async {
      statuses.add(200);
      bodies.add(
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
      ToolChoiceStyleProbe.instance.resetForTest();
      final svc = OpenRouterService(
        apiUrl: 'http://127.0.0.1:${server.port}/v1',
        modelName: 'test-model',
      );
      await svc.generateWithTools(
        const GenerationParams(
          prompt: 'eval',
          maxLength: 512,
          toolChoice: 'report_relationship',
        ),
        const [
          {
            'type': 'function',
            'function': {'name': 'report_relationship'},
          },
        ],
      );
      expect(requests.single['tool_choice'], {
        'type': 'function',
        'function': {'name': 'report_relationship'},
      });
    });
  });
}
