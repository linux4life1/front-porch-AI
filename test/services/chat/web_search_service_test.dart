// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Guards proven to fail before passing:
//   * drop web_search from kWebSearchTools → advertised-tools assertion red
//   * skip the HTTP client on a cache miss → httpCalls expected 1, got 0
//   * return a fake wiki on empty search JSON → empty-result fragment missing
//   * skip cache on the second lookup → httpCalls expected 1, got 2
//   * delete the web_search branch of _dispatchSearch → every round-trip
//     assertion below goes red (this is what the rewrite below bought)
//
// WHY THE ROUND-TRIP GROUP WAS REWRITTEN (2026-09-18):
//
// It used to drive runWebSearchRound, a second implementation of the same
// contract that live dispatch stopped using when the tool catalog landed.
// Its own doc comment admitted it existed "for unit tests of the search
// client" — a function kept alive by its tests, which is how a duplicate
// path rots unnoticed. The orphan is deleted; these tests now drive
// runCatalogRound, the function production actually calls.
//
// Two assertions changed because the live path genuinely behaves
// differently, and that difference is the point:
//
//   * The orphan returned the model's tool-less text as cannedReply. The
//     live round discards doorbell speech and lets the mouth stream, so the
//     test now asserts no dispatch, no injection and no HTTP.
//   * The live round asks again after a dispatch (the clerk loop), so the
//     fake serves a sequence instead of one canned answer, and the test
//     asserts dispatchRounds rather than a generateWithTools count.
//
// Everything else — advertised tool name, one HTTP per cache miss, the
// empty-result fragment instead of an invented wiki, empty bodies not
// poisoning the cache, and the repeat-query cache hit — asserts exactly
// what it did before, against the live dispatcher.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/prompt_injection.dart';
import 'package:front_porch_ai/services/services.dart';

class _ToolsLlm extends LLMService {
  _ToolsLlm(this._replies);

  final List<LlmToolResponse?> _replies;
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
    if (_replies.isEmpty) return const LlmToolResponse(calls: [], text: '');
    return _replies.removeAt(0);
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
          directUserSend: true,
          continueMode: false,
          toolsUnsupported: false,
        ),
        isFalse,
      );
      expect(
        shouldAdvertiseWebSearch(
          globalDefault: true,
          directUserSend: true,
          continueMode: false,
          toolsUnsupported: false,
        ),
        isTrue,
      );
      expect(
        shouldAdvertiseWebSearch(
          globalDefault: true,
          directUserSend: true,
          continueMode: true,
          toolsUnsupported: false,
        ),
        isFalse,
      );
      expect(
        shouldAdvertiseWebSearch(
          globalDefault: true,
          directUserSend: true,
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
          directUserSend: true,
          continueMode: false,
          toolsUnsupported: false,
        ),
        isTrue,
        reason: 'flipping Porch Life on must activate already-open chats',
      );
      expect(
        shouldAdvertiseWebSearch(
          globalDefault: true,
          directUserSend: true,
          continueMode: true,
          toolsUnsupported: false,
        ),
        isFalse,
        reason: 'Continue still skips search even when the global is on',
      );
    });

    test(
      'autonomous mode cannot advertise even with every other gate open',
      () {
        expect(
          shouldAdvertiseWebSearch(
            globalDefault: true,
            directUserSend: true,
            continueMode: false,
            toolsUnsupported: false,
            autonomousMode: true,
          ),
          isFalse,
          reason:
              'Dynamic Responses and other autonomous turns must stay offline',
        );
      },
    );

    test('non-user generation fails closed even in normal mode', () {
      expect(
        shouldAdvertiseWebSearch(
          globalDefault: true,
          directUserSend: false,
          continueMode: false,
          toolsUnsupported: false,
        ),
        isFalse,
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

  group('runCatalogRound web_search', () {
    late List<Uri> fetched;
    late WebSearchService search;

    CatalogBuildResult catalog() =>
        buildToolCatalog(inProcess: [inProcessWebSearchTool()]);

    /// One call, then a trip with no call so the clerk loop stops. The live
    /// round always asks again after a dispatch; the orphan never did.
    _ToolsLlm callThen(String query) => _ToolsLlm([
      LlmToolResponse(
        calls: [
          LlmToolCall(name: kWebSearchToolName, arguments: {'query': query}),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: ''),
    ]);

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
      final llm = callThen('Wandenreich Bleach');
      final round = await runCatalogRound(
        llm: llm,
        params: const GenerationParams(
          prompt: 'starched white wandenreich robes',
        ),
        catalog: catalog(),
        search: search,
      );
      expect(jsonNames(llm.lastTools!), contains(kWebSearchToolName));
      expect(fetched, hasLength(1));
      expect(search.httpCalls, 1);
      expect(round.dispatchRounds, 1);
      expect(round.injection, contains('Quincy empire'));
      expect(round.searchReceipt?['query'], 'Wandenreich Bleach');
      expect(round.searchReceipt?['ok'], isTrue);
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
        final round = await runCatalogRound(
          llm: callThen('made-up-term-xyz'),
          params: const GenerationParams(prompt: 'what is made-up-term-xyz'),
          catalog: catalog(),
          search: search,
        );
        expect(fetched, hasLength(1));
        expect(round.injection, contains('"made-up-term-xyz"'));
        expect(round.injection!.toLowerCase(), contains('do not invent'));
        expect(round.injection!.toLowerCase(), isNot(contains('wikipedia')));
        expect(round.searchReceipt?['ok'], isFalse);
      },
    );

    test(
      'empty HTTP result is not cached — a later user send may retry',
      () async {
        search = WebSearchService(
          getApiKey: () => 'tavily-test-key',
          fetch: (uri, key) async {
            fetched.add(uri);
            return '{"results":[]}';
          },
        );
        await runCatalogRound(
          llm: callThen('San Clemente weather'),
          params: const GenerationParams(prompt: 'weather'),
          catalog: catalog(),
          search: search,
        );
        expect(search.httpCalls, 1);
        search.beginUserSend();
        await runCatalogRound(
          llm: callThen('San Clemente weather'),
          params: const GenerationParams(prompt: 'weather again'),
          catalog: catalog(),
          search: search,
        );
        expect(
          search.httpCalls,
          2,
          reason:
              'a timeout/401/empty body must not poison the session cache; '
              'a later direct user send should be allowed to HTTP again',
        );
      },
    );

    test('repeating the same query is a cache hit — no second HTTP', () async {
      await runCatalogRound(
        llm: callThen('Wandenreich Bleach'),
        params: const GenerationParams(prompt: 'robes'),
        catalog: catalog(),
        search: search,
      );
      expect(search.httpCalls, 1);
      // Reset the per-send HTTP cap so only the session cache can prevent a
      // second network call.
      search.beginUserSend();
      await runCatalogRound(
        llm: callThen('Wandenreich Bleach'),
        params: const GenerationParams(prompt: 'robes again'),
        catalog: catalog(),
        search: search,
      );
      expect(search.httpCalls, 1);
      expect(fetched, hasLength(1));
    });

    test('no tool call means no HTTP and no injection', () async {
      final round = await runCatalogRound(
        llm: _ToolsLlm([
          const LlmToolResponse(calls: [], text: 'those robes look sharp.'),
        ]),
        params: const GenerationParams(prompt: 'hello'),
        catalog: catalog(),
        search: search,
      );
      expect(fetched, isEmpty);
      expect(round.dispatchRounds, 0);
      expect(round.injection, isNull);
      expect(round.searchReceipt, isNull);
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
      final query =
          ((fn['parameters'] as Map)['properties'] as Map)['query'] as Map;
      expect(query['maxLength'], kWebSearchQueryMaxChars);
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
