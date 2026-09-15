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

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/chat/catalog_clerk.dart';
import 'package:front_porch_ai/services/chat/mediawiki_search.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/prompt_injection.dart';
import 'package:front_porch_ai/services/chat/tool_catalog.dart';
import 'package:front_porch_ai/services/chat/user_tool_cards.dart';
import 'package:front_porch_ai/services/chat/web_search_service.dart';
import 'package:front_porch_ai/services/chat/web_search_tools.dart';
import 'package:front_porch_ai/services/chat/wiki_search_service.dart';
import 'package:front_porch_ai/services/chat/wiki_search_tools.dart';
import 'package:front_porch_ai/services/llm_service.dart';

/// Outcome of the catalog tools trip (doorbell plus optional clerk loop).
class CatalogRound {
  const CatalogRound({
    this.injection,
    this.searchReceipt,
    this.wikiReceipt,
    this.toolReceipt,
    this.spokenText,
    this.scrap = '',
    this.dispatchRounds = 0,
  });

  final String? injection;
  final Map<String, dynamic>? searchReceipt;
  final Map<String, dynamic>? wikiReceipt;
  final Map<String, dynamic>? toolReceipt;

  /// Spoken character text from the doorbell `generateWithTools` when no
  /// advertised tool fired. After a ring the clerk's text is discarded.
  final String? spokenText;

  /// Unwrapped clip for the clerk's tool-result row. Empty on a miss.
  final String scrap;

  /// Advertised tool dispatches this turn. 0 = she never rang.
  final int dispatchRounds;
}

/// Doorbell `generateWithTools` plus a clerk loop after she rings.
///
/// No advertised call → spoken tools text (the bubble) and zero extra
/// trips. A ring dispatches (wiki parse / Tavily / recipe card), then up
/// to [kClerkMaxDispatchRounds] advertised dispatches total. Clerk
/// follow-ups never become the bubble: collate one scrap and the mouth
/// streams without tools.
Future<CatalogRound> runCatalogRound({
  required LLMService llm,
  required GenerationParams params,
  required CatalogBuildResult catalog,
  required WebSearchService search,
  WikiSearchService? wiki,
  Future<UserToolHttpResult> Function(
    CatalogTool entry,
    Map<String, dynamic> arguments,
  )?
  executeUserTool,
}) async {
  final tools = catalog.toOpenAiTools();
  debugPrint(
    '[Tools] catalog round backend=${llm.backendName} '
    'tools=${[for (final t in catalog.tools) t.name]} '
    'reasoning=${params.reasoningEnabled}',
  );

  final messages = <Map<String, Object>>[
    if (params.chatMessages != null && params.chatMessages!.isNotEmpty)
      ...params.chatMessages!
    else
      {'role': 'user', 'content': params.prompt},
  ];
  final injections = <String>[];
  Map<String, dynamic>? searchReceipt;
  Map<String, dynamic>? wikiReceipt;
  Map<String, dynamic>? toolReceipt;
  var dispatchRounds = 0;
  String? spokenText;
  final seenCalls = <String>{};

  for (var trip = 0; trip < kClerkMaxDispatchRounds; trip++) {
    final tripParams = trip == 0
        ? params
        : clerkFollowupParams(params, messages);
    if (trip > 0) {
      debugPrint('[Clerk] follow-up trip=$trip dispatches=$dispatchRounds');
    }
    LlmToolResponse? resp;
    try {
      resp = await llm.generateWithTools(tripParams, tools);
    } catch (e) {
      debugPrint('[Tools] generateWithTools THREW: $e');
      break;
    }
    if (resp == null) {
      debugPrint('[Tools] generateWithTools returned null (tools unsupported)');
      break;
    }
    debugPrint(
      '[Tools] think calls=${resp.calls.map((c) => c.name).toList()} '
      'textChars=${resp.text.length}',
    );

    LlmToolCall? call;
    CatalogTool? entry;
    for (final c in resp.calls) {
      final found = catalog.lookup(c.name);
      if (found != null) {
        call = c;
        entry = found;
        break;
      }
      debugPrint(
        '[Tools] ignoring unadvertised call name=${c.name} '
        '(no-op, not in catalog)',
      );
    }
    if (call == null || entry == null) {
      final text = resp.text.trim();
      if (dispatchRounds == 0) {
        debugPrint(
          '[Tools] no advertised tool call — '
          '${text.isEmpty ? 'will stream in-character reply' : 'using spoken tools text'}',
        );
        spokenText = text.isEmpty ? null : text;
      } else {
        debugPrint(
          '[Clerk] no further tool — discard clerk text, stream the mouth',
        );
      }
      break;
    }
    final sig = '${call.name}|${jsonEncode(call.arguments)}';
    if (!seenCalls.add(sig)) {
      debugPrint('[Clerk] repeat $sig — not another book, stop');
      break;
    }

    final round = await _dispatchCall(
      call: call,
      entry: entry,
      search: search,
      wiki: wiki,
      executeUserTool: executeUserTool,
    );
    dispatchRounds++;
    final injection = round.injection;
    if (injection != null && injection.isNotEmpty) {
      injections.add(injection);
    }
    if (round.searchReceipt != null) searchReceipt = round.searchReceipt;
    if (round.wikiReceipt != null) wikiReceipt = round.wikiReceipt;
    if (round.toolReceipt != null) toolReceipt = round.toolReceipt;

    if (dispatchRounds >= kClerkMaxDispatchRounds) {
      debugPrint('[Clerk] dispatch cap $kClerkMaxDispatchRounds — stop');
      break;
    }
    final id = clerkCallId(call, dispatchRounds);
    final clip = round.scrap.trim().isNotEmpty
        ? round.scrap
        : (round.injection ?? '');
    messages
      ..add(
        clerkAssistantToolCallMessage(call: call, callId: id, text: resp.text),
      )
      ..add(clerkToolResultMessage(callId: id, clip: clip));
  }

  return CatalogRound(
    injection: collateCatalogInjections(injections),
    searchReceipt: searchReceipt,
    wikiReceipt: wikiReceipt,
    toolReceipt: toolReceipt,
    spokenText: spokenText,
    dispatchRounds: dispatchRounds,
  );
}

Future<CatalogRound> _dispatchCall({
  required LlmToolCall call,
  required CatalogTool entry,
  required WebSearchService search,
  WikiSearchService? wiki,
  Future<UserToolHttpResult> Function(
    CatalogTool entry,
    Map<String, dynamic> arguments,
  )?
  executeUserTool,
}) async {
  if (entry.source == ToolSource.inProcess &&
      entry.name == kWebSearchToolName) {
    return _dispatchSearch(call, search);
  }
  if (entry.source == ToolSource.inProcess &&
      entry.name == kWikiSearchToolName) {
    return _dispatchWiki(call, wiki);
  }
  if (entry.source == ToolSource.inProcess && entry.name == kWikiPageToolName) {
    return _dispatchWikiPage(call, wiki);
  }
  if (entry.source == ToolSource.userCard) {
    return _dispatchUserCard(
      call: call,
      entry: entry,
      executeUserTool: executeUserTool,
    );
  }
  debugPrint('[Tools] no-op: catalog entry ${entry.name} has no dispatcher');
  return const CatalogRound();
}

Future<CatalogRound> _dispatchWiki(
  LlmToolCall call,
  WikiSearchService? wiki,
) async {
  if (wiki == null || !wiki.isActive) {
    final query = WebSearchService.prepareQuery(
      call.arguments['query']?.toString() ?? '',
    );
    return CatalogRound(
      injection: SearchInjection.emptyResultFragment(query),
      searchReceipt: {'query': query, 'ok': false, 'source': 'wiki'},
      wikiReceipt: {'query': query, 'ok': false, 'source': 'wiki'},
    );
  }
  final query = WebSearchService.prepareQuery(
    call.arguments['query']?.toString() ?? '',
  );
  debugPrint('[Tools] dispatch in-process wiki_search query="$query"');
  final outcome = await wiki.lookup(query);
  return _wikiRound(wiki, outcome);
}

Future<CatalogRound> _dispatchWikiPage(
  LlmToolCall call,
  WikiSearchService? wiki,
) async {
  final title = WebSearchService.prepareQuery(
    call.arguments['title']?.toString() ??
        call.arguments['page']?.toString() ??
        '',
  );
  if (wiki == null || !wiki.isActive) {
    return CatalogRound(
      injection: SearchInjection.emptyResultFragment(title),
      searchReceipt: {'query': title, 'ok': false, 'source': 'wiki'},
      wikiReceipt: {'query': title, 'ok': false, 'source': 'wiki'},
    );
  }
  debugPrint('[Tools] dispatch in-process wiki_page title="$title"');
  final outcome = await wiki.getArticle(title);
  return _wikiRound(wiki, outcome);
}

CatalogRound _wikiRound(WikiSearchService wiki, WebSearchResult outcome) {
  final injection = outcome.ok
      ? SearchInjection.wikiResultFragment(outcome.snippet)
      : SearchInjection.emptyResultFragment(outcome.query);
  final base = parseWikiBaseUrl(wiki.getBaseUrl());
  final receipt = <String, dynamic>{
    'query': outcome.query,
    'ok': outcome.ok,
    'cached': outcome.fromCache,
    'source': 'wiki',
    if (base != null)
      'url': (base.path.isEmpty || base.path == '/')
          ? base.origin
          : '${base.origin}${base.path}',
  };
  return CatalogRound(
    injection: injection,
    searchReceipt: receipt,
    wikiReceipt: receipt,
    scrap: outcome.ok ? outcome.snippet : '',
    dispatchRounds: 1,
  );
}

Future<CatalogRound> _dispatchSearch(
  LlmToolCall call,
  WebSearchService search,
) async {
  final query = WebSearchService.prepareQuery(
    call.arguments['query']?.toString() ?? '',
  );
  debugPrint('[Tools] dispatch in-process web_search query="$query"');
  final outcome = await search.lookup(query);
  final injection = outcome.ok
      ? SearchInjection.resultFragment(outcome.snippet)
      : SearchInjection.emptyResultFragment(outcome.query);
  return CatalogRound(
    injection: injection,
    searchReceipt: {
      'query': outcome.query,
      'ok': outcome.ok,
      'cached': outcome.fromCache,
    },
    scrap: outcome.ok ? outcome.snippet : '',
    dispatchRounds: 1,
  );
}

Future<CatalogRound> _dispatchUserCard({
  required LlmToolCall call,
  required CatalogTool entry,
  Future<UserToolHttpResult> Function(
    CatalogTool entry,
    Map<String, dynamic> arguments,
  )?
  executeUserTool,
}) async {
  debugPrint('[Tools] dispatch user card tool=${entry.name}');
  UserToolHttpResult result;
  if (executeUserTool != null) {
    result = await executeUserTool(entry, call.arguments);
  } else {
    final card = entry.card;
    if (card == null) {
      result = const UserToolHttpResult(ok: false, text: '');
    } else {
      result = await executeUserToolCard(card, call.arguments);
    }
  }
  final injection = result.ok
      ? UserToolInjection.resultFragment(result.text)
      : UserToolInjection.emptyResultFragment;
  return CatalogRound(
    injection: injection,
    toolReceipt: {'tool': entry.name, 'ok': result.ok},
    scrap: result.ok ? result.text : '',
    dispatchRounds: 1,
  );
}
