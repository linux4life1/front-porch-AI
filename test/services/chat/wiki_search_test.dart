// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Built-in wiki_search: this chat's MediaWiki/Fandom host, not Google.
// Proven red before green: missing tool / Wikipedia host / junk URL /
// inject-after-suffix / Continue still advertising.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/chat/catalog_round.dart';
import 'package:front_porch_ai/services/chat/mediawiki_search.dart';
import 'package:front_porch_ai/services/chat/prompt_plan.dart';
import 'package:front_porch_ai/services/chat/tool_catalog.dart';
import 'package:front_porch_ai/services/chat/web_search_service.dart';
import 'package:front_porch_ai/services/chat/web_search_tools.dart';
import 'package:front_porch_ai/services/chat/wiki_search_service.dart';
import 'package:front_porch_ai/services/chat/wiki_search_tools.dart';
import 'package:front_porch_ai/services/llm_service.dart';

class _ToolsLlm extends LLMService {
  _ToolsLlm({this.next});

  LlmToolResponse? next;
  List<Map<String, dynamic>>? lastTools;
  int generateWithToolsCalls = 0;

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
    yield 'streamed reply';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'test';
}

List<String> _toolNames(List<Map<String, dynamic>> tools) => [
  for (final t in tools) ((t['function'] as Map?)?['name'] as String?) ?? '',
];

void main() {
  group('parseWikiBaseUrl', () {
    test('empty and junk are skipped', () {
      expect(parseWikiBaseUrl(''), isNull);
      expect(parseWikiBaseUrl('   '), isNull);
      expect(parseWikiBaseUrl('not a url'), isNull);
      expect(parseWikiBaseUrl('ftp://bleach.fandom.com/'), isNull);
      expect(parseWikiBaseUrl('javascript:alert(1)'), isNull);
      expect(parseWikiBaseUrl('http://localhost/wiki'), isNull);
    });

    test('pasted MediaWiki / Fandom / Wikipedia URLs keep the host', () {
      expect(
        parseWikiBaseUrl('https://bleach.fandom.com/')?.host,
        'bleach.fandom.com',
      );
      expect(
        parseWikiBaseUrl('https://bleach.fandom.com/wiki/Sōsuke_Aizen')?.host,
        'bleach.fandom.com',
      );
      expect(parseWikiBaseUrl('bleach.fandom.com')?.host, 'bleach.fandom.com');
      expect(
        parseWikiBaseUrl('https://en.wikipedia.org/wiki/Sosuke_Aizen')?.host,
        'en.wikipedia.org',
      );
    });
  });

  group('mediawikiSearchUri', () {
    test('Fandom host uses api.php on that host', () {
      final base = parseWikiBaseUrl('https://bleach.fandom.com/wiki/Aizen')!;
      final uri = mediawikiSearchUri(base, 'Sosuke Aizen shikai');
      expect(uri.host, 'bleach.fandom.com');
      expect(uri.path, '/api.php');
      expect(uri.queryParameters['srsearch'], 'Sosuke Aizen shikai');
    });

    test('Wikipedia host keeps REST search on wikipedia.org', () {
      final base = parseWikiBaseUrl('https://en.wikipedia.org/wiki/X')!;
      final uri = mediawikiSearchUri(base, 'Kyoka Suigetsu');
      expect(uri.host, 'en.wikipedia.org');
      expect(uri.path, '/w/rest.php/v1/search/page');
      expect(uri.queryParameters['q'], 'Kyoka Suigetsu');
      expect(
        uri.replace(queryParameters: {}).toString(),
        startsWith(kWikipediaSearchEndpoint),
      );
    });
  });

  group('shouldAdvertiseWikiSearch', () {
    test('empty or junk URL stays off the menu', () {
      expect(
        shouldAdvertiseWikiSearch(
          wikiUrl: '',
          directUserSend: true,
          continueMode: false,
          toolsUnsupported: false,
        ),
        isFalse,
      );
      expect(
        shouldAdvertiseWikiSearch(
          wikiUrl: 'not a url',
          directUserSend: true,
          continueMode: false,
          toolsUnsupported: false,
        ),
        isFalse,
      );
    });

    test('valid URL advertises on a direct user send only', () {
      const url = 'https://bleach.fandom.com/';
      expect(
        shouldAdvertiseWikiSearch(
          wikiUrl: url,
          directUserSend: true,
          continueMode: false,
          toolsUnsupported: false,
        ),
        isTrue,
      );
      expect(
        shouldAdvertiseWikiSearch(
          wikiUrl: url,
          directUserSend: true,
          continueMode: true,
          toolsUnsupported: false,
        ),
        isFalse,
        reason: 'Continue stays offline, same gate as web_search',
      );
      expect(
        shouldAdvertiseWikiSearch(
          wikiUrl: url,
          directUserSend: false,
          continueMode: false,
          toolsUnsupported: false,
        ),
        isFalse,
      );
      expect(
        shouldAdvertiseWikiSearch(
          wikiUrl: url,
          directUserSend: true,
          continueMode: false,
          toolsUnsupported: true,
        ),
        isFalse,
      );
      expect(
        shouldAdvertiseWikiSearch(
          wikiUrl: url,
          directUserSend: true,
          continueMode: false,
          toolsUnsupported: false,
          autonomousMode: true,
        ),
        isFalse,
        reason: 'Dynamic Responses stay offline',
      );
    });
  });

  group('catalog', () {
    test('wiki_search joins web_search on the same round when URL is set', () {
      final catalog = buildToolCatalog(
        inProcess: [inProcessWebSearchTool(), inProcessWikiSearchTool()],
      );
      expect(_toolNames(catalog.toOpenAiTools()), [
        kWebSearchToolName,
        kWikiSearchToolName,
      ]);
      final wiki = catalog.lookup(kWikiSearchToolName)!;
      expect(wiki.description.toLowerCase(), contains('fiction'));
      expect(wiki.description.toLowerCase(), contains('lore'));
      expect(wiki.description.toLowerCase(), contains('never invent'));
    });

    test('empty wiki URL omits wiki_search; web_search can still show', () {
      final catalog = buildToolCatalog(inProcess: [inProcessWebSearchTool()]);
      expect(catalog.hasSearch, isTrue);
      expect(catalog.lookup(kWikiSearchToolName), isNull);
    });
  });

  group('WikiSearchService.lookup', () {
    test('records the pasted host and skips junk', () async {
      final fetched = <Uri>[];
      final wiki = WikiSearchService(
        getBaseUrl: () => 'https://bleach.fandom.com/wiki/Aizen',
        sendRequest: (request) async {
          fetched.add(request.url);
          if (request.url.queryParameters['action'] == 'parse') {
            return http.Response(
              jsonEncode({
                'parse': {
                  'title': 'Sosuke Aizen',
                  'text': {
                    '*':
                        '<p>Kyoka Suigetsu, his shikai. Complete Hypnosis.</p>',
                  },
                },
              }),
              200,
            );
          }
          if (request.url.queryParameters['prop'] == 'extracts') {
            return http.Response(
              jsonEncode({
                'query': {
                  'pages': {
                    '1': {
                      'title': 'Sosuke Aizen',
                      'extract':
                          'Kyoka Suigetsu, his shikai. Complete Hypnosis.',
                    },
                  },
                },
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'query': {
                'search': [
                  {
                    'title': 'Sosuke Aizen',
                    'snippet': 'Kyoka Suigetsu, his shikai',
                  },
                ],
              },
            }),
            200,
          );
        },
      );
      final hit = await wiki.lookup('Sosuke Aizen shikai');
      expect(fetched, hasLength(2));
      expect(fetched.first.host, 'bleach.fandom.com');
      expect(fetched.first.queryParameters['list'], 'search');
      expect(fetched.last.queryParameters['action'], 'parse');
      expect(hit.ok, isTrue);
      expect(hit.snippet, contains('Kyoka Suigetsu'));

      final junk = WikiSearchService(
        getBaseUrl: () => 'not a url',
        sendRequest: (request) async {
          fetched.add(request.url);
          return http.Response('nope', 200);
        },
      );
      final miss = await junk.lookup('Aizen');
      expect(fetched, hasLength(2), reason: 'junk URL must not HTTP');
      expect(miss.ok, isFalse);
      expect(miss.httpAttempted, isFalse);
    });

    test('oversized body is an honest miss', () async {
      final wiki = WikiSearchService(
        getBaseUrl: () => 'https://bleach.fandom.com/',
        sendRequest: (request) async {
          return http.Response('x' * (kMediaWikiMaxBodyBytes + 8), 200);
        },
      );
      final miss = await wiki.lookup('Aizen');
      expect(miss.ok, isFalse);
      expect(miss.httpAttempted, isTrue);
    });
  });

  group('runCatalogRound wiki_search', () {
    test('injects before suffix and stamps a wiki receipt', () async {
      final wiki = WikiSearchService(
        getBaseUrl: () => 'https://bleach.fandom.com/',
        sendRequest: (request) async {
          if (request.url.queryParameters['action'] == 'parse') {
            return http.Response(
              jsonEncode({
                'parse': {
                  'title': 'Kyoka Suigetsu',
                  'text': {'*': '<p>complete hypnosis</p>'},
                },
              }),
              200,
            );
          }
          if (request.url.queryParameters['prop'] == 'extracts') {
            return http.Response(
              jsonEncode({
                'query': {
                  'pages': {
                    '1': {
                      'title': 'Kyoka Suigetsu',
                      'extract': 'complete hypnosis',
                    },
                  },
                },
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'query': {
                'search': [
                  {'title': 'Kyoka Suigetsu', 'snippet': 'complete hypnosis'},
                ],
              },
            }),
            200,
          );
        },
      );
      final llm = _ToolsLlm(
        next: const LlmToolResponse(
          calls: [
            LlmToolCall(
              name: kWikiSearchToolName,
              arguments: {'query': 'Aizen shikai'},
            ),
          ],
          text: '',
        ),
      );
      final catalog = buildToolCatalog(
        inProcess: [inProcessWebSearchTool(), inProcessWikiSearchTool()],
      );
      final round = await runCatalogRound(
        llm: llm,
        params: const GenerationParams(prompt: 'rain on the porch'),
        catalog: catalog,
        search: WebSearchService(getApiKey: () => ''),
        wiki: wiki,
      );
      expect(_toolNames(llm.lastTools!), contains(kWikiSearchToolName));
      expect(round.injection, contains('complete hypnosis'));
      expect(round.injection, contains("this chat's wiki"));
      expect(round.injection!.toLowerCase(), isNot(contains('untrusted')));
      expect(round.searchReceipt?['source'], 'wiki');
      expect(round.searchReceipt?['query'], 'Aizen shikai');
      expect(round.searchReceipt?['ok'], isTrue);
      expect(
        (round.searchReceipt?['url'] as String?) ?? '',
        contains('bleach.fandom.com'),
      );
      expect(round.wikiReceipt?['source'], 'wiki');

      final plan = PromptPlan()
        ..add(id: 'history', text: 'Ash: rain on the porch\n')
        ..add(id: 'web_search', text: '${round.injection}\n')
        ..add(id: 'suffix', text: '\nHinamori:');
      expect(plan.userText.trimRight(), endsWith('Hinamori:'));
      expect(
        plan.userText.indexOf('complete hypnosis'),
        lessThan(plan.userText.lastIndexOf('Hinamori:')),
      );
    });

    test('failed lookup injects the honest miss, not a fake page', () async {
      final wiki = WikiSearchService(
        getBaseUrl: () => 'https://bleach.fandom.com/',
        sendRequest: (request) async =>
            http.Response('{"query":{"search":[]}}', 200),
      );
      final llm = _ToolsLlm(
        next: const LlmToolResponse(
          calls: [
            LlmToolCall(
              name: kWikiSearchToolName,
              arguments: {'query': 'made-up-term-xyz'},
            ),
          ],
          text: '',
        ),
      );
      final round = await runCatalogRound(
        llm: llm,
        params: const GenerationParams(prompt: '???'),
        catalog: buildToolCatalog(inProcess: [inProcessWikiSearchTool()]),
        search: WebSearchService(getApiKey: () => ''),
        wiki: wiki,
      );
      expect(round.injection!.toLowerCase(), contains('do not invent'));
      expect(round.searchReceipt?['ok'], isFalse);
      expect(round.searchReceipt?['source'], 'wiki');
    });
  });
}
