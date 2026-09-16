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

import 'package:front_porch_ai/services/chat/prompt_injection/prompt_injection.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Cap on a wiki HTTP body before we refuse to parse it. Honest miss beats
/// stuffing a dump into the prompt.
const int kMediaWikiMaxBodyBytes = 2 * 1024 * 1024;

/// Lore clip. Web search stays at [kSearchSnippetCharCap] (800). Wiki
/// pages need a real extract or she only gets a Fandom search blurb.
const int kWikiExtractCharCap = 3500;

/// Studio World-from-wiki bake. Chat inject stays [kWikiExtractCharCap].
const int kWorldWikiArticleCharCap = 48000;

/// Studio catalog listing cap. Chat `wiki_search` stays at srlimit 3.
const int kWorldWikiCatalogCap = 500;

/// Origin of a pasted MediaWiki / Fandom / Wikipedia URL, or null if the
/// string is empty, not http(s), or otherwise unsafe to fetch.
///
/// MediaWiki-looking hosts keep origin only (`/wiki/Aizen` is an article).
/// Everything else keeps the path so a TiddlyWiki on GitHub Pages
/// (`https://quietoak.github.io/NeokosmosWiki/`) is fetchable.
final _hostOnly = RegExp(r'^[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z0-9.-]+(/.*)?$');

const String kWikiUserAgent = 'FrontPorchAI/wiki';

bool looksLikeMediaWikiHost(String host) {
  final h = host.toLowerCase();
  if (h == 'wikipedia.org' || h.endsWith('.wikipedia.org')) return true;
  if (h == 'fandom.com' || h.endsWith('.fandom.com')) return true;
  if (h == 'wiki.gg' || h.endsWith('.wiki.gg')) return true;
  if (h == 'wikimedia.org' || h.endsWith('.wikimedia.org')) return true;
  if (h == 'mediawiki.org' || h.endsWith('.mediawiki.org')) return true;
  return false;
}

Uri? parseWikiBaseUrl(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  if (!s.contains('://')) {
    if (!_hostOnly.hasMatch(s)) return null;
    s = 'https://$s';
  }
  final uri = Uri.tryParse(s);
  if (uri == null || !isSafeOutboundUrl(uri)) return null;
  if (uri.host.contains(' ') || uri.host.contains('%20')) return null;
  if (looksLikeMediaWikiHost(uri.host)) {
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    );
  }
  var path = uri.path.isEmpty ? '/' : uri.path;
  if (path.endsWith('/index.html')) {
    path = path.substring(0, path.length - 'index.html'.length);
  }
  final segs = [
    for (final p in path.split('/'))
      if (p.isNotEmpty) p,
  ];
  final looksFile = segs.isNotEmpty && segs.last.contains('.');
  if (!looksFile && !path.endsWith('/')) path = '$path/';
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: path,
  );
}

/// Wikipedia-family hosts keep the REST search the app already uses.
/// Everyone else (Fandom, wiki.gg, self-hosted MW) uses Action API —
/// Fandom's REST sits behind Cloudflare and 403s.
bool usesMediaWikiActionApi(Uri wikiBase) {
  final host = wikiBase.host.toLowerCase();
  return host != 'wikipedia.org' && !host.endsWith('.wikipedia.org');
}

/// Search URI against [wikiBase]'s host. Query is already prepared.
Uri mediawikiSearchUri(Uri wikiBase, String query) {
  if (usesMediaWikiActionApi(wikiBase)) {
    return mediawikiActionApiUri(wikiBase).replace(
      queryParameters: {
        'action': 'query',
        'list': 'search',
        'srsearch': query,
        'srlimit': '3',
        'srprop': 'snippet',
        'format': 'json',
      },
    );
  }
  return Uri.parse(
    '${wikiBase.origin}/w/rest.php/v1/search/page',
  ).replace(queryParameters: {'q': query, 'limit': '3'});
}

/// Top titles from an Action API search (or REST `pages`).
List<String> parseMediaWikiSearchTitles(String body, {int maxTitles = 2}) {
  final dynamic json;
  try {
    json = jsonDecode(body);
  } catch (_) {
    return const [];
  }
  if (json is! Map) return const [];
  final cap = maxTitles < 1 ? 1 : maxTitles;
  final titles = <String>[];
  void take(Object? pages, {String titleKey = 'title'}) {
    if (pages is! List) return;
    for (final page in pages) {
      if (page is! Map) continue;
      final t = page[titleKey]?.toString().trim() ?? '';
      if (t.isEmpty) continue;
      final lower = t.toLowerCase();
      if (lower.contains('image gallery') || lower.contains('/gallery')) {
        continue;
      }
      titles.add(t);
      if (titles.length >= cap) return;
    }
  }

  take(json['pages']);
  final query = json['query'];
  if (query is Map) take(query['search']);
  return titles;
}

/// Plain-text extracts for [titles] on an Action API wiki.
Uri mediawikiExtractUri(Uri wikiBase, List<String> titles) {
  final joined = titles.where((t) => t.trim().isNotEmpty).take(2).join('|');
  return mediawikiActionApiUri(wikiBase).replace(
    queryParameters: {
      'action': 'query',
      'prop': 'extracts',
      'explaintext': '1',
      'redirects': '1',
      'titles': joined,
      'format': 'json',
    },
  );
}

/// `query.pages.*.extract` joined and clipped.
String parseMediaWikiExtracts(String body) {
  final dynamic json;
  try {
    json = jsonDecode(body);
  } catch (_) {
    return '';
  }
  if (json is! Map) return '';
  final query = json['query'];
  if (query is! Map) return '';
  final pages = query['pages'];
  if (pages is! Map) return '';
  final buf = StringBuffer();
  for (final page in pages.values) {
    if (page is! Map) continue;
    final title = page['title']?.toString().trim() ?? '';
    final extract = page['extract']?.toString().trim() ?? '';
    if (extract.isEmpty) continue;
    if (buf.isNotEmpty) buf.write('\n\n');
    if (title.isNotEmpty) buf.write('$title\n');
    buf.write(extract);
    if (buf.length >= kWikiExtractCharCap) break;
  }
  final s = buf.toString().trim();
  if (s.length <= kWikiExtractCharCap) return s;
  return s.substring(0, kWikiExtractCharCap).trim();
}

/// Fandom (and many MW farms) have no TextExtracts. Parse HTML instead.
Uri mediawikiParseUri(Uri wikiBase, String title) {
  return mediawikiActionApiUri(wikiBase).replace(
    queryParameters: {
      'action': 'parse',
      'page': title,
      'prop': 'text',
      'redirects': '1',
      'format': 'json',
    },
  );
}

final _scriptRe = RegExp(r'<script[\s\S]*?</script>', caseSensitive: false);
final _styleRe = RegExp(r'<style[\s\S]*?</style>', caseSensitive: false);
final _tagRe = RegExp(r'<[^>]+>');
final _wsRe = RegExp(r'\s+');

/// `parse.text.*` HTML → clipped plain text.
String parseMediaWikiParseHtml(
  String body, {
  int clipChars = kWikiExtractCharCap,
}) {
  final dynamic json;
  try {
    json = jsonDecode(body);
  } catch (_) {
    return '';
  }
  if (json is! Map) return '';
  final parse = json['parse'];
  if (parse is! Map) return '';
  final title = parse['title']?.toString().trim() ?? '';
  var html = '';
  final text = parse['text'];
  if (text is Map) {
    html = text['*']?.toString() ?? '';
  } else if (text is String) {
    html = text;
  }
  if (html.trim().isEmpty) return '';
  var plain = wikiHtmlToPlain(html);
  if (plain.isEmpty) return '';
  if (title.isNotEmpty) plain = '$title\n$plain';
  if (clipChars <= 0 || plain.length <= clipChars) return plain;
  return plain.substring(0, clipChars).trim();
}

/// Skip `$:/`, media, galleries, and talk/file namespaces. Studio listing.
bool skipWikiStudioTitle(String title) {
  final t = title.trim();
  if (t.isEmpty) return true;
  if (t.startsWith(r'$:/')) return true;
  final lower = t.toLowerCase();
  if (lower.contains('medialibrary') || lower.contains('media library')) {
    return true;
  }
  if (lower.contains('image gallery') || lower.contains('/gallery')) {
    return true;
  }
  const junkExt = <String>[
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.svg',
    '.webp',
    '.ico',
    '.bmp',
    '.mp3',
    '.mp4',
    '.webm',
    '.ogg',
    '.wav',
    '.m4a',
    '.aac',
  ];
  for (final ext in junkExt) {
    if (lower.endsWith(ext)) return true;
  }
  const ns = <String>[
    'file:',
    'media:',
    'category:',
    'template:',
    'user:',
    'talk:',
    'special:',
    'module:',
    'help:',
    'mediawiki:',
    'interface:',
  ];
  for (final n in ns) {
    if (lower.startsWith(n)) return true;
  }
  return false;
}

Uri mediawikiActionApiUri(Uri wikiBase) {
  if (looksLikeMediaWikiHost(wikiBase.host)) {
    if (usesMediaWikiActionApi(wikiBase)) {
      return Uri.parse('${wikiBase.origin}/api.php');
    }
    return Uri.parse('${wikiBase.origin}/w/api.php');
  }
  final segs = [
    for (final p in wikiBase.path.split('/'))
      if (p.isNotEmpty &&
          p != 'api.php' &&
          p != 'index.php' &&
          p != 'index.html')
        p,
  ];
  if (segs.isNotEmpty) {
    return Uri(
      scheme: wikiBase.scheme,
      host: wikiBase.host,
      port: wikiBase.hasPort ? wikiBase.port : null,
      path: '/${segs.join('/')}/api.php',
    );
  }
  return Uri.parse('${wikiBase.origin}/api.php');
}

Uri mediawikiAllPagesUri(Uri wikiBase, {String? apcontinue}) {
  return mediawikiActionApiUri(wikiBase).replace(
    queryParameters: {
      'action': 'query',
      'list': 'allpages',
      'apnamespace': '0',
      'aplimit': '500',
      'apfilterredir': 'nonredirects',
      'format': 'json',
      if (apcontinue != null && apcontinue.isNotEmpty) 'apcontinue': apcontinue,
    },
  );
}

Uri mediawikiStudioSearchUri(Uri wikiBase, String query) {
  return mediawikiActionApiUri(wikiBase).replace(
    queryParameters: {
      'action': 'query',
      'list': 'search',
      'srsearch': query,
      'srlimit': '50',
      'srprop': 'snippet',
      'format': 'json',
    },
  );
}

({List<String> titles, String? apcontinue}) parseMediaWikiAllPages(
  String body,
) {
  final dynamic json;
  try {
    json = jsonDecode(body);
  } catch (_) {
    return (titles: const <String>[], apcontinue: null);
  }
  if (json is! Map) return (titles: const <String>[], apcontinue: null);
  final query = json['query'];
  final titles = <String>[];
  if (query is Map) {
    final pages = query['allpages'];
    if (pages is List) {
      for (final page in pages) {
        if (page is! Map) continue;
        final t = page['title']?.toString().trim() ?? '';
        if (t.isEmpty || skipWikiStudioTitle(t)) continue;
        titles.add(t);
      }
    }
  }
  String? cont;
  final rawCont = json['continue'];
  if (rawCont is Map) {
    cont = rawCont['apcontinue']?.toString();
  }
  return (titles: titles, apcontinue: cont);
}

/// Tags out of wiki HTML. Shared by MediaWiki parse and Tiddly tiddlers.
String wikiHtmlToPlain(String html) {
  return html
      .replaceAll(_scriptRe, ' ')
      .replaceAll(_styleRe, ' ')
      .replaceAll(_tagRe, ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&quot;', '"')
      .replaceAll('&#8212;', '—')
      .replaceAll(_wsRe, ' ')
      .trim();
}

/// REST `pages` or Action API `query.search`. Empty on junk JSON.
String parseMediaWikiBody(String body) {
  final dynamic json;
  try {
    json = jsonDecode(body);
  } catch (_) {
    return '';
  }
  if (json is! Map) return '';
  final rest = _parsePages(json['pages']);
  if (rest.isNotEmpty) return rest;
  final query = json['query'];
  if (query is Map) {
    return _parsePages(query['search'], excerptKey: 'snippet');
  }
  return '';
}

String _parsePages(Object? pages, {String excerptKey = 'excerpt'}) {
  if (pages is! List) return '';
  final buf = StringBuffer();
  for (final page in pages) {
    if (page is! Map) continue;
    final title = page['title']?.toString() ?? '';
    final excerpt = page[excerptKey]?.toString() ?? '';
    if (title.trim().isEmpty && excerpt.trim().isEmpty) continue;
    if (buf.isNotEmpty) buf.write(' ');
    if (title.trim().isNotEmpty) buf.write('$title — ');
    buf.write(SearchInjection.clipSnippet(excerpt));
    if (buf.length >= kSearchSnippetCharCap) break;
  }
  return SearchInjection.clipSnippet(buf.toString());
}
