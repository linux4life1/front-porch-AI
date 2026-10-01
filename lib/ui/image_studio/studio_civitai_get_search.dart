// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'studio_civitai_get.dart';

/// Searching CivitAI from the sheet: a new search, and Load more, which
/// carries on from where the last one stopped with the same words and base.
extension _CivitaiSearching on _StudioCivitaiGetState {
  Future<void> _search() => _runSearch(more: false);

  Future<void> _loadMore() => _runSearch(more: true);

  /// A newer search replaces an older one, so the list on screen is always
  /// the answer to the last thing asked.
  Future<void> _runSearch({required bool more}) async {
    if (_downloading) return;
    final from = more ? _cursor : null;
    final asked = more
        ? _asked
        : (query: _query.text.trim(), base: _base, adult: _adultNow);
    if (more && (from == null || asked == null)) return;
    final seq = ++_searchSeq;
    _set(() {
      _searching = true;
      _error = null;
      _needFolder = false;
      _offerFolder = null;
    });
    try {
      final saveError = await _keys.saveTyped();
      if (!_current(seq)) return;
      if (saveError != null) {
        _set(() => _error = saveError);
        return;
      }
      final relay = CivitaiRelay(await CivitaiCredentialStore.open());
      final plan = await relay.planSearch(
        accountId: 'local',
        query: asked!.query,
        adult: asked.adult,
        lora: widget.lora,
        baseModel: asked.base,
      );
      if (!_current(seq)) return;
      if (plan.needsCredential || plan.uri == null) {
        _set(() {
          _rows = const [];
          _cursor = null;
          _error = civitaiSearchNote(
            kind: CivitaiHttpKind.needsCredential,
            hadKey: _keys.saved,
            rows: 0,
          );
        });
        return;
      }
      final found = await civitaiSearchPages(
        first: plan.uri!,
        headers: {
          if (plan.authorization != null) 'Authorization': plan.authorization!,
        },
        includeAdult: asked.adult,
        get: widget.searchCall,
        cursor: from,
      );
      if (!_current(seq)) return;
      final rows = more ? _withNew(_rows, found.rows) : found.rows;
      final note = civitaiSearchNote(
        kind: found.kind,
        hadKey: _keys.saved || plan.authorization != null,
        rows: found.kind == CivitaiHttpKind.ok ? rows.length : 0,
        more: !found.exhausted,
        scanned: found.scanned,
      );
      _set(() {
        _rows = rows;
        _asked = asked;
        _cursor = found.nextCursor;
        _error = note.isEmpty ? null : note;
      });
    } on CivitaiKeyStoreException catch (e) {
      if (_current(seq)) _set(() => _error = e.message);
    } catch (e) {
      debugPrint('civitai search failed: ${e.runtimeType}');
      if (_current(seq)) _set(() => _error = 'CivitAI search failed.');
    } finally {
      if (_current(seq)) _set(() => _searching = false);
    }
  }
}

/// [have] then the rows of [next] not already in it.
List<CivitaiModelRow> _withNew(
  List<CivitaiModelRow> have,
  List<CivitaiModelRow> next,
) {
  final ids = {for (final row in have) row.id};
  return [...have, ...next.where((row) => ids.add(row.id))];
}
