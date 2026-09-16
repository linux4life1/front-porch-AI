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
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/chat/mediawiki_search.dart';
import 'package:front_porch_ai/services/chat/tiddly_wiki.dart';
import 'package:front_porch_ai/services/chat/web_search_service.dart';
import 'package:front_porch_ai/utils/utils.dart';

part 'wiki_search_service.http.dart';
part 'wiki_search_service.studio.dart';

enum WikiBackend { mediawiki, tiddly, unknown }

/// Same turn window as [shouldAdvertiseWebSearch], but the switch is "this
/// chat has a usable wiki URL" instead of the Porch Life web-search global.
/// Regen advertises (directUserSend on that path). Continue does not.
bool shouldAdvertiseWikiSearch({
  required String wikiUrl,
  required bool directUserSend,
  required bool continueMode,
  required bool toolsUnsupported,
  bool autonomousMode = false,
}) {
  return parseWikiBaseUrl(wikiUrl) != null &&
      directUserSend &&
      !continueMode &&
      !autonomousMode &&
      !toolsUnsupported;
}

/// Wiki lookup against the pasted host. MediaWiki/Fandom or TiddlyWiki.
/// Session cache of the tiddler index; HTTP only on a miss.
class WikiSearchService with _WikiHttp {
  WikiSearchService({required this.getBaseUrl, this.sendRequest});

  final String Function() getBaseUrl;

  /// Request-level test seam. Production leaves this null.
  @override
  final Future<http.Response> Function(http.BaseRequest request)? sendRequest;

  bool get isActive => parseWikiBaseUrl(getBaseUrl()) != null;

  int httpCalls = 0;
  final Map<String, String> _cache = {};
  final Map<String, WikiBackend> _backend = {};
  final Map<String, TiddlyIndex> _tiddly = {};
  int _httpThisSend = 0;

  void beginUserSend() => _httpThisSend = 0;

  void resetCache() {
    _cache.clear();
    _backend.clear();
    _tiddly.clear();
    _httpThisSend = 0;
  }

  void resetForFreshChat() => resetCache();

  Future<WebSearchResult> lookup(String query) async {
    return _run(query, page: false);
  }

  /// `wiki_page` / get_article: open this title on the detected backend.
  Future<WebSearchResult> getArticle(
    String title, {
    bool honorSendCap = true,
  }) async {
    return _run(title, page: true, honorSendCap: honorSendCap);
  }

  /// Studio bake: full article, not the chat 3500 clip. Does not spend
  /// the per-send HTTP cap (chat stays at 6).
  Future<WebSearchResult> getArticleFull(String title) {
    return _run(
      title,
      page: true,
      clipChars: kWorldWikiArticleCharCap,
      honorSendCap: false,
    );
  }

  Future<WebSearchResult> _run(
    String rawIn, {
    required bool page,
    int? clipChars,
    bool honorSendCap = true,
  }) async {
    final base = parseWikiBaseUrl(getBaseUrl());
    if (base == null) {
      debugPrint('[Wiki] miss/fail reason=junk url page=$page');
      return const WebSearchResult(
        query: '',
        snippet: '',
        fromCache: false,
        httpAttempted: false,
      );
    }
    final raw = WebSearchService.prepareQuery(rawIn);
    if (raw.isEmpty) {
      debugPrint('[Wiki] miss/fail reason=empty page=$page');
      return const WebSearchResult(
        query: '',
        snippet: '',
        fromCache: false,
        httpAttempted: false,
      );
    }
    final clip = clipChars ?? (page ? kWikiExtractCharCap : 0);
    final key =
        '${page ? 'page' : 'search'}|$clip|${_cacheKey(base)}|'
        '${WebSearchService.normalizeQuery(raw)}';
    final cached = _cache[key];
    if (cached != null) {
      return WebSearchResult(
        query: raw,
        snippet: cached,
        fromCache: true,
        httpAttempted: false,
      );
    }
    final kind = await _ensureBackend(base, honorSendCap: honorSendCap);
    debugPrint(
      '[Wiki] picker url=${_cacheKey(base)} backend=${kind.name} '
      'page=$page',
    );
    if (kind == WikiBackend.unknown) {
      debugPrint('[Wiki] miss/fail reason=no store');
      return WebSearchResult(
        query: raw,
        snippet: '',
        fromCache: false,
        httpAttempted: true,
      );
    }
    String snippet;
    if (kind == WikiBackend.tiddly) {
      snippet = page
          ? _tiddlyPage(base, raw, clipChars: clip)
          : _tiddlySearch(base, raw);
    } else if (page) {
      snippet = await _mediawikiPage(
        base,
        raw,
        clipChars: clip,
        honorSendCap: honorSendCap,
      );
    } else {
      snippet = await _mediawikiLookup(base, raw);
    }
    if (snippet.trim().isEmpty) {
      debugPrint('[Wiki] miss/fail reason=empty page=$page');
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

  String _cacheKey(Uri base) => '${base.origin}${base.path}';

  String _tiddlySearch(Uri base, String query) {
    final index = _tiddly[_cacheKey(base)];
    if (index == null) {
      debugPrint('[Tiddly] miss/fail reason=no store');
      return '';
    }
    final hits = searchTiddlyIndex(index, query);
    debugPrint(
      '[Tiddly] search query="$query" hits='
      '${[for (final t in hits.take(5)) t.title].join(', ')}',
    );
    return formatTiddlySearchHits(hits);
  }

  String _tiddlyPage(
    Uri base,
    String title, {
    int clipChars = kWikiExtractCharCap,
  }) {
    final index = _tiddly[_cacheKey(base)];
    if (index == null) {
      debugPrint('[WikiPage] miss/fail reason=no store title="$title"');
      return '';
    }
    final text = tiddlyPageText(index, title, clipChars: clipChars);
    debugPrint('[WikiPage] title="$title" clipChars=${text.length}');
    return text;
  }

  Future<WikiBackend> _ensureBackend(
    Uri base, {
    bool honorSendCap = true,
  }) async {
    final key = _cacheKey(base);
    final cached = _backend[key];
    if (cached != null) return cached;
    if (looksLikeMediaWikiHost(base.host)) {
      debugPrint('[Wiki] picker url=$key detected backend=mediawiki');
      return _backend[key] = WikiBackend.mediawiki;
    }
    TiddlyIndex? index;
    try {
      index = await _loadTiddlyIndex(base, honorSendCap: honorSendCap);
    } on TimeoutException {
      return WikiBackend.unknown;
    }
    if (index != null) {
      _tiddly[key] = index;
      debugPrint('[Wiki] picker url=$key detected backend=tiddly');
      debugPrint(
        '[Tiddly] index size=${index.tiddlers.length} '
        'skipped \$:/=${index.skippedSystem} parsed=${index.parsedCount}',
      );
      return _backend[key] = WikiBackend.tiddly;
    }
    if (await _apiPhpWorks(base)) {
      debugPrint('[Wiki] picker url=$key detected backend=mediawiki');
      return _backend[key] = WikiBackend.mediawiki;
    }
    debugPrint(
      '[Wiki] picker url=$key detected backend=unknown '
      'miss/fail reason=no store',
    );
    return _backend[key] = WikiBackend.unknown;
  }

  Future<TiddlyIndex?> _loadTiddlyIndex(
    Uri base, {
    bool honorSendCap = true,
  }) async {
    if (honorSendCap && _httpThisSend >= 6) {
      debugPrint('[Tiddly] miss/fail reason=cap');
      return null;
    }
    final uri = tiddlyFetchUri(base);
    httpCalls++;
    _httpThisSend++;
    try {
      final resp = await _get(
        uri,
        kind: 'html',
        cap: kTiddlyMaxBodyBytes,
        followRedirects: true,
      );
      if (resp.statusCode != 200) {
        debugPrint('[Tiddly] miss/fail reason=status ${resp.statusCode}');
        return null;
      }
      if (!looksLikeTiddlyStoreHtml(resp.body)) {
        debugPrint('[Tiddly] miss/fail reason=no store');
        return null;
      }
      return parseTiddlyStoreHtml(resp.body);
    } on TimeoutException {
      debugPrint('[Tiddly] miss/fail reason=timeout');
      rethrow;
    } catch (e) {
      debugPrint('[Tiddly] miss/fail reason=$e');
      return null;
    }
  }

  Future<bool> _apiPhpWorks(Uri wikiBase) async {
    if (_httpThisSend >= 6) return false;
    final uri = mediawikiActionApiUri(wikiBase).replace(
      queryParameters: {
        'action': 'query',
        'meta': 'siteinfo',
        'format': 'json',
      },
    );
    httpCalls++;
    _httpThisSend++;
    try {
      final resp = await _get(uri, kind: 'search', cap: kMediaWikiMaxBodyBytes);
      if (resp.statusCode != 200) return false;
      if (resp.bodyBytes.length > kMediaWikiMaxBodyBytes) return false;
      final dynamic json;
      try {
        json = jsonDecode(resp.body);
      } catch (_) {
        return false;
      }
      return json is Map && json['query'] != null;
    } catch (_) {
      return false;
    }
  }

  Future<String> _mediawikiLookup(Uri wikiBase, String query) async {
    if (_httpThisSend >= 6) return '';
    httpCalls++;
    _httpThisSend++;
    final searchUri = mediawikiSearchUri(wikiBase, query);
    try {
      final searchResp = await _get(
        searchUri,
        kind: 'search',
        cap: kMediaWikiMaxBodyBytes,
      );
      if (searchResp.statusCode != 200) return '';
      if (searchResp.bodyBytes.length > kMediaWikiMaxBodyBytes) {
        debugPrint('[Wiki] miss/fail reason=cap');
        return '';
      }
      final titles = parseMediaWikiSearchTitles(searchResp.body);
      if (usesMediaWikiActionApi(wikiBase) && titles.isNotEmpty) {
        final parsed = await _mediawikiParse(wikiBase, titles.first);
        if (parsed.trim().isNotEmpty) return parsed;
        if (_httpThisSend >= 6) return parseMediaWikiBody(searchResp.body);
        httpCalls++;
        _httpThisSend++;
        final extractUri = mediawikiExtractUri(wikiBase, titles);
        final extractResp = await _get(
          extractUri,
          kind: 'parse',
          cap: kMediaWikiMaxBodyBytes,
        );
        if (extractResp.statusCode == 200 &&
            extractResp.bodyBytes.length <= kMediaWikiMaxBodyBytes) {
          final extract = parseMediaWikiExtracts(extractResp.body);
          if (extract.trim().isNotEmpty) return extract;
        }
      }
      return parseMediaWikiBody(searchResp.body);
    } on TimeoutException {
      debugPrint('[Wiki] miss/fail reason=timeout');
      return '';
    } catch (e) {
      debugPrint('[Wiki] miss/fail reason=$e');
      return '';
    }
  }

  Future<String> _mediawikiPage(
    Uri wikiBase,
    String title, {
    int clipChars = kWikiExtractCharCap,
    bool honorSendCap = true,
  }) async {
    if (honorSendCap && _httpThisSend >= 6) {
      debugPrint('[WikiPage] miss/fail reason=cap title="$title"');
      return '';
    }
    final parsed = await _mediawikiParse(wikiBase, title, clipChars: clipChars);
    debugPrint('[WikiPage] title="$title" clipChars=${parsed.length}');
    return parsed;
  }

  Future<String> _mediawikiParse(
    Uri wikiBase,
    String title, {
    int clipChars = kWikiExtractCharCap,
  }) async {
    httpCalls++;
    _httpThisSend++;
    final parseUri = mediawikiParseUri(wikiBase, title);
    try {
      final parseResp = await _get(
        parseUri,
        kind: 'parse',
        cap: kMediaWikiMaxBodyBytes,
      );
      if (parseResp.statusCode == 200 &&
          parseResp.bodyBytes.length <= kMediaWikiMaxBodyBytes) {
        return parseMediaWikiParseHtml(parseResp.body, clipChars: clipChars);
      }
      if (parseResp.bodyBytes.length > kMediaWikiMaxBodyBytes) {
        debugPrint('[Wiki] miss/fail reason=cap');
      }
      return '';
    } on TimeoutException {
      debugPrint('[Wiki] miss/fail reason=timeout');
      return '';
    } catch (e) {
      debugPrint('[Wiki] miss/fail reason=$e');
      return '';
    }
  }
}
