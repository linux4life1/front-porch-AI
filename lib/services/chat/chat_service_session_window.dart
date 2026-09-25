// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of '../chat_service.dart';

/// Tail-first session hydrate, then a chunked background backfill of
/// everything older. The tail is what ChatPage paints; the rest pages
/// in with a yield per chunk so 11k JSON decodes cannot freeze the
/// first paint. Overlay drop belongs to the owner after scalars
/// hydrate — this method must not call [endSessionLoad]. RAG/Journal
/// wait on [_awaitHistoryHydrated] or treat [basePosition] as already
/// out of context.
extension ChatServiceSessionWindow on ChatService {
  bool get isBackfillingHistory => _history.isBackfilling;
  bool get hasOlderHistory => _history.hasMore;

  Future<int> countSessionsForCharacterId(String characterId) =>
      _db.countSessionsForCharacter(characterId);

  /// True when the picker must open. Uses the card's UUID internally —
  /// the home tap handler must not pass that UUID to [getSessionsForId].
  Future<bool> hasMultipleSavedSessions(CharacterCard card) async {
    final id = card.dbId;
    if (id == null) return true;
    return (await _db.countSessionsForCharacter(id)) > 1;
  }

  Future<void> _awaitHistoryHydrated() async {
    final pending = _history.backfill;
    if (pending != null) await pending;
  }

  /// Map a visible-list index to the post-backfill index. Captures the
  /// absolute position *before* awaiting so a fork/delete tap during the
  /// window still addresses the same row after older lines prepend.
  Future<int?> _resolveHydratedIndex(int messageIndex) async {
    if (messageIndex < 0 || messageIndex >= _messages.length) return null;
    final abs = persistMessagePosition(
      base: _history.basePosition,
      index: messageIndex,
    );
    await _awaitHistoryHydrated();
    if (abs < 0 || abs >= _messages.length) return null;
    return abs;
  }

  /// Last [kSessionOpenWindow] rows, then pages the rest in on a
  /// yielded loop. Does not drop the session overlay — scalars still
  /// hydrate after this returns, and a picker-owned load still has
  /// [loadSession] / [startNewChat] to run.
  Future<void> _openSessionMessages(String sessionId) async {
    final sw = Stopwatch()..start();
    _history.reset();
    final tail = await _db.getMessagesTailForSession(
      sessionId,
      kSessionOpenWindow,
    );
    _computeAbsenceGap(tail);
    _messages.clear();
    _hydrateMessagesFromRows(tail);
    if (tail.isNotEmpty) {
      _history.basePosition = tail.first.position;
      _history.hasMore = tail.first.position > 0;
    }
    debugPrint(
      '[ChatOpen] tail ${sw.elapsedMilliseconds}ms '
      'n=${tail.length} base=${_history.basePosition} '
      'hasMore=${_history.hasMore} session=$sessionId',
    );
    if (_history.hasMore) {
      final epoch = _history.epoch;
      _history.backfill = _runBackgroundBackfill(sessionId, epoch);
    }
  }

  Future<void> _runBackgroundBackfill(String sessionId, int epoch) async {
    // One frame so ChatPage paints the tail before we decode the archive.
    await Future<void>.delayed(Duration.zero);
    final sw = Stopwatch()..start();
    var pages = 0;
    try {
      while (_history.hasMore &&
          epoch == _history.epoch &&
          _currentSessionId == sessionId) {
        final more = await _prependOlderPage(sessionId, epoch);
        if (!more) break;
        pages++;
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      if (epoch == _history.epoch) {
        _history.backfill = null;
        if (!_history.hasMore) notifyListeners();
      }
      debugPrint(
        '[ChatOpen] backfill ${sw.elapsedMilliseconds}ms '
        'pages=$pages n=${_messages.length} session=$sessionId',
      );
    }
  }

  /// One older page. Returns false when the prefix is done or the
  /// session changed. The background loop notifies once at the end so
  /// idle scrolling is not rebuilt on every page.
  Future<bool> _prependOlderPage(String sessionId, int epoch) async {
    if (!_history.hasMore) return false;
    final older = await _db.getMessagesBeforePosition(
      sessionId,
      _history.basePosition,
      limit: kSessionOlderPage,
    );
    if (epoch != _history.epoch || _currentSessionId != sessionId) {
      return false;
    }
    if (older.isEmpty) {
      _history.hasMore = false;
      _history.basePosition = 0;
      return false;
    }
    final kept = List<ChatMessage>.from(_messages);
    _messages.clear();
    _hydrateMessagesFromRows(older);
    _messages.addAll(kept);
    _backfillLoadedSlotClocks();
    _history.basePosition = older.first.position;
    _history.hasMore =
        older.length == kSessionOlderPage && older.first.position > 0;
    return _history.hasMore;
  }

  /// One older page for scroll-up. No-op while the background loop
  /// is already paging newest → older, or when the prefix is done.
  Future<void> loadOlderHistory({int count = kSessionOlderPage}) async {
    if (_history.isBackfilling) return;
    final sid = _currentSessionId;
    if (sid == null || !_history.hasMore) return;
    await _prependOlderPage(sid, _history.epoch);
    notifyListeners();
  }
}
