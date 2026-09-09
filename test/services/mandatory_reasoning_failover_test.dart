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

// A 400 while we asked to switch thinking OFF is the Kimi salvage signal
// for EVERY model — not a name list and not a phrase list.
//
// GLM 5.3 (Discord 2026-09): "always thinks and does not support disabling
// reasoning." That sentence misses the Kimi matcher (mandatory /
// cannot be disabled / exclude=true), so both eval attempts 400'd and
// Realism/Needs dropped. Failover must not depend on that wording.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/reasoning_effort.dart';

const _glm53 =
    'GLM 5.3 always thinks and does not support disabling reasoning.';
const _generic400 = 'This request is invalid.';

Future<HttpServer> _startFake({
  required List<Map<String, dynamic>> seen,
  required String errorMessage,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((HttpRequest req) async {
    final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
    final reasoning = (body['reasoning'] as Map?)?.cast<String, dynamic>();
    seen.add(reasoning ?? <String, dynamic>{});

    if (reasoning != null && reasoning['enabled'] == false) {
      req.response
        ..statusCode = 400
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'error': {'message': errorMessage},
          }),
        );
      await req.response.close();
      return;
    }

    final wantTools = body['tools'] is List;
    if (wantTools) {
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': null,
                  'tool_calls': [
                    {
                      'id': 'c1',
                      'type': 'function',
                      'function': {
                        'name': 'report_realism',
                        'arguments': '{"relationship_delta":6,"trust_delta":3}',
                      },
                    },
                  ],
                },
              },
            ],
          }),
        );
      await req.response.close();
      return;
    }

    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType('text', 'event-stream');
    req.response.write(
      'data: ${jsonEncode({
        'choices': [
          {
            'delta': {'content': '{"relationship_delta":6,"trust_delta":3}'},
          },
        ],
      })}\n\n',
    );
    req.response.write('data: [DONE]\n\n');
    await req.response.close();
  });
  return server;
}

void main() {
  setUp(() {
    HttpOverrides.global = null;
    clearReasoningEffortCatalog();
  });
  tearDown(clearReasoningEffortCatalog);

  group('shouldFailoverToMandatoryReasoning', () {
    test('a 400 while thinking-off is the signal, wording does not matter', () {
      expect(
        shouldFailoverToMandatoryReasoning(
          statusCode: 400,
          askedToDisableThinking: true,
          errorMessage: _glm53,
        ),
        isTrue,
      );
      expect(
        shouldFailoverToMandatoryReasoning(
          statusCode: 400,
          askedToDisableThinking: true,
          errorMessage: _generic400,
        ),
        isTrue,
      );
    });

    test('does not steal effort-listing 400s or transport failures', () {
      expect(
        shouldFailoverToMandatoryReasoning(
          statusCode: 400,
          askedToDisableThinking: true,
          errorMessage:
              "Invalid 'reasoning_effort' value. Supported values: none, high, max",
        ),
        isFalse,
      );
      expect(
        shouldFailoverToMandatoryReasoning(
          statusCode: 500,
          askedToDisableThinking: true,
          errorMessage: _glm53,
        ),
        isFalse,
      );
      expect(
        shouldFailoverToMandatoryReasoning(
          statusCode: 400,
          askedToDisableThinking: false,
          errorMessage: _glm53,
        ),
        isFalse,
      );
    });
  });

  Future<void> _evalSurvives(String errorMessage, String model) async {
    final seen = <Map<String, dynamic>>[];
    final server = await _startFake(seen: seen, errorMessage: errorMessage);
    addTearDown(() => server.close(force: true));

    final svc = OpenRouterService(
      apiUrl: 'http://127.0.0.1:${server.port}',
      apiKey: 'test-key',
      modelName: model,
    );

    final out = StringBuffer();
    await for (final chunk in svc.generateStream(
      GenerationParams(
        prompt: 'Score the relationship_delta for this exchange.',
        maxLength: 128,
        reasoningEnabled: false,
        reasoningMaxTokens: 0,
        salvageReasoning: true,
      ),
    )) {
      out.write(chunk);
    }

    expect(
      out.toString(),
      contains('relationship_delta'),
      reason:
          'after a thinking-off 400 the eval must Kimi-salvage, '
          'not drop Realism/Needs',
    );
    expect(seen.length, 2, reason: 'one thinking-off 400, one salvage retry');
    expect(seen.first['enabled'], false);
    expect(seen.last.containsKey('enabled'), isFalse);
    expect(seen.last.containsKey('exclude'), isFalse);
    expect(reasoningCannotDisable(model), isTrue);
  }

  test(
    'GLM 5.3 phrasing still failovers — no per-model name or Kimi phrase',
    () async {
      await _evalSurvives(_glm53, 'z-ai/glm-5.3');
    },
  );

  test('a generic 400 while thinking-off failovers the same way', () async {
    await _evalSurvives(_generic400, 'acme/whatever-v9');
  });

  test('tool evals failover on a generic thinking-off 400', () async {
    final seen = <Map<String, dynamic>>[];
    final server = await _startFake(seen: seen, errorMessage: _generic400);
    addTearDown(() => server.close(force: true));

    final svc = OpenRouterService(
      apiUrl: 'http://127.0.0.1:${server.port}',
      apiKey: 'test-key',
      modelName: 'acme/whatever-v9',
    );

    final resp = await svc.generateWithTools(
      GenerationParams(
        prompt: 'Score the relationship_delta for this exchange.',
        maxLength: 128,
        reasoningEnabled: false,
        reasoningMaxTokens: 0,
        salvageReasoning: true,
      ),
      const [
        {
          'type': 'function',
          'function': {
            'name': 'report_realism',
            'parameters': <String, dynamic>{},
          },
        },
      ],
    );

    expect(resp, isNotNull);
    expect(seen.length, 2);
    expect(seen.first['enabled'], false);
    expect(seen.last.containsKey('enabled'), isFalse);
    expect(reasoningCannotDisable('acme/whatever-v9'), isTrue);
  });
}
