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

import 'package:front_porch_ai/services/chat/catalog_clerk.dart';
import 'package:front_porch_ai/services/chat/catalog_round.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/prompt_injection.dart';
import 'package:front_porch_ai/services/chat/web_search_service.dart';
import 'package:front_porch_ai/services/chat/wiki_search_service.dart';

/// Shown when `/search` or `/wiki` is missing `--` and the words to look up.
const String kLookupForceUsage =
    'Say what to look up after --. For example: /search -- the name';

const String _kLookupWebOff =
    'Turn on Web Search in Settings → Porch Life to use /search.';

const String _kLookupNoWiki =
    'This chat has no wiki. Pick one in Porch Life to use /wiki.';

const String _kLookupOnce = 'Use /search and /wiki once each.';

final RegExp _lookupCmd = RegExp(r'^/(search|wiki)\b', caseSensitive: false);

final RegExp _nextLookupCmd = RegExp(
  r'\s+/(?:search|wiki)\b',
  caseSensitive: false,
);

/// A `/search` or `/wiki` on a message the user is sending.
class LookupForceParse {
  const LookupForceParse._({
    required this.attempted,
    this.error,
    this.body = '',
    this.webQuery,
    this.wikiQuery,
  });

  const LookupForceParse.none()
    : attempted = false,
      error = null,
      body = '',
      webQuery = null,
      wikiQuery = null;

  /// True when a lookup command sits at the start or the end of the line.
  final bool attempted;

  /// Why the send must stop. Null when [accepted] or when this is not a command.
  final String? error;

  /// The line with the command removed. Empty when the message is only a lookup.
  final String body;

  final String? webQuery;
  final String? wikiQuery;

  bool get accepted => attempted && error == null;

  /// Text stored as the user line. A lookup with no other words keeps the query.
  String get userText {
    final line = body.trim();
    if (line.isNotEmpty) return line;
    return [
      if (webQuery != null && webQuery!.trim().isNotEmpty) webQuery!.trim(),
      if (wikiQuery != null && wikiQuery!.trim().isNotEmpty) wikiQuery!.trim(),
    ].join('\n');
  }
}

/// `/search` and `/wiki` count only at the start or the end, and only with
/// `--` plus the words to fetch. `/search *I smile*` is a rejected command,
/// not a search for the smile.
LookupForceParse parseLookupForce(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return const LookupForceParse.none();
  if (_lookupCmd.hasMatch(text)) {
    return _parseCommands(text, prefixBody: '');
  }
  final at = _commandSuffixStart(text);
  if (at < 0) return const LookupForceParse.none();
  return _parseCommands(
    text.substring(at).trimLeft(),
    prefixBody: text.substring(0, at).trimRight(),
  );
}

/// Null when this forced lookup can run. Otherwise a line for the banner.
String? lookupForceUnavailable({
  required String? webQuery,
  required String? wikiQuery,
  required bool webEnabled,
  required bool hasWiki,
}) {
  final lines = <String>[];
  if (webQuery != null && webQuery.trim().isNotEmpty && !webEnabled) {
    lines.add(_kLookupWebOff);
  }
  if (wikiQuery != null && wikiQuery.trim().isNotEmpty && !hasWiki) {
    lines.add(_kLookupNoWiki);
  }
  if (lines.isEmpty) return null;
  return lines.join(' ');
}

/// Scraps and receipts for words the user named. Does not ask the model
/// to choose a query.
class ForcedLookupOutcome {
  const ForcedLookupOutcome({
    this.injection,
    this.searchReceipt,
    this.wikiReceipt,
  });

  final String? injection;
  final Map<String, dynamic>? searchReceipt;
  final Map<String, dynamic>? wikiReceipt;
}

Future<ForcedLookupOutcome> runForcedLookups({
  required WebSearchService web,
  required WikiSearchService wiki,
  String? webQuery,
  String? wikiQuery,
}) async {
  final parts = <String>[];
  Map<String, dynamic>? searchReceipt;
  Map<String, dynamic>? wikiReceipt;
  final webWords = webQuery?.trim() ?? '';
  if (webWords.isNotEmpty) {
    final outcome = await web.lookup(webWords);
    final query = outcome.query.isEmpty ? webWords : outcome.query;
    parts.add(
      outcome.ok
          ? SearchInjection.resultFragment(outcome.snippet)
          : SearchInjection.emptyResultFragment(query),
    );
    searchReceipt = {
      'query': query,
      'ok': outcome.ok,
      'cached': outcome.fromCache,
    };
  }
  final wikiWords = wikiQuery?.trim() ?? '';
  if (wikiWords.isNotEmpty) {
    final page = await _openWiki(wiki, wikiWords);
    final query = page.query.isEmpty ? wikiWords : page.query;
    parts.add(
      page.ok
          ? SearchInjection.wikiResultFragment(page.snippet)
          : SearchInjection.emptyResultFragment(query),
    );
    wikiReceipt = {
      'query': query,
      'ok': page.ok,
      'cached': page.fromCache,
      'source': 'wiki',
    };
    searchReceipt ??= wikiReceipt;
  }
  return ForcedLookupOutcome(
    injection: collateCatalogInjections(parts),
    searchReceipt: searchReceipt,
    wikiReceipt: wikiReceipt,
  );
}

Future<WebSearchResult> _openWiki(WikiSearchService wiki, String words) async {
  final found = await wiki.lookup(words);
  if (found.ok) {
    final title = firstWikiHitTitle(found.snippet);
    if (title != null) {
      final opened = await wiki.getArticle(title);
      if (opened.ok) return opened;
    }
    return found;
  }
  final opened = await wiki.getArticle(words);
  if (opened.ok) return opened;
  return found.query.isEmpty
      ? WebSearchResult(
          query: words,
          snippet: '',
          fromCache: false,
          httpAttempted: found.httpAttempted,
        )
      : found;
}

int _commandSuffixStart(String text) {
  final re = RegExp(r'(?:^|\s)(?=/(?:search|wiki)\b)', caseSensitive: false);
  for (final match in re.allMatches(text)) {
    final slash = text.indexOf('/', match.start);
    if (slash < 0) continue;
    if (_couldBeCommandSuffix(text.substring(slash))) return slash;
  }
  return -1;
}

bool _couldBeCommandSuffix(String suffix) {
  var rest = suffix.trim();
  if (!_lookupCmd.hasMatch(rest)) return false;
  while (rest.isNotEmpty) {
    final match = _lookupCmd.firstMatch(rest);
    if (match == null) return false;
    rest = rest.substring(match.end).trimLeft();
    if (rest.isEmpty || !rest.startsWith('--')) {
      return rest.isEmpty;
    }
    rest = rest.substring(2).trimLeft();
    if (rest.isEmpty) return true;
    final next = _nextLookupCmd.firstMatch(rest);
    if (next == null) return true;
    if (rest.substring(0, next.start).trim().isEmpty) return false;
    rest = rest.substring(next.start).trimLeft();
  }
  return false;
}

LookupForceParse _parseCommands(String suffix, {required String prefixBody}) {
  var rest = suffix.trim();
  String? web;
  String? wiki;
  while (rest.isNotEmpty) {
    final match = _lookupCmd.firstMatch(rest);
    if (match == null) {
      return const LookupForceParse._(
        attempted: true,
        error: kLookupForceUsage,
      );
    }
    final kind = match.group(1)!.toLowerCase();
    rest = rest.substring(match.end).trimLeft();
    if (!rest.startsWith('--')) {
      return const LookupForceParse._(
        attempted: true,
        error: kLookupForceUsage,
      );
    }
    rest = rest.substring(2).trimLeft();
    final next = rest.isEmpty ? null : _nextLookupCmd.firstMatch(rest);
    final query = (next == null ? rest : rest.substring(0, next.start)).trim();
    if (query.isEmpty) {
      return const LookupForceParse._(
        attempted: true,
        error: kLookupForceUsage,
      );
    }
    if (kind == 'search') {
      if (web != null) {
        return const LookupForceParse._(attempted: true, error: _kLookupOnce);
      }
      web = query;
    } else {
      if (wiki != null) {
        return const LookupForceParse._(attempted: true, error: _kLookupOnce);
      }
      wiki = query;
    }
    rest = next == null ? '' : rest.substring(next.start).trimLeft();
  }
  return LookupForceParse._(
    attempted: true,
    body: prefixBody.trim(),
    webQuery: web,
    wikiQuery: wiki,
  );
}
