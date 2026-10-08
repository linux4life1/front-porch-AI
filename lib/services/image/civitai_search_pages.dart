// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/image/civitai_client.dart';

enum CivitaiHttpKind { ok, needsCredential, locked, failed }

/// 401 asks for a key. 403 is a locked file and is not retried.
CivitaiHttpKind civitaiHttpKind(int status) {
  if (status == 200) return CivitaiHttpKind.ok;
  if (status == 401) return CivitaiHttpKind.needsCredential;
  if (status == 403) return CivitaiHttpKind.locked;
  return CivitaiHttpKind.failed;
}

/// What to show after a CivitAI search. Empty means the rows are the result.
/// [scanned] results were looked through and CivitAI has [more].
String civitaiSearchNote({
  required CivitaiHttpKind kind,
  required bool hadKey,
  required int rows,
  bool more = false,
  int scanned = 0,
}) {
  switch (kind) {
    case CivitaiHttpKind.needsCredential:
      return hadKey
          ? 'That API key was refused. Paste a valid key and search again.'
          : 'Paste an API key to search adult models.';
    case CivitaiHttpKind.locked:
      return 'CivitAI refused this search.';
    case CivitaiHttpKind.failed:
      return 'CivitAI search failed.';
    case CivitaiHttpKind.ok:
      if (rows > 0) return '';
      if (more && scanned > 0) {
        return 'No matches in the first $scanned results. Try a different '
            'word, or Load more.';
      }
      return 'CivitAI returned no models for that search.';
  }
}

/// One CivitAI request: the HTTP status and body.
typedef CivitaiSearchCall =
    Future<({int status, String body})> Function(
      Uri uri,
      Map<String, String> headers,
    );

Future<({int status, String body})> civitaiHttpSearch(
  Uri uri,
  Map<String, String> headers,
) async {
  final response = await http
      .get(uri, headers: headers)
      .timeout(const Duration(seconds: 20));
  return (status: response.statusCode, body: response.body);
}

Map? _decoded(String body) {
  try {
    final decoded = jsonDecode(body);
    return decoded is Map ? decoded : null;
  } on FormatException {
    return null;
  }
}

/// Where the next page starts, from `metadata.nextCursor`; null at the end.
String? civitaiNextCursor(String body) {
  final metadata = _decoded(body)?['metadata'];
  if (metadata is! Map) return null;
  final cursor = metadata['nextCursor'];
  if (cursor == null) return null;
  final text = cursor.toString().trim();
  return text.isEmpty ? null : text;
}

/// What a paged search found.
class CivitaiSearchPages {
  final List<CivitaiModelRow> rows;

  /// Where Load more carries on; null when CivitAI has nothing more.
  final String? nextCursor;

  /// [CivitaiHttpKind.ok], or the answer that stopped it.
  final CivitaiHttpKind kind;

  /// Word matches CivitAI looked through: a page's worth for each page, as
  /// it keeps the asked-for bases only after taking a page of matches.
  final int scanned;
  final int pages;

  const CivitaiSearchPages({
    required this.rows,
    required this.nextCursor,
    required this.kind,
    required this.scanned,
    required this.pages,
  });

  bool get exhausted => nextCursor == null;

  String note({required bool hadKey}) => civitaiSearchNote(
    kind: kind,
    hadKey: hadKey,
    rows: rows.length,
    more: !exhausted,
    scanned: scanned,
  );
}

/// Follows CivitAI's `nextCursor` from [first] (or from [cursor]) until
/// [enough] rows, [maxPages] pages, or [budget] has gone by. CivitAI matches
/// a word first and only then keeps the bases asked for, page by page, so a
/// first page can be empty while later ones are not. Rows are kept once per
/// model. A refused page stops it, keeping what came before.
Future<CivitaiSearchPages> civitaiSearchPages({
  required Uri first,
  required Map<String, String> headers,
  required bool includeAdult,
  CivitaiSearchCall get = civitaiHttpSearch,
  String? cursor,
  int enough = 20,
  int maxPages = 5,
  Duration budget = const Duration(seconds: 15),
}) async {
  final clock = Stopwatch()..start();
  final perPage = int.tryParse(first.queryParameters['limit'] ?? '') ?? 20;
  final rows = <CivitaiModelRow>[];
  final seen = <int>{};
  final asked = <String>{};
  var next = cursor;
  var scanned = 0;
  var pages = 0;
  while (true) {
    final uri = next == null
        ? first
        : first.replace(
            queryParameters: {...first.queryParametersAll, 'cursor': next},
          );
    final response = await get(uri, headers);
    final kind = civitaiHttpKind(response.status);
    if (kind != CivitaiHttpKind.ok) {
      return CivitaiSearchPages(
        rows: rows,
        nextCursor: next,
        kind: kind,
        scanned: scanned,
        pages: pages,
      );
    }
    pages++;
    scanned += perPage;
    for (final row in parseCivitaiModels(
      response.body,
      includeAdult: includeAdult,
    )) {
      if (seen.add(row.id)) rows.add(row);
    }
    if (next != null) asked.add(next);
    next = civitaiNextCursor(response.body);
    if (next != null && asked.contains(next)) next = null;
    if (next == null ||
        rows.length >= enough ||
        pages >= maxPages ||
        clock.elapsed >= budget) {
      return CivitaiSearchPages(
        rows: rows,
        nextCursor: next,
        kind: CivitaiHttpKind.ok,
        scanned: scanned,
        pages: pages,
      );
    }
  }
}
