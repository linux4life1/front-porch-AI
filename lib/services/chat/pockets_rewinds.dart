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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/item_card_journal.dart';
import 'package:front_porch_ai/services/chat/pockets.dart';
import 'package:front_porch_ai/services/chat/pockets_ledger.dart';

/// Pockets time travel: put records back from the `pockets_before` /
/// `pockets_after` stamps a reply carries (regenerate, swipe, tail delete,
/// fork and import). Writes go through [PocketsLedger.setPocketsFor], the
/// same setter the pass uses.
class PocketsRewinds {
  PocketsRewinds(this._messages, this._ledger, {required this.itemCards});

  /// The chat's in-memory message list (the same list object, not a copy).
  final List<ChatMessage> _messages;
  final PocketsLedger _ledger;
  final ItemCardJournal Function() itemCards;

  /// Restore pocket records from a message's rewind stamps — the pockets
  /// half of the time-travel every other turn effect already had (realism
  /// scalars via realism_state, needs via the arithmetic refund, journal
  /// cards via timeline invalidation). [after] picks the swipe's post-turn
  /// state (swipe navigation); otherwise the turn's pre-state (regenerate,
  /// tail delete). A message with no stamps applied no ops — nothing to do.
  /// Restores the speaker AND any transfer recipients stamped under
  /// `others` / `pockets_after_others`.
  /// Fork/import: replay pocket stamps in story order so a silent
  /// recipient keeps an earlier gift when a later stamp names only the giver.
  void restoreChronologically(int start) {
    if (!_ledger.pocketsFeatureEnabled) return;
    final last = start.clamp(0, _messages.isEmpty ? 0 : _messages.length - 1);
    for (var i = 0; i <= last && i < _messages.length; i++) {
      final m = _messages[i];
      if (m.metadata?['pockets_before'] is Map) {
        restoreFromStamp(m, after: true);
      }
    }
  }

  void restoreFromStamp(ChatMessage msg, {required bool after}) {
    // Rewind (regenerate / tail-delete) un-deletes the item cards this turn
    // retired. `after: true` (cancel put-back, swipe) keeps the turn's text,
    // so its retires stand. Runs above the pockets gate deliberately: the
    // cards were written while pockets was on and must come back even if the
    // switch is off today (same rule as the RAG invalidator).
    if (!after) {
      unawaited(itemCards().replant(msg, key: 'item_cards_retired'));
    }
    if (!_ledger.pocketsFeatureEnabled) return;
    final before = msg.metadata?['pockets_before'];
    if (before is! Map) return;
    final chId = before['char'];
    if (chId is! String || chId.isEmpty) return;
    Object? recordJson = before['record'];
    if (after) {
      final a = msg.activeMetadata?['pockets_after'];
      if (a is Map) recordJson = a;
    }
    if (_ledger.pocketsWriteAllowed(chId)) {
      _ledger.setPocketsFor(chId, Pockets.fromJson(recordJson));
    }

    // Recipients of a give: same before/after contract as the speaker.
    final othersBefore = before['others'];
    if (othersBefore is! List) return;
    Map<String, Object?> afterByChar = {};
    if (after) {
      final ao = msg.activeMetadata?['pockets_after_others'];
      if (ao is List) {
        for (final e in ao) {
          if (e is Map && e['char'] is String) {
            afterByChar[e['char'] as String] = e['record'];
          }
        }
      }
    }
    for (final o in othersBefore) {
      if (o is! Map) continue;
      final oid = o['char'];
      if (oid is! String || oid.isEmpty) continue;
      Object? oRec = o['record'];
      if (after && afterByChar.containsKey(oid)) {
        oRec = afterByChar[oid];
      }
      if (_ledger.pocketsWriteAllowed(oid)) {
        _ledger.setPocketsFor(oid, Pockets.fromJson(oRec));
      }
    }
  }
}
