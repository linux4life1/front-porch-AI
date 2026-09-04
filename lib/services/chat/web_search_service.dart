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

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/chat/prompt_injection/prompt_injection.dart';
import 'package:front_porch_ai/services/chat/web_search_tools.dart';
import 'package:front_porch_ai/services/llm_service.dart';

String _wsClip(String s, [int max = 180]) {
  final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.length <= max) return t;
  return '${t.substring(0, max)}…';
}

const Duration kWebSearchTimeout = Duration(seconds: 8);

const String kTavilySearchEndpoint = 'https://api.tavily.com/search';

/// Keyless default backend: Wikipedia REST search. Returns page titles +
/// excerpts as plain text — encyclopedia coverage, no signup, no key.
const String kWikipediaSearchEndpoint =
    'https://en.wikipedia.org/w/rest.php/v1/search/page';

/// One lookup: snippet text (empty = nothing reliable) plus whether this
/// call hit the session cache or the network.
class WebSearchResult {
  const WebSearchResult({
    required this.query,
    required this.snippet,
    required this.fromCache,
    required this.httpAttempted,
  });

  final String query;
  final String snippet;
  final bool fromCache;
  final bool httpAttempted;

  bool get ok => snippet.trim().isNotEmpty;
}

/// Outcome of the one tools round-trip. [cannedReply] is the model's
/// text when it did not call `web_search`. [injection] is the gated
/// fragment to splice into the prompt before streaming.
class WebSearchRound {
  const WebSearchRound({this.injection, this.receipt, this.cannedReply});

  final String? injection;
  final Map<String, dynamic>? receipt;
  final String? cannedReply;
}

/// Porch Life global on + direct user send + tools-capable → advertise
/// `web_search`. Continue, autonomous, regen, guest, cast, and group follow-up
/// turns fail closed. Read [globalDefault] at check time so flipping the
/// setting applies to the chat already open. No per-chat flag.
bool shouldAdvertiseWebSearch({
  required bool globalDefault,
  required bool directUserSend,
  required bool continueMode,
  required bool toolsUnsupported,
  bool autonomousMode = false,
}) {
  return globalDefault &&
      directUserSend &&
      !continueMode &&
      !autonomousMode &&
      !toolsUnsupported;
}

/// One `generateWithTools` with `web_search`. No call + text → canned
/// (think-phase scratch; dispatch must not use it as the bubble).
/// A `web_search` call → cache lookup, HTTP on miss, fragment.
Future<WebSearchRound> runWebSearchRound({
  required LLMService llm,
  required GenerationParams params,
  required WebSearchService search,
}) async {
  debugPrint(
    '[WebSearch] decision round backend=${llm.backendName} '
    'reasoning=${params.reasoningEnabled} effort=${params.reasoningEffort} '
    'cueInPrompt=${params.prompt.contains(kWebSearchDecisionCue)} '
    'cueInSystem=${params.systemPrompt?.contains(kWebSearchDecisionCue) ?? false} '
    'promptTail="${_wsClip(params.prompt)}"',
  );
  LlmToolResponse? resp;
  try {
    resp = await llm.generateWithTools(params, kWebSearchTools);
  } catch (e) {
    debugPrint('[WebSearch] generateWithTools THREW: $e');
    return const WebSearchRound();
  }
  if (resp == null) {
    debugPrint(
      '[WebSearch] generateWithTools returned null '
      '(backend rejected tools / no protocol)',
    );
    return const WebSearchRound();
  }

  debugPrint(
    '[WebSearch] think="${_wsClip(resp.reasoning)}" '
    'calls=${resp.calls.map((c) => c.name).toList()} '
    'text="${_wsClip(resp.text)}"',
  );

  LlmToolCall? call;
  for (final c in resp.calls) {
    if (c.name == kWebSearchToolName) {
      call = c;
      break;
    }
  }
  if (call == null) {
    final text = resp.text.trim();
    debugPrint(
      '[WebSearch] no web_search call — think-phase text only '
      '(${text.length} chars); will stream the in-character reply',
    );
    return WebSearchRound(cannedReply: text.isEmpty ? null : text);
  }

  final query = WebSearchService.prepareQuery(
    call.arguments['query']?.toString() ?? '',
  );
  debugPrint('[WebSearch] called web_search query="$query"');
  final outcome = await search.lookup(query);
  debugPrint(
    '[WebSearch] lookup ok=${outcome.ok} cached=${outcome.fromCache} '
    'http=${outcome.httpAttempted} snippet="${_wsClip(outcome.snippet)}"',
  );
  final injection = outcome.ok
      ? SearchInjection.resultFragment(outcome.snippet)
      : SearchInjection.emptyResultFragment(outcome.query);
  return WebSearchRound(
    injection: injection,
    receipt: {
      'query': outcome.query,
      'ok': outcome.ok,
      'cached': outcome.fromCache,
    },
  );
}

/// In-process Tavily/Wikipedia client. Session-scoped cache; HTTP only on
/// misses from an eligible direct user send.
class WebSearchService {
  WebSearchService({
    required this.getApiKey,
    this.getGlobalDefault,
    this.fetch,
    this.sendRequest,
  });

  final String Function() getApiKey;

  /// Live read of Porch Life `webSearchDefault`. Null in unit tests
  /// that only exercise lookup/cache.
  final bool Function()? getGlobalDefault;

  /// Legacy body-only test seam for Tavily. Production leaves this null.
  /// Returns the response body (not an [http.Response]).
  Future<String> Function(Uri uri, String apiKey)? fetch;

  /// Request-level test seam. Production leaves this null and uses a fresh
  /// [http.Client]. Requests reach this callback only after redirects are
  /// disabled.
  Future<http.Response> Function(http.BaseRequest request)? sendRequest;

  /// Porch Life global, read at check time — not seed time.
  bool get isActive => getGlobalDefault?.call() ?? false;

  int httpCalls = 0;
  final Map<String, String> _cache = {};
  int _httpThisSend = 0;

  bool get hasKey => getApiKey().trim().isNotEmpty;
  bool get hasApiKey => hasKey;

  /// Collapse whitespace and hard-truncate a model-supplied query before it
  /// can become a cache key, log line, URL, or request body. Runes avoid
  /// splitting a surrogate pair at the boundary.
  static String prepareQuery(String query) {
    final collapsed = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (collapsed.runes.length <= kWebSearchQueryMaxChars) return collapsed;
    return String.fromCharCodes(
      collapsed.runes.take(kWebSearchQueryMaxChars),
    ).trim();
  }

  static String normalizeQuery(String query) =>
      prepareQuery(query).toLowerCase();

  void beginUserSend() {
    _httpThisSend = 0;
  }

  void resetCache() {
    _cache.clear();
    _httpThisSend = 0;
  }

  void clearCache() => resetCache();

  void resetForFreshChat() {
    resetCache();
  }

  Future<WebSearchResult> lookup(String query) async {
    final raw = prepareQuery(query);
    if (raw.isEmpty) {
      return const WebSearchResult(
        query: '',
        snippet: '',
        fromCache: false,
        httpAttempted: false,
      );
    }
    final key = normalizeQuery(raw);
    final cached = _cache[key];
    if (cached != null) {
      debugPrint('[WebSearch] cache hit query="$raw"');
      return WebSearchResult(
        query: raw,
        snippet: cached,
        fromCache: true,
        httpAttempted: false,
      );
    }
    if (_httpThisSend >= 1) {
      debugPrint(
        '[WebSearch] HTTP cap (already 1 this send) — skip query="$raw"',
      );
      return WebSearchResult(
        query: raw,
        snippet: '',
        fromCache: false,
        httpAttempted: false,
      );
    }
    _httpThisSend++;
    final snippet = await _httpLookup(raw);
    if (snippet.trim().isEmpty) {
      debugPrint('[WebSearch] empty result not cached query="$raw"');
      return WebSearchResult(
        query: raw,
        snippet: '',
        fromCache: false,
        httpAttempted: true,
      );
    }
    _cache[key] = snippet;
    return WebSearchResult(
      query: raw,
      snippet: snippet,
      fromCache: false,
      httpAttempted: true,
    );
  }

  Future<String> _httpLookup(String query) async {
    final key = getApiKey().trim();
    if (key.isEmpty) {
      // Two-tier: no key → Wikipedia REST search (keyless, encyclopedia).
      debugPrint('[WebSearch] HTTP Wikipedia (no Tavily key) query="$query"');
      return _wikipediaLookup(query);
    }
    httpCalls++;
    try {
      final custom = fetch;
      if (custom != null) {
        debugPrint('[WebSearch] HTTP Tavily (test fetch) query="$query"');
        final body = await custom(
          Uri.parse(
            kTavilySearchEndpoint,
          ).replace(queryParameters: {'q': query}),
          key,
        ).timeout(kWebSearchTimeout);
        return _parseSnippets(body);
      }
      debugPrint('[WebSearch] HTTP Tavily query="$query"');
      final request = http.Request('POST', Uri.parse(kTavilySearchEndpoint))
        ..headers.addAll({
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $key',
        })
        ..body = jsonEncode({
          'query': query,
          'max_results': 3,
          'search_depth': 'basic',
        });
      final response = await _sendWithoutRedirects(request);
      debugPrint(
        '[WebSearch] Tavily status=${response.statusCode} '
        'bodyChars=${response.body.length}',
      );
      if (response.statusCode != 200) return '';
      return _parseSnippets(response.body);
    } catch (e) {
      debugPrint('[WebSearch] Tavily THREW: $e');
      return '';
    }
  }

  /// Keyless Wikipedia search. Returns page titles + excerpts as text.
  Future<String> _wikipediaLookup(String query) async {
    httpCalls++;
    final uri = Uri.parse(
      kWikipediaSearchEndpoint,
    ).replace(queryParameters: {'q': query, 'limit': '3'});
    try {
      final request = http.Request('GET', uri)
        ..headers['Accept'] = 'application/json';
      final response = await _sendWithoutRedirects(request);
      debugPrint(
        '[WebSearch] Wikipedia status=${response.statusCode} '
        'bodyChars=${response.body.length}',
      );
      if (response.statusCode != 200) return '';
      return _parseWikipedia(response.body);
    } catch (e) {
      debugPrint('[WebSearch] Wikipedia THREW: $e');
      return '';
    }
  }

  Future<http.Response> _sendWithoutRedirects(http.Request request) async {
    request
      ..followRedirects = false
      ..maxRedirects = 0;
    final custom = sendRequest;
    if (custom != null) {
      return custom(request).timeout(kWebSearchTimeout);
    }
    final client = http.Client();
    try {
      return await (() async {
        final streamed = await client.send(request);
        return http.Response.fromStream(streamed);
      })().timeout(kWebSearchTimeout);
    } finally {
      client.close();
    }
  }

  static String _parseWikipedia(String body) {
    final dynamic json;
    try {
      json = jsonDecode(body);
    } catch (_) {
      return '';
    }
    if (json is! Map) return '';
    final pages = json['pages'];
    if (pages is! List) return '';
    final buf = StringBuffer();
    for (final page in pages) {
      if (page is! Map) continue;
      final title = page['title']?.toString() ?? '';
      final excerpt = page['excerpt']?.toString() ?? '';
      if (title.trim().isEmpty && excerpt.trim().isEmpty) continue;
      if (buf.isNotEmpty) buf.write(' ');
      if (title.trim().isNotEmpty) buf.write('$title — ');
      buf.write(SearchInjection.clipSnippet(excerpt));
      if (buf.length >= kSearchSnippetCharCap) break;
    }
    return SearchInjection.clipSnippet(buf.toString());
  }

  static String _parseSnippets(String body) {
    final dynamic json;
    try {
      json = jsonDecode(body);
    } catch (_) {
      return '';
    }
    if (json is! Map) return '';
    // Tavily returns results at the top level.
    final results = json['results'];
    if (results is! List || results.isEmpty) return '';
    final buf = StringBuffer();
    for (final raw in results) {
      if (raw is! Map) continue;
      final title = raw['title']?.toString() ?? '';
      final desc = raw['content']?.toString() ?? '';
      final pieces = <String>[
        if (title.trim().isNotEmpty) title,
        if (desc.trim().isNotEmpty) desc,
      ];
      for (final piece in pieces) {
        final cleaned = SearchInjection.clipSnippet(piece);
        if (cleaned.isEmpty) continue;
        if (buf.isNotEmpty) buf.write(' ');
        buf.write(cleaned);
        if (buf.length >= kSearchSnippetCharCap) break;
      }
      if (buf.length >= kSearchSnippetCharCap) break;
    }
    return SearchInjection.clipSnippet(buf.toString());
  }
}
