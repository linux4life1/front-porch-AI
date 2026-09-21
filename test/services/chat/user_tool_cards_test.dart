// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Recipe cards in <library>/tools/: load, skip junk, advertise names,
// HTTP seam (no network), inject before Name: suffix, web_search still
// advertised when enabled.
//
// Proven red before green: missing loader / catalog merge / HTTP body.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/chat/catalog_round.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/user_tool_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_plan.dart';
import 'package:front_porch_ai/services/chat/tool_catalog.dart';
import 'package:front_porch_ai/services/chat/user_tool_cards.dart';
import 'package:front_porch_ai/services/chat/web_search_service.dart';
import 'package:front_porch_ai/services/chat/web_search_tools.dart';
import 'package:front_porch_ai/services/llm_service.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fpai_tools_lib_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Directory toolsDir() => Directory('${root.path}/tools');

  Future<File> writeCard(String filename, Object json) async {
    final dir = toolsDir();
    await dir.create(recursive: true);
    final file = File('${dir.path}/$filename');
    await file.writeAsString(
      json is String ? json : const JsonEncoder.withIndent('  ').convert(json),
    );
    return file;
  }

  Map<String, dynamic> validCard({
    String name = 'search_neokosmos',
    String url = 'https://example.invalid/search',
    bool enabled = true,
  }) {
    return {
      'name': name,
      'description':
          'Look up canon from the Neokosmos wiki. Call when the scene '
          'names a person, place, ritual, or term you are not certain of.',
      'parameters': {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
        },
        'required': ['query'],
      },
      'method': 'POST',
      'url': url,
      'enabled': enabled,
    };
  }

  test('loadUserToolCards creates tools/ and reads a valid card', () async {
    final cards = loadUserToolCards(toolsDir());
    expect(
      toolsDir().existsSync(),
      isTrue,
      reason: 'create the dir if missing',
    );
    expect(cards, isEmpty);

    await writeCard('neokosmos.json', validCard());
    final loaded = loadUserToolCards(toolsDir());
    expect(loaded.map((c) => c.name), ['search_neokosmos']);
    expect(loaded.single.url.toString(), 'https://example.invalid/search');
    expect(loaded.single.method, 'POST');
  });

  test('junk, disabled, and missing-url cards are skipped', () async {
    await writeCard('ok.json', validCard());
    await writeCard('readme.txt', 'not json');
    await writeCard('broken.json', '{');
    await writeCard('array.json', ['nope']);
    await writeCard('no-url.json', validCard()..remove('url'));
    await writeCard('blank-url.json', validCard(url: '  '));
    await writeCard('file-url.json', validCard(url: 'file:///tmp/x'));
    await writeCard('off.json', validCard(name: 'off_tool', enabled: false));
    await writeCard('bad-name.json', validCard(name: 'has a space'));

    final loaded = loadUserToolCards(toolsDir());
    expect(loaded.map((c) => c.name).toList(), ['search_neokosmos']);
  });

  test('catalog advertises card names; web_search still wins when enabled', () {
    final cards = [
      UserToolCard.parse(validCard())!,
      UserToolCard.parse(validCard(name: 'web_search'))!,
    ];
    final withSearch = buildToolCatalog(
      inProcess: [inProcessWebSearchTool()],
      userCards: [for (final c in cards) c.toCatalogTool()],
    );
    expect(withSearch.hasSearch, isTrue);
    expect(
      [
        for (final t in withSearch.toOpenAiTools())
          (t['function'] as Map)['name'],
      ],
      ['web_search', 'search_neokosmos'],
    );
    expect(withSearch.lookup('web_search')!.source, ToolSource.inProcess);
    expect(withSearch.exclusions.single.toolName, 'web_search');

    final cardsOnly = buildToolCatalog(
      inProcess: const [],
      userCards: [cards.first.toCatalogTool()],
    );
    expect(cardsOnly.lookup('search_neokosmos'), isNotNull);
    expect(cardsOnly.hasSearch, isFalse);
  });

  test(
    'HTTP seam posts tool+arguments JSON and does not hit the network',
    () async {
      final card = UserToolCard.parse(validCard())!;
      String? postedBody;
      Uri? postedUrl;
      final result = await executeUserToolCard(
        card,
        {'query': 'Rhea'},
        send:
            ({
              required method,
              required url,
              required headers,
              required body,
            }) async {
              postedUrl = url;
              postedBody = body;
              expect(method, 'POST');
              expect(headers['Content-Type'], contains('json'));
              return const UserToolHttpResult(
                ok: true,
                text: 'Rhea is a priestess.',
              );
            },
      );
      expect(postedUrl.toString(), 'https://example.invalid/search');
      expect(jsonDecode(postedBody!), {
        'tool': 'search_neokosmos',
        'arguments': {'query': 'Rhea'},
      });
      expect(result.ok, isTrue);
      expect(result.text, contains('priestess'));
    },
  );

  test('inject sits before the speaker suffix', () {
    final injection = UserToolInjection.resultFragment(
      'Rhea keeps the lantern.',
    );
    final plan = PromptPlan()
      ..add(id: 'history', text: 'Sam: who is Rhea\n')
      ..add(id: 'web_search', text: '$injection\n')
      ..add(id: 'suffix', text: '\nMara:');
    expect(plan.userText.trimRight(), endsWith('Mara:'));
    expect(
      plan.userText.indexOf('lantern'),
      lessThan(plan.userText.lastIndexOf('Mara:')),
    );
    expect(injection, contains('UNTRUSTED EXTERNAL TOOL DATA'));
  });

  test(
    'catalog round dispatches the user card through the HTTP seam',
    () async {
      final card = UserToolCard.parse(validCard())!;
      final catalog = buildToolCatalog(
        inProcess: [inProcessWebSearchTool()],
        userCards: [card.toCatalogTool()],
      );
      final llm = _ScriptedLlm(
        toolName: 'search_neokosmos',
        args: {'query': 'Rhea'},
      );
      final round = await runCatalogRound(
        llm: llm,
        params: const GenerationParams(prompt: 'Sam: who is Rhea\nMara:'),
        catalog: catalog,
        search: WebSearchService(
          getApiKey: () => '',
          getGlobalDefault: () => true,
        ),
        executeUserTool: (entry, args) async {
          expect(entry.name, 'search_neokosmos');
          expect(args['query'], 'Rhea');
          return const UserToolHttpResult(
            ok: true,
            text: 'Rhea keeps the lantern.',
          );
        },
      );
      expect(round.injection, contains('lantern'));
      expect(round.toolReceipt?['tool'], 'search_neokosmos');
      expect(round.toolReceipt?['ok'], isTrue);
      expect(round.searchReceipt, isNull);
    },
  );

  test('web_search is still advertised and dispatched when enabled', () async {
    final catalog = buildToolCatalog(
      inProcess: [inProcessWebSearchTool()],
      userCards: const [],
    );
    expect(catalog.hasSearch, isTrue);
    final llm = _ScriptedLlm(
      toolName: kWebSearchToolName,
      args: {'query': 'Rhea'},
    );
    final search = WebSearchService(
      getApiKey: () => '',
      getGlobalDefault: () => true,
      sendRequest: (request) async => http.Response(
        jsonEncode({
          'pages': [
            {'title': 'Rhea', 'excerpt': 'A priestess of the porch.'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    final round = await runCatalogRound(
      llm: llm,
      params: const GenerationParams(prompt: 'Sam: who is Rhea\nMara:'),
      catalog: catalog,
      search: search,
    );
    expect(round.searchReceipt?['query'], 'Rhea');
    expect(round.injection, contains('UNTRUSTED EXTERNAL SEARCH DATA'));
  });

  test('user tools advertise only on a first user send', () {
    expect(
      shouldAdvertiseUserTools(
        hasCards: true,
        directUserSend: true,
        continueMode: false,
        toolsUnsupported: false,
      ),
      isTrue,
    );
    expect(
      shouldAdvertiseUserTools(
        hasCards: true,
        directUserSend: true,
        continueMode: true,
        toolsUnsupported: false,
      ),
      isFalse,
    );
    expect(
      shouldAdvertiseUserTools(
        hasCards: true,
        directUserSend: false,
        continueMode: false,
        toolsUnsupported: false,
      ),
      isFalse,
    );
    expect(
      shouldAdvertiseUserTools(
        hasCards: false,
        directUserSend: true,
        continueMode: false,
        toolsUnsupported: false,
      ),
      isFalse,
    );
  });
}

class _ScriptedLlm extends LLMService {
  _ScriptedLlm({this.toolName, this.args = const {}});

  final String? toolName;
  final Map<String, dynamic> args;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    yield '';
  }

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    final names = [
      for (final t in tools) (t['function'] as Map?)?['name'] as String?,
    ];
    final wanted = toolName;
    if (wanted == null || !names.contains(wanted)) {
      return const LlmToolResponse(calls: [], text: 'I already know.');
    }
    return LlmToolResponse(
      calls: [LlmToolCall(name: wanted, arguments: args)],
      text: '',
    );
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedLlm';
}
