// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Clerk loop on the catalog mouth: she is the doorbell; extra
// generateWithTools trips fetch books and never become the bubble.
// Doorbell + clerk use the eval side lane (not user max-gen / thinking).
//
// Proven red before green:
//   * one-shot catalog (no follow-up) → always-tool LLM dispatches 1, not 3
//   * clerk/doorbell inheriting mouth maxLength or temperature
//   * 4th dispatch after the cap
//   * Continue still advertising in generation_request

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/chat/catalog_clerk.dart';
import 'package:front_porch_ai/services/chat/catalog_round.dart';
import 'package:front_porch_ai/services/chat/eval_lane_params.dart';
import 'package:front_porch_ai/services/chat/tool_catalog.dart';
import 'package:front_porch_ai/services/chat/web_search_service.dart';
import 'package:front_porch_ai/services/chat/wiki_search_service.dart';
import 'package:front_porch_ai/services/chat/wiki_search_tools.dart';
import 'package:front_porch_ai/services/llm_service.dart';

class _SeqLlm extends LLMService {
  _SeqLlm(this.script);

  final List<LlmToolResponse?> script;
  int generateWithToolsCalls = 0;
  final paramsSeen = <GenerationParams>[];

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    generateWithToolsCalls++;
    paramsSeen.add(params);
    if (generateWithToolsCalls > script.length) {
      return const LlmToolResponse(calls: [], text: 'clerk leftover');
    }
    return script[generateWithToolsCalls - 1];
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    yield 'streamed reply';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'clerk-test';
}

class _AlwaysWikiLlm extends LLMService {
  int generateWithToolsCalls = 0;
  final queries = <String>[];

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    generateWithToolsCalls++;
    final q = 'query-$generateWithToolsCalls';
    queries.add(q);
    return LlmToolResponse(
      calls: [
        LlmToolCall(name: kWikiSearchToolName, arguments: {'query': q}),
      ],
      text: 'I would speak in character — clerk must ignore this',
    );
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    yield 'streamed reply';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'always-wiki';
}

WikiSearchService _wiki(List<Uri> fetched) {
  return WikiSearchService(
    getBaseUrl: () => 'https://bleach.fandom.com/',
    sendRequest: (request) async {
      fetched.add(request.url);
      if (request.url.queryParameters['action'] == 'parse') {
        final page = request.url.queryParameters['page'] ?? 'Page';
        return http.Response(
          jsonEncode({
            'parse': {
              'title': page,
              'text': {'*': '<p>$page clip from the wiki.</p>'},
            },
          }),
          200,
        );
      }
      if (request.url.queryParameters['list'] == 'search') {
        final q = request.url.queryParameters['srsearch'] ?? 'X';
        return http.Response(
          jsonEncode({
            'query': {
              'search': [
                {'title': q, 'snippet': '$q blurb'},
              ],
            },
          }),
          200,
        );
      }
      return http.Response('{"query":{"search":[]}}', 200);
    },
  );
}

CatalogBuildResult _wikiCatalog() =>
    buildToolCatalog(inProcess: [inProcessWikiSearchTool()]);

WebSearchService _deadSearch() => WebSearchService(getApiKey: () => '');

void _expectEvalLane(GenerationParams p) {
  expect(p.maxLength, kEvalLaneMaxLength);
  expect(p.minLength, 0);
  expect(p.temperature, kEvalLaneTemperature);
  expect(p.topP, kEvalLaneTopP);
  expect(p.repeatPenalty, kEvalLaneRepeatPenalty);
  expect(p.xtcProbability, 0.0);
  expect(p.reasoningEnabled, isFalse);
  expect(p.reasoningMaxTokens, 0);
  expect(p.salvageReasoning, isFalse);
  expect(p.stopSequences, isEmpty);
}

void main() {
  test('cap is three advertised dispatches', () {
    expect(kClerkMaxDispatchRounds, 3);
  });

  test('side lane matches fireLLMEval numbers, not the mouth settings', () {
    const mouth = GenerationParams(
      prompt: 'Ash: hi\nHinamori:',
      maxLength: 32000,
      minLength: 80,
      temperature: 1.2,
      topP: 0.95,
      repeatPenalty: 1.4,
      reasoningEnabled: true,
      reasoningMaxTokens: 8000,
      salvageReasoning: true,
      stopSequences: ['Hinamori:'],
    );
    final doorbell = clerkSideLaneParams(mouth);
    _expectEvalLane(doorbell);
    expect(doorbell.prompt, mouth.prompt);
    expect(doorbell.maxLength, isNot(mouth.maxLength));
    expect(doorbell.temperature, isNot(mouth.temperature));
    final follow = clerkFollowupParams(mouth, [
      {'role': 'user', 'content': mouth.prompt},
    ]);
    _expectEvalLane(follow);
    expect(follow.chatMessages, isNotNull);
  });

  test('no tool call is one generateWithTools and no clerk extras', () async {
    final fetched = <Uri>[];
    final llm = _SeqLlm([const LlmToolResponse(calls: [], text: 'Hey there.')]);
    final round = await runCatalogRound(
      llm: llm,
      params: const GenerationParams(
        prompt: 'Ash: hi\nHinamori:',
        maxLength: 32000,
        temperature: 1.2,
        reasoningEnabled: true,
        reasoningMaxTokens: 8000,
      ),
      catalog: _wikiCatalog(),
      search: _deadSearch(),
      wiki: _wiki(fetched),
    );
    expect(llm.generateWithToolsCalls, 1);
    expect(round.dispatchRounds, 0);
    expect(round.injection, isNull);
    expect(fetched, isEmpty);
    _expectEvalLane(llm.paramsSeen.single);
    expect(llm.paramsSeen.single.chatMessages, isNotNull);
  });

  test(
    'one tool call dispatches, clerk checks, then mouth has no voice',
    () async {
      final fetched = <Uri>[];
      final llm = _SeqLlm([
        const LlmToolResponse(
          calls: [
            LlmToolCall(
              name: kWikiSearchToolName,
              arguments: {'query': 'Aizen shikai'},
            ),
          ],
          text: '',
        ),
        const LlmToolResponse(calls: [], text: 'Clerk must not be the bubble.'),
      ]);
      final round = await runCatalogRound(
        llm: llm,
        params: const GenerationParams(prompt: 'Ash: rain\nHinamori:'),
        catalog: _wikiCatalog(),
        search: _deadSearch(),
        wiki: _wiki(fetched),
      );
      expect(round.dispatchRounds, 1);
      expect(llm.generateWithToolsCalls, 2);
      expect(round.injection, contains('Aizen shikai'));
      _expectEvalLane(llm.paramsSeen[0]);
      _expectEvalLane(llm.paramsSeen[1]);
      expect(
        fetched.any((u) => u.queryParameters['action'] == 'parse'),
        isTrue,
        reason: 'search hit must auto-open wiki_page',
      );
      expect(round.injection!.toLowerCase(), isNot(contains('untrusted')));
      expect(round.injection, contains("this chat's wiki"));
      expect(llm.paramsSeen[1].chatMessages, isNotNull);
      final roles = [
        for (final m in llm.paramsSeen[1].chatMessages!) m['role'],
      ];
      expect(roles, containsAllInOrder(['user', 'assistant', 'tool']));
      expect(llm.paramsSeen[1].reasoningEnabled, isFalse);
    },
  );

  test('two wiki calls collate then stop when she is done', () async {
    final fetched = <Uri>[];
    final llm = _SeqLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(name: kWikiSearchToolName, arguments: {'query': 'Aizen'}),
        ],
        text: '',
      ),
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: kWikiSearchToolName,
            arguments: {'query': 'Hinamori'},
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'would have been voice'),
    ]);
    final round = await runCatalogRound(
      llm: llm,
      params: const GenerationParams(prompt: 'Ash: names\nHinamori:'),
      catalog: _wikiCatalog(),
      search: _deadSearch(),
      wiki: _wiki(fetched),
    );
    expect(round.dispatchRounds, 2);
    expect(llm.generateWithToolsCalls, 3);
    expect(round.injection, contains('Aizen'));
    expect(round.injection, contains('Hinamori'));
    for (final p in llm.paramsSeen) {
      _expectEvalLane(p);
    }
  });

  test('the same tool+args twice is not a second book', () async {
    final fetched = <Uri>[];
    final llm = _SeqLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(name: kWikiSearchToolName, arguments: {'query': 'Aizen'}),
        ],
        text: '',
      ),
      const LlmToolResponse(
        calls: [
          LlmToolCall(name: kWikiSearchToolName, arguments: {'query': 'Aizen'}),
        ],
        text: '',
      ),
      const LlmToolResponse(
        calls: [
          LlmToolCall(name: kWikiSearchToolName, arguments: {'query': 'Aizen'}),
        ],
        text: '',
      ),
    ]);
    final round = await runCatalogRound(
      llm: llm,
      params: const GenerationParams(prompt: 'Ash: again\nHinamori:'),
      catalog: _wikiCatalog(),
      search: _deadSearch(),
      wiki: _wiki(fetched),
    );
    expect(round.dispatchRounds, 1);
    expect(llm.generateWithToolsCalls, 2);
    expect(
      fetched.where((u) => u.queryParameters['list'] == 'search').length,
      1,
    );
  });

  test('always-ringing model stops at three dispatches', () async {
    final fetched = <Uri>[];
    final llm = _AlwaysWikiLlm();
    final round = await runCatalogRound(
      llm: llm,
      params: const GenerationParams(prompt: 'Ash: lore\nHinamori:'),
      catalog: _wikiCatalog(),
      search: _deadSearch(),
      wiki: _wiki(fetched),
    );
    expect(kClerkMaxDispatchRounds, 3);
    expect(round.dispatchRounds, 3);
    expect(llm.generateWithToolsCalls, 3);
    expect(llm.queries, ['query-1', 'query-2', 'query-3']);
    expect(round.injection, contains('query-1'));
    expect(round.injection, contains('query-2'));
    expect(round.injection, contains('query-3'));
    final searches = fetched
        .where((u) => u.queryParameters['list'] == 'search')
        .length;
    expect(searches, 3);
  });
}
