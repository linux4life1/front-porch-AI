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

import 'journal_ops.dart';
import 'journal_store.dart';

/// The Journal — proposals + the ONE applier (docs/design/journal-memory.md
/// §4.3 review-first mode, phase 4).
///
/// The maintenance pass resolves every parsed [JournalOp] into a
/// [JournalProposedOp] — handles become card ids, emotion stamps are read
/// from message metadata — at pass time, while the window and card snapshot
/// are live. [JournalReview.applyOwnerProposals] is then the single write
/// path for BOTH modes: normal mode applies immediately; review-first parks
/// the batch here for the user, and [apply]/[discard] settle it later. One
/// applier, so review mode can never drift from the immediate behavior.
///
/// A parked batch is in-memory and strictly session-guarded: switching chats
/// orphans it harmlessly (no writes, no cursor moves), and it's replaced by
/// the next force pass. If it's lost (app restart), the cursor never moved,
/// so the same window is simply re-proposed later — no data loss possible.
class JournalProposedOp {
  final JournalOpAction action;

  /// Resolved target card id (revise/retire/pin) — resolved at pass time so
  /// later user edits in the Journal dialog can't shift 1-based handles.
  final String? cardId;

  /// The target card's text at proposal time (review UI display).
  final String? oldContent;

  /// New content (add/revise).
  final String text;
  final String category;

  /// Revised feeling (revise ops).
  final String? feeling;

  /// Deterministic emotion stamp read from the cited messages (add ops).
  final String? emotionLabel;
  final String? emotionIntensity;

  final List<int> sourcePositions;

  /// Review checkbox state; every op ships accepted.
  bool accepted = true;

  /// Deterministic story-date stamp (story-calendar §4), resolved from the
  /// cited messages' realism_state at proposal time — same snapshot-while-live
  /// contract as the emotion stamp.
  final int? storyDay;
  final String? storyClock;

  JournalProposedOp({
    required this.action,
    this.cardId,
    this.oldContent,
    this.text = '',
    this.category = 'moment',
    this.feeling,
    this.emotionLabel,
    this.emotionIntensity,
    this.sourcePositions = const [],
    this.storyDay,
    this.storyClock,
  });
}

class JournalOwnerProposals {
  final String ownerId;
  final String ownerName;
  final List<JournalProposedOp> ops;

  JournalOwnerProposals({
    required this.ownerId,
    required this.ownerName,
    required this.ops,
  });
}

class JournalReviewBatch {
  final String sessionId;

  /// Where the pass cursor lands once this batch is settled (the message
  /// count captured at pass time).
  final int cursorTarget;
  final List<JournalOwnerProposals> owners;

  /// Proposed "Where we are" recap (chat-level, from the first owner's call).
  final String? recap;
  bool recapAccepted = true;

  JournalReviewBatch({
    required this.sessionId,
    required this.cursorTarget,
    required this.owners,
    this.recap,
  });

  int get totalProposals =>
      owners.fold(0, (n, o) => n + o.ops.length) + (recap == null ? 0 : 1);
}

class JournalReview {
  final JournalStore store;
  final String? Function() getSessionId;
  final void Function(String) setRecap;
  final void Function(int) setCursor;
  final Future<void> Function() onSaveChat;
  final VoidCallback onNotify;
  final int Function() getMaxCards;

  JournalReview({
    required this.store,
    required this.getSessionId,
    required this.setRecap,
    required this.setCursor,
    required this.onSaveChat,
    required this.onNotify,
    required this.getMaxCards,
  });

  JournalReviewBatch? _pending;
  JournalReviewBatch? get pending => _pending;

  bool hasPendingFor(String? sessionId) =>
      _pending != null && sessionId != null && _pending!.sessionId == sessionId;

  /// Park a batch for user review (review-first mode). Replaces any previous
  /// batch — a force regen proposes fresh.
  void park(JournalReviewBatch batch) {
    _pending = batch;
    onNotify();
  }

  /// The single write path for one owner's proposals — used immediately by
  /// the maintenance pass in normal mode and by [apply] in review mode.
  /// Unaccepted ops are skipped; ops whose target card vanished (user retired
  /// it in the dialog meanwhile) are skipped silently.
  Future<void> applyOwnerProposals(
    String sessionId,
    JournalOwnerProposals owner,
  ) async {
    final cards = await store.cardsFor(sessionId, owner.ownerId);
    final byId = {for (final c in cards) c.id: c};
    for (final op in owner.ops) {
      if (!op.accepted) continue;
      switch (op.action) {
        case JournalOpAction.add:
          await store.addCard(
            sessionId: sessionId,
            characterId: owner.ownerId,
            content: op.text,
            category: op.category,
            emotionLabel: op.emotionLabel,
            emotionIntensity: op.emotionIntensity,
            sourcePositions: op.sourcePositions,
            storyDay: op.storyDay,
            storyClock: op.storyClock,
            maxCards: getMaxCards(),
          );
          break;
        case JournalOpAction.revise:
          final card = byId[op.cardId];
          if (card == null) continue;
          await store.reviseCard(card, content: op.text, feeling: op.feeling);
          break;
        case JournalOpAction.retire:
          if (op.cardId == null || !byId.containsKey(op.cardId)) continue;
          await store.retireCard(op.cardId!);
          break;
        case JournalOpAction.pin:
          if (op.cardId == null || !byId.containsKey(op.cardId)) continue;
          await store.setPinned(op.cardId!, true);
          break;
      }
    }
    // Vector whatever the ops produced so cold-card recall can find it.
    await store.embedMissing(sessionId, owner.ownerId);
  }

  /// Commit the pending batch: accepted ops, the recap if accepted, cursor
  /// past the reviewed window, persist. A batch from another chat is dropped
  /// without writing anything.
  Future<void> apply() async {
    final batch = _pending;
    if (batch == null) return;
    if (getSessionId() != batch.sessionId) {
      _pending = null;
      onNotify();
      return;
    }
    // Keep _pending SET during the writes: that's what makes hasPendingFor()
    // still block a competing auto-pass (_maybeRunJournalPass), so a generation
    // finishing mid-apply can't reprocess the same window into duplicate cards.
    // Advance the cursor + clear _pending only AFTER every write succeeds, so a
    // write failure leaves the batch intact for retry instead of silently
    // abandoning accepted proposals (the earlier "advance first" version fixed
    // the race but introduced that loss).
    for (final owner in batch.owners) {
      await applyOwnerProposals(batch.sessionId, owner);
    }
    if (batch.recap != null && batch.recapAccepted) setRecap(batch.recap!);
    setCursor(batch.cursorTarget);
    _pending = null;
    await onSaveChat();
    onNotify();
    debugPrint('[Journal] ✓ Review applied (${batch.totalProposals} proposal(s))');
  }

  /// Dismiss without writing: the window counts as handled (cursor advances)
  /// so it isn't re-proposed forever; the transcript itself stays in RAG.
  Future<void> discard() async {
    final batch = _pending;
    _pending = null;
    if (batch == null) return;
    if (getSessionId() == batch.sessionId) {
      setCursor(batch.cursorTarget);
      await onSaveChat();
    }
    onNotify();
    debugPrint('[Journal] ✗ Review discarded');
  }
}
