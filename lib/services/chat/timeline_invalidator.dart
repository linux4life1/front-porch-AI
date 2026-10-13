// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/database/database.dart' show AppDatabase;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/growth_desk.dart';
import 'package:front_porch_ai/services/chat/growth_review.dart';
import 'package:front_porch_ai/services/chat/growth_store.dart';
import 'package:front_porch_ai/services/chat/item_card_journal.dart';
import 'package:front_porch_ai/services/chat/journal_maintenance.dart';
import 'package:front_porch_ai/services/chat/journal_review.dart';
import 'package:front_porch_ai/services/chat/journal_store.dart';

/// Journal / Growth / RAG timeline invalidation: an edit, regenerate or
/// delete rewrites history from a persist position, and every memory
/// citing that region is purged (cards, rings, embedded windows), the
/// recap cursor rolls back, and this swipe's item cards can be re-sown.
class TimelineInvalidator {
  TimelineInvalidator({
    required this.messages,
    required this.currentSessionId,
    required this.summary,
    required this.setSummary,
    required this.armRecapClear,
    required this.summaryLastIndex,
    required this.setSummaryLastIndex,
    required this.journalStore,
    required this.journalReview,
    required this.journalMaintenance,
    required this.growthStore,
    required this.growthReview,
    required this.growth,
    required this.itemCards,
    required this.db,
    required this.disposed,
    required this.notify,
  });

  /// The chat's in-memory message list (the same list object, not a copy).
  final List<ChatMessage> messages;
  final String? Function() currentSessionId;

  /// The "Where we are" recap and its cursor (`_summary`,
  /// `_summaryLastIndex`); [armRecapClear] sets `_recapClearArmed`.
  final String Function() summary;
  final void Function(String) setSummary;
  final void Function() armRecapClear;
  final int Function() summaryLastIndex;
  final void Function(int) setSummaryLastIndex;
  final JournalStore Function() journalStore;
  final JournalReview Function() journalReview;
  final JournalMaintenance Function() journalMaintenance;
  final GrowthStore Function() growthStore;
  final GrowthReview Function() growthReview;
  final GrowthDesk Function() growth;
  final ItemCardJournal Function() itemCards;
  final AppDatabase Function() db;
  final bool Function() disposed;
  final void Function() notify;

  List<ChatMessage> get _messages => messages;
  String? get _currentSessionId => currentSessionId();
  JournalStore get _journalStore => journalStore();
  JournalReview get _journalReview => journalReview();
  JournalMaintenance get _journalMaintenance => journalMaintenance();
  GrowthStore get _growthStore => growthStore();
  GrowthReview get _growthReview => growthReview();
  bool get _disposed => disposed();

  /// Cards/rings citing positions ≥ [position] describe events that no
  /// longer happened. Cursor rollback stays gated on recap window.
  /// [thenReplantPlanted] re-sows this swipe's item cards after the purge.
  void invalidateFrom(int position, {ChatMessage? thenReplantPlanted}) {
    final sessionId = _currentSessionId;
    if (sessionId == null) return;
    _journalReview.abandon();
    _growthReview.abandon();
    final rewriteInsideRecap = position < summaryLastIndex();
    if (rewriteInsideRecap) {
      setSummaryLastIndex(position);
    }

    var recapCleared = false;
    final transcriptGone = _messages.isEmpty;
    if (summary().isNotEmpty && (rewriteInsideRecap || transcriptGone)) {
      setSummary('');
      armRecapClear();
      recapCleared = true;
      unawaited(_journalStore.persistRecap(sessionId, ''));
      if (transcriptGone) {
        setSummaryLastIndex(0);
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
              await itemCards().replant(
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
            if (removed > 0 || recapCleared) notify();
          })
          .catchError((Object e) {
            debugPrint(
              '[Journal] ⚠ card invalidation at $position skipped: $e',
            );
            if (!_disposed && recapCleared) {
              _journalMaintenance.eventKickPending = true;
              notify();
            }
          }),
    );

    unawaited(_invalidateGrowthFrom(sessionId, position));
    unawaited(_invalidateEmbeddingsFrom(sessionId, position));

    if (recapCleared) {
      _journalMaintenance.eventKickPending = true;
      notify();
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
        await growth().refreshCache();
        notify();
      }
    } catch (e) {
      debugPrint('[Growth] ⚠ ring invalidation at $position skipped: $e');
    }
  }

  Future<void> _invalidateEmbeddingsFrom(String sessionId, int position) async {
    try {
      final db = this.db();
      final removed = await db.customUpdate(
        'DELETE FROM message_embeddings '
        'WHERE session_id = ? AND position_end >= ?',
        variables: [drift.Variable(sessionId), drift.Variable(position)],
        updates: {db.messageEmbeddings},
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
