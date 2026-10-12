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

import 'package:front_porch_ai/services/image/civitai_client.dart';
import 'package:front_porch_ai/services/image/civitai_credentials.dart';
import 'package:front_porch_ai/services/image/civitai_search_pages.dart';

import '../studio_civitai_key.dart';

typedef CivitaiAsked = ({String query, String base, bool adult});

/// The search results on the sheet. A newer search replaces an older one, so
/// the list on screen is always the answer to the last thing asked.
class CivitaiSearchResults {
  List<CivitaiModelRow> rows = const [];

  /// What the rows on screen were searched for, and where Load more starts.
  CivitaiAsked? asked;
  String? cursor;
  bool searching = false;

  /// The sheet's error is what the last search said, so it goes with its
  /// results.
  bool errorFromSearch = false;
  String _lastWords = '';
  int _seq = 0;

  /// Starts a search; the returned number is current until the next one.
  int begin() => ++_seq;

  bool isCurrent(int seq) => seq == _seq;

  /// Drops a search under way: its answer will no longer be current.
  void drop() {
    _seq++;
    searching = false;
  }

  /// A new base, new words or the adult box make the rows on screen the
  /// answer to something no longer asked: they go, with Load more, until
  /// Search is pressed again. A search still under way is dropped too. True
  /// when the sheet's error came from a search and must go as well. Call
  /// inside a state change.
  bool clear() {
    drop();
    rows = const [];
    cursor = null;
    asked = null;
    final fromSearch = errorFromSearch;
    errorFromSearch = false;
    return fromSearch;
  }

  /// True when new [words] leave results on screen that must be cleared.
  bool wordsChanged(String words) {
    if (words == _lastWords) return false;
    _lastWords = words;
    return rows.isNotEmpty || cursor != null || searching || errorFromSearch;
  }
}

/// One CivitAI search page: [found] is false when no key let the search run
/// (then [note] says so and nothing was asked).
typedef CivitaiSearchPage = ({
  bool found,
  List<CivitaiModelRow> rows,
  String? cursor,
  String note,
});

/// Plans and runs one search for [asked], carrying on from [cursor] after
/// the rows already in [have]. Null once [current] says a newer search or a
/// change on the sheet has replaced this one.
Future<CivitaiSearchPage?> fetchCivitaiSearchPage({
  required CivitaiAsked asked,
  required bool lora,
  required CivitaiSearchCall get,
  required String? cursor,
  required List<CivitaiModelRow> have,
  required CivitaiKeyController keys,
  required bool Function() current,
}) async {
  final relay = CivitaiRelay(await CivitaiCredentialStore.open());
  final plan = await relay.planSearch(
    accountId: 'local',
    query: asked.query,
    adult: asked.adult,
    lora: lora,
    baseModel: asked.base,
  );
  if (!current()) return null;
  if (plan.needsCredential || plan.uri == null) {
    return (
      found: false,
      rows: const <CivitaiModelRow>[],
      cursor: null,
      note: civitaiSearchNote(
        kind: CivitaiHttpKind.needsCredential,
        hadKey: keys.saved,
        rows: 0,
      ),
    );
  }
  final found = await civitaiSearchPages(
    first: plan.uri!,
    headers: {
      if (plan.authorization != null) 'Authorization': plan.authorization!,
    },
    includeAdult: asked.adult,
    get: get,
    cursor: cursor,
  );
  if (!current()) return null;
  final rows = cursor != null ? _withNew(have, found.rows) : found.rows;
  return (
    found: true,
    rows: rows,
    cursor: found.nextCursor,
    note: civitaiSearchNote(
      kind: found.kind,
      hadKey: keys.saved || plan.authorization != null,
      rows: found.kind == CivitaiHttpKind.ok ? rows.length : 0,
      more: !found.exhausted,
      scanned: found.scanned,
    ),
  );
}

/// [have] then the rows of [next] not already in it.
List<CivitaiModelRow> _withNew(
  List<CivitaiModelRow> have,
  List<CivitaiModelRow> next,
) {
  final ids = {for (final row in have) row.id};
  return [...have, ...next.where((row) => ids.add(row.id))];
}
