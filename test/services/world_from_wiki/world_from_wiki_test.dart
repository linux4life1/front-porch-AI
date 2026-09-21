// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// World from wiki studio: tools gate, climate off, K signed cards → K entries,
// abort does not save, full article not the chat 3500 clip. Chat clerk cap
// stays 3.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/prompt_injection.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';

String _tiddlyFixture() {
  final store = jsonEncode([
    {
      'title': 'Ceolwynn',
      'text': 'A singer of the Alnhama Republic. ' * 200,
      'type': 'text/vnd.tiddlywiki',
    },
    {
      'title': 'Alnhama',
      'text': 'The Alnhama Republic is a coastal city-state.',
      'type': 'text/vnd.tiddlywiki',
    },
    {
      'title': 'River Faith',
      'text': 'The temple of the river faith stands on the quay.',
      'type': 'text/vnd.tiddlywiki',
    },
    {
      'title': '3 On Climate, Wind, and Currents',
      'text': 'A hidden warm current keeps the southern seas livable. ' * 40,
      'type': 'text/vnd.tiddlywiki',
    },
    {
      'title': 'Chapter 1: Ceolwynn',
      'text': 'A draft of the singer on the quay.',
      'type': 'text/vnd.tiddlywiki',
    },
    {
      'title': 'Alnhama (draft)',
      'text': 'Notes toward the coastal city-state.',
      'type': 'text/vnd.tiddlywiki',
    },
    {
      'title': r'$:/core',
      'text': 'system kernel',
      'type': 'text/vnd.tiddlywiki',
    },
    {'title': 'Ceolwynn.png', 'text': 'iVBORw0KGgo=', 'type': 'image/png'},
    {'title': 'Image Gallery', 'text': 'pics', 'type': 'text/vnd.tiddlywiki'},
  ]);
  return '<!doctype html><html><body>'
      '<script class="tiddlywiki-tiddler-store" type="application/json">'
      '$store'
      '</script></body></html>';
}

WikiSearchService _wiki() {
  return WikiSearchService(
    getBaseUrl: () => 'https://quietoak.github.io/NeokosmosWiki/',
    sendRequest: (request) async {
      if (request.url.path.endsWith('api.php')) {
        return http.Response('nope', 404);
      }
      return http.Response(_tiddlyFixture(), 200);
    },
  );
}

List<Map<String, dynamic>> _homemadeCards() => [
  {
    'name': "Baker's Street",
    'keys': ["Baker's Street", 'the street'],
    'role': 'hub',
    'sourceTitles': ['Alnhama'],
  },
  {
    'name': 'The River Faith',
    'keys': ['River Faith'],
    'role': 'hub',
    'sourceTitles': ['River Faith'],
    'group': 'river-faith',
  },
  {
    'name': 'Mira the Scout',
    'keys': ['Mira'],
    'role': 'leaf',
    'sourceTitles': ['Ceolwynn'],
    'group': 'river-faith',
  },
];

class _ToolsLlm extends LLMService {
  int writeCalls = 0;
  int scoutCalls = 0;
  bool returnNull = false;
  bool climateNull = false;
  String lastPrompt = '';

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    lastPrompt = params.prompt;
    if (returnNull) return null;
    final names = [
      for (final t in tools)
        if (t['function'] is Map)
          (t['function'] as Map)['name']?.toString() ?? '',
    ];
    if (names.contains(kWorldScoutToolName)) {
      scoutCalls++;
      return LlmToolResponse(
        calls: [
          LlmToolCall(
            name: kWorldScoutToolName,
            arguments: {'cards': _homemadeCards()},
          ),
        ],
        text: '',
      );
    }
    if (names.contains(kWorldClimateToolName)) {
      writeCalls++;
      if (climateNull) return null;
      return LlmToolResponse(
        calls: [
          LlmToolCall(
            name: kWorldClimateToolName,
            arguments: {
              'displayName': 'Southern current',
              'description': 'Warm sea under the hull.',
              'feel': 'Mild winters, salt air.',
              'diurnalAmplitude': 0.85,
              'seasonLabels': {
                'winter': 'Brief Frost',
                'spring': 'Gulf Rise',
                'summer': 'High Current',
                'autumn': 'Trade Winds',
              },
              'baseTemp': {'winter': 2, 'spring': 3, 'summer': 4, 'autumn': 3},
              'weights': {
                'winter': [32, 22, 16, 12, 12, 4, 2],
                'spring': [38, 22, 12, 10, 14, 4, 0],
                'summer': [48, 20, 8, 6, 10, 8, 0],
                'autumn': [36, 22, 14, 10, 14, 4, 0],
              },
              'loreCards': [
                {
                  'name': 'Warm current',
                  'keys': ['warm current', 'Sea of Neokosmos'],
                  'content':
                      'A hidden warm current keeps the southern seas livable. Lands at this latitude elsewhere are ice. The gulf pulls that heat inland.',
                },
              ],
            },
          ),
        ],
        text: '',
      );
    }
    writeCalls++;
    return LlmToolResponse(
      calls: [
        LlmToolCall(
          name: kWorldLoreBatchToolName,
          arguments: {
            'entries': [
              for (final c in _homemadeCards())
                {
                  'name': c['name'],
                  'keys': c['keys'],
                  'content': 'A baker on the quay keeps the oven lit for them.',
                },
            ],
          },
        ),
      ],
      text: '',
    );
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {}

  @override
  bool get isReady => true;

  @override
  String get backendName => 'test';
}

List<WorldProposedCard> _signed(WorldScoutResult scout, Iterable<int> idx) {
  return [for (final i in idx) scout.proposed[i]];
}

void main() {
  test('chat clerk cap is still 3', () {
    expect(kClerkMaxDispatchRounds, 3);
  });

  test('chat wiki_search still asks for 3 hits', () {
    final uri = mediawikiSearchUri(
      Uri.parse('https://bleach.fandom.com'),
      'aizen',
    );
    expect(uri.queryParameters['srlimit'], '3');
  });

  test('tools-incapable model is blocked', () {
    expect(
      worldFromWikiToolsOk(
        remoteCaps: const ModelApiCapabilities(advertisesTools: false),
        isLocalBackend: false,
      ),
      isFalse,
    );
    expect(
      worldFromWikiToolsOk(
        remoteCaps: const ModelApiCapabilities(
          toolCalling: true,
          advertisesTools: true,
        ),
        isLocalBackend: false,
      ),
      isTrue,
    );
    expect(
      worldFromWikiToolsOk(isLocalBackend: true, modelId: 'mythomax.gguf'),
      isFalse,
    );
    expect(
      worldFromWikiToolsOk(
        isLocalBackend: true,
        modelId: 'Qwen2.5-27B-Instruct.gguf',
      ),
      isTrue,
    );
  });

  test('climate off writes no biome json; recursion is on', () {
    final world = worldFromWikiDraft(
      name: 'The quay',
      description: 'A notebook world.',
      entries: const [],
    );
    expect(world.climateEnabled, isFalse);
    expect(world.biomeJson, isNull);
    expect(world.biomeId, isNull);
    expect(world.lorebook.recursiveScanning, isTrue);
    expect(world.lorebook.scanDepth, 10);
    expect(world.lorebook.tokenBudget, 2800);
    final json = world.toJson();
    expect(json.containsKey('biome_json'), isFalse);
    expect(json.containsKey('biome_id'), isFalse);
    expect(json.containsKey('place_traits'), isFalse);
    expect(json['climate_enabled'], isFalse);
    expect(json['lorebook']['recursive_scanning'], isTrue);
  });

  test('skip \$:/ media galleries', () {
    expect(skipWikiStudioTitle(r'$:/core'), isTrue);
    expect(skipWikiStudioTitle('Ceolwynn.png'), isTrue);
    expect(skipWikiStudioTitle('Image Gallery'), isTrue);
    expect(skipWikiStudioTitle('File:Map.png'), isTrue);
    expect(skipWikiStudioTitle('Ceolwynn'), isFalse);
  });

  test('scan skips junk and logs catalog size', () async {
    final engine = WorldFromWikiEngine(wiki: _wiki(), llm: _ToolsLlm());
    final catalog = await engine.scan();
    expect(catalog.backend, WikiBackend.tiddly);
    expect(catalog.titles, containsAll(['Ceolwynn', 'Alnhama', 'River Faith']));
    expect(catalog.titles, isNot(contains(r'$:/core')));
    expect(catalog.titles, isNot(contains('Ceolwynn.png')));
    expect(catalog.titles, isNot(contains('Image Gallery')));
  });

  test(
    'wiki_page chat clip stays 3500; studio full article is longer',
    () async {
      final wiki = _wiki();
      final clipped = await wiki.getArticle('Ceolwynn');
      expect(clipped.ok, isTrue);
      expect(clipped.snippet.length, lessThanOrEqualTo(kWikiInjectCharCap));
      final full = await wiki.getArticleFull('Ceolwynn');
      expect(full.ok, isTrue);
      expect(full.snippet.length, greaterThan(kWikiInjectCharCap));
    },
  );

  test('scout proposes cards from Tiddly titles, not one per page', () async {
    final llm = _ToolsLlm();
    final engine = WorldFromWikiEngine(wiki: _wiki(), llm: llm);
    final result = await engine.scout(
      worldName: 'The quay',
      premise: 'A coastal republic.',
    );
    expect(result.catalog.titles.length, greaterThan(result.proposed.length));
    expect(result.proposed, hasLength(3));
    expect(llm.scoutCalls, 1);
    expect(llm.writeCalls, 0);
    expect(result.proposed.map((c) => c.group), contains('river-faith'));
    expect(llm.lastPrompt, contains(kWorldScoutPrompt));
  });

  test('K signed cards → K lorebook entries, not wiki title count', () async {
    final llm = _ToolsLlm();
    final engine = WorldFromWikiEngine(wiki: _wiki(), llm: llm);
    final scout = await engine.scout(
      worldName: 'The quay',
      premise: 'A coastal republic.',
    );
    final catalogSize = scout.catalog.titles.length;
    expect(catalogSize, greaterThan(2));
    final entries = await engine.write(
      _signed(scout, [0, 2]),
      worldName: 'The quay',
      premise: 'A coastal republic.',
    );
    expect(entries, hasLength(2));
    expect(llm.writeCalls, 1);
    expect(entries.length, isNot(catalogSize));
    expect(engine.aborted, isFalse);
    expect(entries.every((e) => e.depth == 4), isTrue);
  });

  test('same signed name is not written twice', () async {
    final llm = _ToolsLlm();
    final engine = WorldFromWikiEngine(wiki: _wiki(), llm: llm);
    final scout = await engine.scout(worldName: 'The quay', premise: 'x');
    final entries = await engine.write(
      [scout.proposed.first, scout.proposed.first],
      worldName: 'The quay',
      premise: 'x',
    );
    expect(entries, hasLength(1));
    expect(llm.writeCalls, 1);
  });

  test('abort stops the loop and does not save a World', () async {
    final llm = _ToolsLlm();
    final scout = await WorldFromWikiEngine(
      wiki: _wiki(),
      llm: llm,
    ).scout(worldName: 'The quay', premise: 'x');
    late WorldFromWikiEngine engine;
    engine = WorldFromWikiEngine(
      wiki: _wiki(),
      llm: llm,
      onProgress: (_) => engine.abort(),
    );
    final entries = await engine.write(
      scout.proposed,
      worldName: 'The quay',
      premise: 'x',
    );
    expect(engine.aborted, isTrue);
    expect(entries, isEmpty);
    expect(
      worldFromWikiCanSave(
        aborted: engine.aborted,
        lorebooksOn: true,
        entries: entries,
      ),
      isFalse,
    );
    final leftover = [
      LorebookEntry(name: 'Partial', keys: const ['partial'], content: 'x'),
    ];
    expect(
      worldFromWikiCanSave(aborted: true, lorebooksOn: true, entries: leftover),
      isFalse,
      reason: 'abort refuses save even if a batch already produced cards',
    );
  });

  test('climate on + miss does not enable climate on the World', () async {
    final llm = _ToolsLlm()..climateNull = true;
    final engine = WorldFromWikiEngine(wiki: _wiki(), llm: llm);
    final scout = await engine.scout(worldName: 'The quay', premise: 'x');
    final entries = await engine.write(
      _signed(scout, [0]),
      worldName: 'The quay',
      premise: 'x',
      climateEnabled: true,
    );
    expect(entries, isNotEmpty);
    expect(engine.biome, isNull);
    final world = worldFromWikiDraft(
      name: 'The quay',
      description: 'x',
      entries: entries,
      climateEnabled: true,
      biome: engine.biome,
    );
    expect(world.climateEnabled, isFalse);
    expect(world.biomeId, isNull);
    expect(world.biomeJson, isNull);
  });

  test('tools miss does not dump the article as a lorebook card', () async {
    final llm = _ToolsLlm()..returnNull = true;
    final engine = WorldFromWikiEngine(wiki: _wiki(), llm: llm);
    final scout = await engine.scout(worldName: 'The quay', premise: 'x');
    expect(scout.proposed, isEmpty);
    final entries = await engine.write(
      [
        WorldProposedCard(
          name: 'Mira the Scout',
          keys: const ['Mira'],
          role: WorldCraftRole.leaf,
          sourceTitles: const ['Ceolwynn'],
        ),
      ],
      worldName: 'The quay',
      premise: 'x',
    );
    expect(entries, isEmpty);
  });

  test('lore content is clipped to 330; comma keys split', () {
    final long = 'Word. ' * 80;
    final parsed = parseWorldLoreToolCall({
      'name': 'Allevia',
      'keys': ['Sol Allevia, Order of Sol Allevia, sisters'],
      'content': long,
    })!;
    expect(parsed.content.length, lessThanOrEqualTo(kWorldLoreContentMax));
    expect(
      parsed.keys,
      containsAll(['Sol Allevia', 'Order of Sol Allevia', 'sisters']),
    );
  });
}
