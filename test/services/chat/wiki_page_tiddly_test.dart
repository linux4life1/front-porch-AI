// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// TiddlyWiki adapter + wiki_page. Same picker as Fandom; two backends.
// Proven red before green: search returned $:/core; wiki_page skipped
// parse URI on Fandom; catalog omitted wiki_page; junk URL still HTTP;
// GH Pages path stripped to origin so Neokosmos fetched the user site.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/prompt_injection.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/storage/settings/web_search_settings.dart';

String _tiddlyFixture({
  String ceolwynnText = 'A singer of the Alnhama Republic.',
}) {
  final store = jsonEncode([
    {'title': 'Ceolwynn', 'text': ceolwynnText, 'type': 'text/vnd.tiddlywiki'},
    {
      'title': '\$:/core',
      'text': 'system kernel must not appear in search',
      'type': 'text/vnd.tiddlywiki',
    },
    {'title': 'Ceolwynn.png', 'text': 'iVBORw0KGgo=', 'type': 'image/png'},
    {'title': 'theme.mp3', 'text': 'binary-audio', 'type': 'audio/mpeg'},
  ]);
  return '<!doctype html><html><body>'
      '<script class="tiddlywiki-tiddler-store" type="application/json">'
      '$store'
      '</script></body></html>';
}

class _ToolsLlm extends LLMService {
  _ToolsLlm({this.next});

  LlmToolResponse? next;
  List<Map<String, dynamic>>? lastTools;

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
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
  group('parseTiddlyStoreHtml', () {
    test('search finds Ceolwynn and skips \$:/ system tiddlers', () {
      final index = parseTiddlyStoreHtml(_tiddlyFixture());
      expect(index, isNotNull);
      expect(index!.skippedSystem, 1);
      expect(index.tiddlers.any((t) => t.title.startsWith(r'$:/')), isFalse);
      final hits = searchTiddlyIndex(index, 'Ceolwynn');
      expect(hits.map((t) => t.title), ['Ceolwynn']);
      expect(hits.single.text, contains('Alnhama'));
      expect(
        formatTiddlySearchHits(hits).toLowerCase(),
        isNot(contains('system kernel')),
      );
    });
  });

  group('canonicalize keeps Tiddly path', () {
    test('Neokosmos GH Pages path is not stripped to origin', () {
      expect(
        canonicalizeWikiUrl('https://quietoak.github.io/NeokosmosWiki/'),
        'https://quietoak.github.io/NeokosmosWiki/',
      );
      expect(
        parseWikiBaseUrl('https://quietoak.github.io/NeokosmosWiki/')?.path,
        '/NeokosmosWiki/',
      );
    });

    test('Fandom article URLs still canonicalize to origin', () {
      expect(
        canonicalizeWikiUrl('https://bleach.fandom.com/wiki/Sōsuke_Aizen'),
        'https://bleach.fandom.com',
      );
    });
  });

  group('WikiSearchService Tiddly', () {
    test('search hits Ceolwynn, skips \$:/, caches the notebook', () async {
      final fetched = <Uri>[];
      final wiki = WikiSearchService(
        getBaseUrl: () => 'https://quietoak.github.io/NeokosmosWiki/',
        sendRequest: (request) async {
          fetched.add(request.url);
          expect(request.headers['User-Agent'], isNotEmpty);
          if (request.url.path.endsWith('api.php')) {
            return http.Response('nope', 404);
          }
          return http.Response(_tiddlyFixture(), 200);
        },
      );
      final hit = await wiki.lookup('Ceolwynn');
      expect(hit.ok, isTrue);
      expect(hit.snippet, contains('Ceolwynn'));
      expect(hit.snippet, contains('Alnhama'));
      expect(hit.snippet.toLowerCase(), isNot(contains('system kernel')));
      expect(
        fetched.where((u) => u.path.contains('NeokosmosWiki')),
        isNotEmpty,
      );

      final again = await wiki.lookup('Ceolwynn');
      expect(again.ok, isTrue);
      expect(again.fromCache, isTrue);
      expect(
        fetched.where((u) => !u.path.endsWith('api.php')).length,
        1,
        reason: 'tiddler index is session-cached',
      );
    });

    test('wiki_page returns that tiddler clipped', () async {
      const long = 'A singer of the Alnhama Republic. ';
      final body = long * 200; // well over kWikiInjectCharCap
      final wiki = WikiSearchService(
        getBaseUrl: () => 'https://quietoak.github.io/NeokosmosWiki/',
        sendRequest: (request) async {
          if (request.url.path.endsWith('api.php')) {
            return http.Response('nope', 404);
          }
          return http.Response(_tiddlyFixture(ceolwynnText: body), 200);
        },
      );
      final page = await wiki.getArticle('Ceolwynn');
      expect(page.ok, isTrue);
      expect(page.snippet, startsWith('Ceolwynn'));
      expect(page.snippet, contains('Alnhama'));
      expect(page.snippet.length, lessThanOrEqualTo(kWikiInjectCharCap));
      expect(page.snippet, isNot(contains('system kernel')));
    });
  });

  group('MediaWiki wiki_page', () {
    test('Fandom wiki_page uses parse URI, not search', () async {
      final fetched = <Uri>[];
      final wiki = WikiSearchService(
        getBaseUrl: () => 'https://bleach.fandom.com/wiki/Aizen',
        sendRequest: (request) async {
          fetched.add(request.url);
          expect(request.headers['User-Agent'], isNotEmpty);
          if (request.url.queryParameters['action'] == 'parse') {
            return http.Response(
              jsonEncode({
                'parse': {
                  'title': 'Sosuke Aizen',
                  'text': {'*': '<p>Kyoka Suigetsu, his shikai.</p>'},
                },
              }),
              200,
            );
          }
          return http.Response('unexpected ${request.url}', 500);
        },
      );
      final page = await wiki.getArticle('Sosuke Aizen');
      expect(page.ok, isTrue);
      expect(page.snippet, contains('Kyoka Suigetsu'));
      expect(fetched, hasLength(1));
      expect(fetched.single.path, '/api.php');
      expect(fetched.single.queryParameters['action'], 'parse');
      expect(fetched.single.queryParameters['page'], 'Sosuke Aizen');
    });
  });

  group('junk URL', () {
    test('wiki_search and wiki_page do not HTTP', () async {
      var calls = 0;
      final wiki = WikiSearchService(
        getBaseUrl: () => 'not a url',
        sendRequest: (request) async {
          calls++;
          return http.Response('nope', 200);
        },
      );
      final search = await wiki.lookup('Ceolwynn');
      final page = await wiki.getArticle('Ceolwynn');
      expect(calls, 0);
      expect(search.httpAttempted, isFalse);
      expect(page.httpAttempted, isFalse);
      expect(search.ok, isFalse);
      expect(page.ok, isFalse);
    });
  });

  group('catalog wiki_page', () {
    test('advertises wiki_page when URL set, not when empty', () {
      expect(
        shouldAdvertiseWikiSearch(
          wikiUrl: 'https://bleach.fandom.com/',
          directUserSend: true,
          continueMode: false,
          toolsUnsupported: false,
        ),
        isTrue,
      );
      final on = buildToolCatalog(
        inProcess: [inProcessWikiSearchTool(), inProcessWikiPageTool()],
      );
      expect(_toolNames(on.toOpenAiTools()), [
        kWikiSearchToolName,
        kWikiPageToolName,
      ]);
      expect(on.lookup(kWikiPageToolName), isNotNull);

      expect(
        shouldAdvertiseWikiSearch(
          wikiUrl: '',
          directUserSend: true,
          continueMode: false,
          toolsUnsupported: false,
        ),
        isFalse,
      );
      final off = buildToolCatalog(
        inProcess: [
          if (shouldAdvertiseWikiSearch(
            wikiUrl: '',
            directUserSend: true,
            continueMode: false,
            toolsUnsupported: false,
          ))
            inProcessWikiPageTool(),
        ],
      );
      expect(off.lookup(kWikiPageToolName), isNull);
      expect(off.lookup(kWikiSearchToolName), isNull);
    });

    test('generation_request advertises wiki_page with wiki_search', () {
      final request = File(
        'lib/services/chat/chat_service_generation_request.dart',
      ).readAsStringSync();
      expect(request, contains('inProcessWikiPageTool'));
      expect(request, contains('inProcessWikiSearchTool'));
    });

    test(
      'runCatalogRound wiki_page injects the article, not UNTRUSTED',
      () async {
        final wiki = WikiSearchService(
          getBaseUrl: () => 'https://quietoak.github.io/NeokosmosWiki/',
          sendRequest: (request) async {
            if (request.url.path.endsWith('api.php')) {
              return http.Response('nope', 404);
            }
            return http.Response(_tiddlyFixture(), 200);
          },
        );
        final llm = _ToolsLlm(
          next: const LlmToolResponse(
            calls: [
              LlmToolCall(
                name: kWikiPageToolName,
                arguments: {'title': 'Ceolwynn'},
              ),
            ],
            text: '',
          ),
        );
        final round = await runCatalogRound(
          llm: llm,
          params: const GenerationParams(prompt: 'rain on the porch'),
          catalog: buildToolCatalog(
            inProcess: [inProcessWikiSearchTool(), inProcessWikiPageTool()],
          ),
          search: WebSearchService(getApiKey: () => ''),
          wiki: wiki,
        );
        expect(_toolNames(llm.lastTools!), contains(kWikiPageToolName));
        expect(round.injection, contains('Alnhama'));
        expect(round.injection, contains("this chat's wiki"));
        expect(round.injection!.toLowerCase(), isNot(contains('untrusted')));
        expect(round.wikiReceipt?['ok'], isTrue);
      },
    );
  });
}
