// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Mandatory-reasoning 400 retry must still POST a second time with the
// original named tool_choice (params.toolChoice rides through the recursive
// call). The style probe must stay `named` because the body has no
// `tool_choice`.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/reasoning_effort.dart';
import 'package:front_porch_ai/services/tool_choice_style_probe.dart';

void main() {
  setUpAll(() => HttpOverrides.global = null);

  late HttpServer server;
  final requests = <Map<String, dynamic>>[];
  var call = 0;

  setUp(() async {
    requests.clear();
    call = 0;
    kMandatoryReasoningModels.remove('kimi-retry-test');
    ToolChoiceStyleProbe.instance.resetForTest();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      requests.add(
        jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>,
      );
      call++;
      req.response.headers.contentType = ContentType.json;
      if (call == 1) {
        req.response.statusCode = 400;
        req.response.write(
          jsonEncode({
            'error': {
              'message':
                  'Kimi K2 Thinking is a mandatory-reasoning model. Use '
                  'reasoning.exclude=true to hide reasoning output.',
            },
          }),
        );
      } else {
        req.response.statusCode = 200;
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
      }
      await req.response.close();
    });
  });

  tearDown(() async {
    kMandatoryReasoningModels.remove('kimi-retry-test');
    await server.close(force: true);
  });

  test(
    'mandatory-reasoning 400 retries with named tool_choice intact',
    () async {
      final svc = OpenRouterService(
        apiUrl: 'http://127.0.0.1:${server.port}/v1',
        modelName: 'kimi-retry-test',
      );
      final resp = await svc.generateWithTools(
        const GenerationParams(
          prompt: 'eval',
          maxLength: 512,
          salvageReasoning: true,
          reasoningEnabled: false,
          reasoningMaxTokens: 0,
          toolChoice: 'report_relationship',
        ),
        const [
          {
            'type': 'function',
            'function': {'name': 'report_relationship'},
          },
        ],
      );
      expect(requests, hasLength(2), reason: 'second POST must fire');
      expect(kMandatoryReasoningModels.contains('kimi-retry-test'), isTrue);
      expect(
        ToolChoiceStyleProbe.instance.styleFor('Remote API|kimi-retry-test|'),
        ToolChoiceStyle.named,
      );
      for (final req in requests) {
        expect(req['tool_choice'], {
          'type': 'function',
          'function': {'name': 'report_relationship'},
        });
      }
      expect(resp!.calls.single.name, 'report_relationship');
      expect(
        requests[1]['max_tokens'],
        512 + kMandatoryReasoningThinkHeadroomTokens,
      );
    },
  );
}
