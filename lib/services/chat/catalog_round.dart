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
    this.scrap = '',
    this.dispatchRounds = 0,
  });

  final String? injection;
  final Map<String, dynamic>? searchReceipt;
  final Map<String, dynamic>? wikiReceipt;
  final Map<String, dynamic>? toolReceipt;

  /// Unwrapped clip for the clerk's tool-result row. Empty on a miss.
  final String scrap;

  /// Advertised tool dispatches this turn. 0 = she never rang.
  final int dispatchRounds;
}

/// Doorbell `generateWithTools` plus a clerk loop after she rings.
///
/// Every trip uses [clerkSideLaneParams] (eval-lane budget, no thinking).
/// No advertised call → discard doorbell speech; the mouth streams with
/// full character params. A ring dispatches, then up to
/// [kClerkMaxDispatchRounds] advertised dispatches. Clerk text never
/// becomes the bubble: collate one scrap and the mouth streams.
Future<CatalogRound> runCatalogRound({
  required LLMService llm,
  required GenerationParams params,
  required CatalogBuildResult catalog,
  required WebSearchService search,
  WikiSearchService? wiki,
  String? backendIdentity,
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
    'sideLane',
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
  final seenCalls = <String>{};

  for (var trip = 0; trip < kClerkMaxDispatchRounds; trip++) {
    final tripParams = clerkSideLaneParams(
      params,
      messages: messages,
      backendIdentity: backendIdentity,
    );
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
      debugPrint(
        dispatchRounds == 0
            ? '[Tools] no advertised tool call — discard doorbell, stream the mouth'
            : '[Clerk] no further tool — discard clerk text, stream the mouth',
      );
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
  var outcome = await wiki.lookup(query);
  // MediaWiki lookup already parses the first hit. Tiddly search is
  // titles-only — open that tiddler without waiting for wiki_page.
  final base = parseWikiBaseUrl(wiki.getBaseUrl());
  final mediawiki = base != null && looksLikeMediaWikiHost(base.host);
  final title = firstWikiHitTitle(outcome.snippet);
  if (!mediawiki && outcome.ok && title != null) {
    debugPrint('[Clerk] auto wiki_page title="$title"');
    final page = await wiki.getArticle(title, honorSendCap: false);
    if (page.ok) outcome = page;
  }
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

/// First catalog title from a wiki_search scrap (`Title — clip`).
/// Skips drafts, system tiddlers, and image names so we open a real article.
String? firstWikiHitTitle(String snippet) {
  final line = snippet.trim().split('\n').first.trim();
  if (line.isEmpty) return null;
  var title = line;
  final dash = line.indexOf(' — ');
  if (dash > 0) title = line.substring(0, dash).trim();
  if (title.isEmpty) return null;
  final lower = title.toLowerCase();
  if (lower.startsWith(r'$:/')) return null;
  if (lower.startsWith('draft of')) return null;
  if (lower.contains('.png') ||
      lower.contains('.jpg') ||
      lower.contains('.jpeg') ||
      lower.contains('.gif') ||
      lower.contains('.mp3')) {
    return null;
  }
  return title;
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
