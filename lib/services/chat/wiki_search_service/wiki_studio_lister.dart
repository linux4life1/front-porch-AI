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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/chat/mediawiki_search.dart';
import 'package:front_porch_ai/services/chat/tiddly_wiki.dart';
import 'package:front_porch_ai/services/chat/wiki_search_service/wiki_backend.dart';
import 'package:front_porch_ai/services/chat/wiki_search_service/wiki_http_client.dart';

/// Studio catalog. Chat `wiki_search` stays a 3-hit postcard.
class WikiStudioCatalog {
  const WikiStudioCatalog({
    required this.backend,
    required this.titles,
    this.skipped = 0,
    this.parsed = 0,
  });

  final WikiBackend backend;
  final List<String> titles;
  final int skipped;
  final int parsed;
}

/// Studio catalog listing for a wiki base. The owning service resolves the
/// backend and hands in the cached tiddler index; HTTP calls are reported
/// back through [onHttpCall].
class WikiStudioLister {
  WikiStudioLister({required this.http, required this.onHttpCall});

  final WikiHttpClient http;
  final void Function() onHttpCall;

  /// Tiddly: index titles. MediaWiki: allpages (index analog), seed search
  /// as a fallback. Skips `$:/`, media, galleries. Cap is the catalog, not 3.
  Future<WikiStudioCatalog> listStudioTitles(
    Uri base,
    WikiBackend kind, {
    TiddlyIndex? tiddlyIndex,
    String? seedQuery,
  }) async {
    if (kind == WikiBackend.tiddly) {
      final index = tiddlyIndex;
      if (index == null) {
        return const WikiStudioCatalog(backend: WikiBackend.tiddly, titles: []);
      }
      final titles = <String>[];
      var skipped = index.skippedSystem;
      for (final t in index.tiddlers) {
        if (skipWikiStudioTitle(t.title)) {
          skipped++;
          continue;
        }
        titles.add(t.title);
        if (titles.length >= kWorldWikiCatalogCap) break;
      }
      return WikiStudioCatalog(
        backend: WikiBackend.tiddly,
        titles: titles,
        skipped: skipped,
        parsed: index.parsedCount,
      );
    }
    if (kind != WikiBackend.mediawiki) {
      return WikiStudioCatalog(backend: kind, titles: const []);
    }
    final fromPages = await _mediawikiAllPages(base);
    if (fromPages.isNotEmpty) {
      return WikiStudioCatalog(
        backend: WikiBackend.mediawiki,
        titles: fromPages,
        parsed: fromPages.length,
      );
    }
    final seed = (seedQuery ?? '').trim();
    if (seed.isEmpty) {
      return const WikiStudioCatalog(
        backend: WikiBackend.mediawiki,
        titles: [],
      );
    }
    final searched = await _mediawikiStudioSearch(base, seed);
    return WikiStudioCatalog(
      backend: WikiBackend.mediawiki,
      titles: searched,
      parsed: searched.length,
    );
  }

  Future<List<String>> _mediawikiAllPages(Uri wikiBase) async {
    final out = <String>[];
    final seen = <String>{};
    String? cont;
    for (var page = 0; page < 4; page++) {
      onHttpCall();
      final uri = mediawikiAllPagesUri(wikiBase, apcontinue: cont);
      try {
        final resp = await http.get(
          uri,
          kind: 'search',
          cap: kMediaWikiMaxBodyBytes,
        );
        if (resp.statusCode != 200) break;
        if (resp.bodyBytes.length > kMediaWikiMaxBodyBytes) break;
        final parsed = parseMediaWikiAllPages(resp.body);
        for (final t in parsed.titles) {
          if (!seen.add(t.toLowerCase())) continue;
          out.add(t);
          if (out.length >= kWorldWikiCatalogCap) return out;
        }
        cont = parsed.apcontinue;
        if (cont == null || cont.isEmpty) break;
      } catch (e) {
        debugPrint('[World] allpages miss/fail reason=$e');
        break;
      }
    }
    return out;
  }

  Future<List<String>> _mediawikiStudioSearch(
    Uri wikiBase,
    String query,
  ) async {
    onHttpCall();
    final uri = mediawikiStudioSearchUri(wikiBase, query);
    try {
      final resp = await http.get(
        uri,
        kind: 'search',
        cap: kMediaWikiMaxBodyBytes,
      );
      if (resp.statusCode != 200) return const [];
      if (resp.bodyBytes.length > kMediaWikiMaxBodyBytes) return const [];
      return [
        for (final t in parseMediaWikiSearchTitles(resp.body, maxTitles: 50))
          if (!skipWikiStudioTitle(t)) t,
      ];
    } catch (e) {
      debugPrint('[World] studio search miss/fail reason=$e');
      return const [];
    }
  }
}
