// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Guards proven to fail before passing:
//   * drop web_search from kWebSearchTools → advertised-tools assertion red
//   * skip the HTTP client on a cache miss → httpCalls expected 1, got 0
//   * return a fake wiki on empty search JSON → empty-result fragment missing
//   * skip cache on the second lookup → httpCalls expected 1, got 2

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/prompt_injection/search_injection.dart';
import 'package:front_porch_ai/services/chat/web_search_service.dart';
import 'package:front_porch_ai/services/chat/web_search_tools.dart';
import 'package:front_porch_ai/services/llm_service.dart';

class _ToolsLlm extends LLMService {
  _ToolsLlm({this.next});

  LlmToolResponse? next;
  List<Map<String, dynamic>>? lastTools;
  int generateWithToolsCalls = 0;
  int streamCalls = 0;

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    generateWithToolsCalls++;
    lastTools = tools;
    return next;
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    streamCalls++;
    yield 'streamed reply';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'test';
}

void main() {
  group('normalizeQuery', () {
    test('trims, lowercases, and collapses whitespace', () {
      expect(
        WebSearchService.normalizeQuery('  Wandenreich   Bleach '),
        'wandenreich bleach',
      );
    });
  });

  group('SearchInjection', () {
    test('empty result names the query and forbids inventing', () {
      final text = SearchInjection.emptyResultFragment('Wandenreich');
      expect(text, contains('"Wandenreich"'));
      expect(text.toLowerCase(), contains('do not invent'));
      expect(text.toLowerCase(), contains("don't know"));
      expect(text.toLowerCase(), isNot(contains('quincy')));
    });

    test('clipSnippet strips HTML, links stay out, cap applies', () {
      final clipped = SearchInjection.clipSnippet(
        '<p>The <b>Wandenreich</b> is the Quincy empire.</p>',
      );
      expect(clipped, contains('Wandenreich'));
      expect(clipped, isNot(contains('<p>')));
      expect(clipped, isNot(contains('<b>')));
      final long = SearchInjection.clipSnippet('x' * 2000);
      expect(long.length, lessThanOrEqualTo(kSearchSnippetCharCap));
    });
  });

  group('shouldAdvertiseWebSearch', () {
    test('off, continue, or xml-only → false', () {
      expect(
        shouldAdvertiseWebSearch(
          globalDefault: false,
          continueMode: false,
          toolsUnsupported: false,
        ),
        isFalse,
      );
      expect(
        shouldAdvertiseWebSearch(
          globalDefault: true,
          continueMode: false,
          toolsUnsupported: false,
        ),
        isTrue,
      );
      expect(
        shouldAdvertiseWebSearch(
          globalDefault: true,
          continueMode: true,
          toolsUnsupported: false,
        ),
        isFalse,
      );
      expect(
        shouldAdvertiseWebSearch(
          globalDefault: true,
          continueMode: false,
          toolsUnsupported: true,
        ),
        isFalse,
      );
    });

    test('Porch Life global at check time, Continue still skips', () {
      expect(
        shouldAdvertiseWebSearch(
          globalDefault: true,
          continueMode: false,
          toolsUnsupported: false,
        ),
        isTrue,
        reason: 'flipping Porch Life on must activate already-open chats',
      );
      expect(
        shouldAdvertiseWebSearch(
          globalDefault: true,
          continueMode: true,
          toolsUnsupported: false,
        ),
        isFalse,
        reason: 'Continue still skips search even when the global is on',
      );
    });
  });

  group('isActive is the live Porch Life global', () {
    test('global default at check time enables without seeding', () {
      var global = false;
      final search = WebSearchService(
        getApiKey: () => '',
        getGlobalDefault: () => global,
      );
      expect(search.isActive, isFalse);
      global = true;
      expect(search.isActive, isTrue);
      global = false;
      expect(search.isActive, isFalse);
    });
  });

  group('runWebSearchRound', () {
    late List<Uri> fetched;
    late WebSearchService search;

    setUp(() {
      fetched = [];
      search = WebSearchService(
        getApiKey: () => 'tavily-test-key',
        fetch: (uri, key) async {
          fetched.add(uri);
          return jsonSearch({'Wandenreich': 'the Quincy empire from Bleach'});
        },
      );
    });

    test('advertises web_search and a call runs the HTTP client', () async {
      final llm = _ToolsLlm(
        next: const LlmToolResponse(
          calls: [
            LlmToolCall(
              name: kWebSearchToolName,
              arguments: {'query': 'Wandenreich Bleach'},
            ),
          ],
          text: '',
        ),
      );
      final round = await runWebSearchRound(
        llm: llm,
        params: const GenerationParams(
          prompt: 'starched white wandenreich robes',
        ),
        search: search,
      );
      expect(llm.generateWithToolsCalls, 1);
      expect(jsonNames(llm.lastTools!), contains(kWebSearchToolName));
      expect(fetched, hasLength(1));
      expect(search.httpCalls, 1);
      expect(round.injection, contains('Quincy empire'));
      expect(round.receipt?['query'], 'Wandenreich Bleach');
      expect(round.receipt?['ok'], isTrue);
      expect(round.cannedReply, isNull);
    });

    test(
      'empty search body injects the empty-result fragment, not a wiki',
      () async {
        search = WebSearchService(
          getApiKey: () => 'tavily-test-key',
          fetch: (uri, key) async {
            fetched.add(uri);
            return '{"results":[]}';
          },
        );
        final llm = _ToolsLlm(
          next: const LlmToolResponse(
            calls: [
              LlmToolCall(
                name: kWebSearchToolName,
                arguments: {'query': 'made-up-term-xyz'},
              ),
            ],
            text: '',
          ),
        );
        final round = await runWebSearchRound(
          llm: llm,
          params: const GenerationParams(prompt: 'what is made-up-term-xyz'),
          search: search,
        );
        expect(fetched, hasLength(1));
        expect(round.injection, contains('"made-up-term-xyz"'));
        expect(round.injection!.toLowerCase(), contains('do not invent'));
        expect(round.injection!.toLowerCase(), isNot(contains('wikipedia')));
        expect(round.receipt?['ok'], isFalse);
      },
    );

    test('empty HTTP result is not cached — regen may retry', () async {
      search = WebSearchService(
        getApiKey: () => 'tavily-test-key',
        fetch: (uri, key) async {
          fetched.add(uri);
          return '{"results":[]}';
        },
      );
      final llm = _ToolsLlm(
        next: const LlmToolResponse(
          calls: [
            LlmToolCall(
              name: kWebSearchToolName,
              arguments: {'query': 'San Clemente weather'},
            ),
          ],
          text: '',
        ),
      );
      await runWebSearchRound(
        llm: llm,
        params: const GenerationParams(prompt: 'weather'),
        search: search,
      );
      expect(search.httpCalls, 1);
      search.beginUserSend();
      await runWebSearchRound(
        llm: llm,
        params: const GenerationParams(prompt: 'weather again'),
        search: search,
      );
      expect(
        search.httpCalls,
        2,
        reason:
            'a timeout/401/empty body must not poison the session cache; '
            'regen should be allowed to HTTP again',
      );
    });

    test('regen of the same query is a cache hit — no second HTTP', () async {
      final llm = _ToolsLlm(
        next: const LlmToolResponse(
          calls: [
            LlmToolCall(
              name: kWebSearchToolName,
              arguments: {'query': 'Wandenreich Bleach'},
            ),
          ],
          text: '',
        ),
      );
      await runWebSearchRound(
        llm: llm,
        params: const GenerationParams(prompt: 'robes'),
        search: search,
      );
      expect(search.httpCalls, 1);
      // Regen is a new generate, not a later speaker on the same send —
      // reset the per-send HTTP cap so only the session cache can prevent
      // a second network call.
      search.beginUserSend();
      await runWebSearchRound(
        llm: llm,
        params: const GenerationParams(prompt: 'robes again'),
        search: search,
      );
      expect(search.httpCalls, 1);
      expect(fetched, hasLength(1));
    });

    test('no tool call + text is the canned reply (no HTTP)', () async {
      final llm = _ToolsLlm(
        next: const LlmToolResponse(calls: [], text: 'those robes look sharp.'),
      );
      final round = await runWebSearchRound(
        llm: llm,
        params: const GenerationParams(prompt: 'hello'),
        search: search,
      );
      expect(fetched, isEmpty);
      expect(round.cannedReply, 'those robes look sharp.');
      expect(round.injection, isNull);
      expect(round.receipt, isNull);
    });
  });

  group('kWebSearchTools', () {
    test('schema name and required query', () {
      expect(kWebSearchTools, hasLength(1));
      final fn = kWebSearchTools.first['function'] as Map;
      expect(fn['name'], kWebSearchToolName);
      expect(fn['description'], contains("do not recognize"));
      final required = (fn['parameters'] as Map)['required'] as List;
      expect(required, contains('query'));
    });
  });

  group('path-complete pins', () {
    test('Continue strips the search section and dispatch skips Continue', () {
      final plan = File(
        'lib/services/chat/chat_service_generation_plan.dart',
      ).readAsStringSync();
      expect(plan, contains("plan.section('web_search').text = ''"));
      final req = File(
        'lib/services/chat/chat_service_generation_request.dart',
      ).readAsStringSync();
      expect(req, contains('shouldAdvertiseWebSearch'));
      expect(req, contains('GenerationMode.continue_'));
    });

    test('no slash-command parser or /search chat route exists', () {
      final handler = File(
        'lib/services/chat/chat_command_handler.dart',
      ).readAsStringSync();
      expect(
        handler.contains("'search'") || handler.contains('"search"'),
        isFalse,
      );
      final routesDir = Directory('lib/services/web/routes');
      for (final f in routesDir.listSync().whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final src = f.readAsStringSync();
        expect(
          src.contains('/api/search') || src.contains("'/search'"),
          isFalse,
          reason: '${f.path} must not grow a /search chat route in v1',
        );
      }
    });
  });
}

String jsonSearch(Map<String, String> titleToDesc) {
  return jsonEncode({
    'results': [
      for (final e in titleToDesc.entries)
        {'title': e.key, 'content': e.value, 'url': 'https://example.invalid'},
    ],
  });
}

List<String> jsonNames(List<Map<String, dynamic>> tools) {
  return [
    for (final t in tools) ((t['function'] as Map?)?['name'] as String?) ?? '',
  ];
}
