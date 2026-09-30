// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Journal / Growth / RAG timeline invalidation. Extracted from
// chat_service_message_ops.dart so that file stays under 500 lines.

part of '../chat_service.dart';

extension ChatServiceTimeline on ChatService {
  /// Cards/rings citing positions ≥ [position] describe events that no
  /// longer happened. Cursor rollback stays gated on recap window.
  /// [thenReplantPlanted] re-sows this swipe's item cards after the purge.
  void _invalidateJournalFrom(int position, {ChatMessage? thenReplantPlanted}) {
    final sessionId = _currentSessionId;
    if (sessionId == null) return;
    _journalReview.abandon();
    _growthReview.abandon();
    final rewriteInsideRecap = position < _summaryLastIndex;
    if (rewriteInsideRecap) {
      _summaryLastIndex = position;
    }

    var recapCleared = false;
    final transcriptGone = _messages.isEmpty;
    if (_summary.isNotEmpty && (rewriteInsideRecap || transcriptGone)) {
      _summary = '';
      _recapClearArmed = true;
      recapCleared = true;
      unawaited(_journalStore.persistRecap(sessionId, ''));
      if (transcriptGone) {
        _summaryLastIndex = 0;
      }
      debugPrint(
        '[Journal] Timeline rewrite at $position — cleared stale recap '
        '(refill on next journal pass)',
      );
    }

    unawaited(
      _journalStore
          .invalidateCardsCitingFrom(sessionId, position)
          .then((removed) async {
            if (_disposed) return;
            if (thenReplantPlanted != null) {
              await _replantItemCards(
                thenReplantPlanted,
                key: 'item_cards_planted',
              );
            }
            if (removed > 0 || recapCleared) {
              _journalMaintenance.eventKickPending = true;
            }
            if (removed > 0) {
              debugPrint(
                '[Journal] Timeline rewrite at $position — removed $removed '
                'card(s) citing the discarded region',
              );
            }
            if (removed > 0 || recapCleared) notifyListeners();
          })
          .catchError((Object e) {
            debugPrint(
              '[Journal] ⚠ card invalidation at $position skipped: $e',
            );
            if (!_disposed && recapCleared) {
              _journalMaintenance.eventKickPending = true;
              notifyListeners();
            }
          }),
    );

    unawaited(_invalidateGrowthFrom(sessionId, position));
    unawaited(_invalidateEmbeddingsFrom(sessionId, position));

    if (recapCleared) {
      _journalMaintenance.eventKickPending = true;
      notifyListeners();
    }
  }

  Future<void> _invalidateGrowthFrom(String sessionId, int position) async {
    try {
      final cursor = await _growthStore.cursorFor(sessionId);
      if (position < cursor) {
        await _growthStore.setCursor(sessionId, position);
        debugPrint(
          '[Growth] Timeline rewrite at $position — cursor rolled back '
          'from $cursor',
        );
      }
      final removed = await _growthStore.invalidateRingsCitingFrom(
        sessionId,
        position,
      );
      if (_disposed) return;
      if (removed > 0) {
        debugPrint(
          '[Growth] Timeline rewrite at $position — removed $removed '
          'ring(s) citing the discarded region',
        );
        await _refreshGrowthCache();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[Growth] ⚠ ring invalidation at $position skipped: $e');
    }
  }

  Future<void> _invalidateEmbeddingsFrom(String sessionId, int position) async {
    try {
      final removed = await _db.customUpdate(
        'DELETE FROM message_embeddings '
        'WHERE session_id = ? AND position_end >= ?',
        variables: [drift.Variable(sessionId), drift.Variable(position)],
        updates: {_db.messageEmbeddings},
      );
      if (removed > 0) {
        debugPrint(
          '[RAG] Timeline rewrite at $position — removed $removed embedded '
          'window(s) citing the discarded region',
        );
      }
    } catch (e) {
      debugPrint('[RAG] ⚠ embedding invalidation at $position skipped: $e');
    }
  }
}
