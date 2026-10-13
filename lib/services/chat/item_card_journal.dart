// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/database/database.dart'
    show AppDatabase, AppDatabaseMemoryQueries;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/item_card_stamps.dart';
import 'package:front_porch_ai/services/chat/journal_physics.dart';
import 'package:front_porch_ai/services/chat/journal_store.dart';
import 'package:front_porch_ai/services/chat/pocket_journal_cards.dart';
import 'package:front_porch_ai/services/chat/pockets.dart';
import 'package:front_porch_ai/services/chat/session_open_window.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';
import 'package:front_porch_ai/services/storage/settings/memory_settings.dart';

/// Item-memory Journal cards: written from applied pocket events (only when
/// both Pockets and the Journal are on — the caller holds that gate),
/// retired by the eraser, stamped on the swipe, and re-planted on rewind.
class ItemCardJournal {
  ItemCardJournal({
    required this.messages,
    required this.history,
    required this.currentSessionId,
    required this.journalStore,
    required this.db,
    required this.time,
    required this.memorySettings,
    required this.activeCharacterName,
  });

  /// The chat's in-memory message list (the same list object, not a copy).
  final List<ChatMessage> messages;
  final SessionHistoryWindow history;
  final String? Function() currentSessionId;
  final JournalStore Function() journalStore;
  final AppDatabase Function() db;
  final TimeService Function() time;
  final MemorySettings Function() memorySettings;
  final String? Function() activeCharacterName;

  List<ChatMessage> get _messages => messages;
  SessionHistoryWindow get _history => history;

  /// Retire every live item-memory card about [itemName] for [ownerId].
  /// Shared by the post-gen feed (one live placement per item) and the
  /// eraser (`PocketsLedger.removePocketItem`) so neither path leaves a
  /// phantom diary.
  Future<void> retireFor(String ownerId, String itemName) async {
    final sid = currentSessionId();
    if (sid == null || itemName.isEmpty) return;
    final existing = await journalStore().cardsFor(sid, ownerId);
    for (final old in existing) {
      if (JournalPhysics.isItemCard(old) &&
          sameItem(JournalPhysics.itemOf(old) ?? '', itemName)) {
        await journalStore().retireCard(old.id);
      }
    }
  }

  /// Write this turn's item-memory cards ([itemCardsFrom] decides which
  /// events are diary-worthy). One live placement memory per item: a new
  /// card about the same thing retires the old one first, so "where are my
  /// keys" always has exactly one answer in the diary. Cards carry the
  /// canonical item name in the metadata pouch (the keyword re-warm key),
  /// the story stamp, and the reply's **persist** position as their receipt
  /// — a tail window must cite base+index, not the on-screen 0..23.
  Future<void> write(
    String ownerId,
    List<PocketEvent> events, {
    required bool asContinuation,
  }) async {
    // A retire is a hard DB delete — right while this turn stands, wrong the
    // moment it is regenerated or tail-deleted. Stamp every card this turn is
    // about to retire onto THIS SWIPE (same contract as pockets_after:
    // replace on a normal turn, append on Continue) so the rewind can
    // re-plant them without copying swipe 0's retires onto swipe 1.
    final stamps = <ItemCardStamp>[];
    final planted = <ItemCardStamp>[];
    // Pickup writes no diary line but must retire the old placement card
    // ("I set my keys down") or "where are my keys?" stays wrong.
    for (final e in events) {
      if (e.kind == PocketOpKind.pickup) {
        final sid = currentSessionId();
        if (sid != null) {
          stamps.addAll(
            itemCardStampsFrom(
              await db().getJournalCardsForSession(sid),
              e.item,
            ),
          );
          await journalStore().retireItemCardsInSession(sid, e.item);
        } else {
          await retireFor(ownerId, e.item);
        }
      }
    }
    final drafts = itemCardsFrom(events);
    if (drafts.isEmpty) {
      _stamp(stamps, key: 'item_cards_retired', asContinuation: asContinuation);
      return;
    }
    final sid = currentSessionId()!;
    final cite = persistTipCite(
      base: _history.basePosition,
      length: _messages.length,
    );
    for (final draft in drafts) {
      stamps.addAll(
        itemCardStampsFrom(
          await journalStore().cardsFor(sid, ownerId),
          draft.item,
        ),
      );
      await retireFor(ownerId, draft.item);
      await journalStore().addCard(
        sessionId: sid,
        characterId: ownerId,
        content: draft.content,
        category: 'item',
        kind: 'item',
        extraMetadata: {'item': draft.item},
        sourcePositions: cite,
        storyDay: time().dayCount,
        storyClock: time().storyClockIso,
        maxCards: memorySettings().journalMaxCards,
      );
      planted.add(
        ItemCardStamp(
          owner: ownerId,
          item: draft.item,
          content: draft.content,
          positions: cite,
          storyDay: time().dayCount,
          storyClock: time().storyClockIso,
        ),
      );
    }
    _stamp(stamps, key: 'item_cards_retired', asContinuation: asContinuation);
    _stamp(planted, key: 'item_cards_planted', asContinuation: asContinuation);
    debugPrint(
      '[Journal] 📦 ${drafts.length} item card(s) for ${activeCharacterName()}',
    );
  }

  /// Ride item-card stamps on THIS SWIPE. Replace on a normal turn; append
  /// on Continue (the first half belongs to the same swipe). Swipe-scoped
  /// so regen of swipe 1 cannot replant swipe 0's retires. Older chats that
  /// wrote `item_cards_retired` on shared metadata still read via the
  /// activeMetadata → metadata fallback in [replant].
  void _stamp(
    List<ItemCardStamp> stamps, {
    required String key,
    required bool asContinuation,
  }) {
    if (_messages.isEmpty || _messages.last.isUser) return;
    final msg = _messages.last;
    final prior = asContinuation
        ? ItemCardStamp.listFrom(msg.activeMetadata?[key] ?? msg.metadata?[key])
        : const <ItemCardStamp>[];
    final all = [...prior, ...stamps];
    if (all.isEmpty) return;
    msg.activeMetadata = {
      ...?msg.activeMetadata,
      key: [for (final s in all) s.toJson()],
    };
  }

  /// Re-plant item cards stamped on [msg] under [key].
  /// `item_cards_retired`: regenerate / tail-delete (`after: false`).
  /// `item_cards_planted`: swipe-back after timeline invalidation.
  /// Retire-first so a double regenerate cannot duplicate a card.
  Future<void> replant(ChatMessage msg, {required String key}) async {
    final sid = currentSessionId();
    if (sid == null) return;
    final stamps = ItemCardStamp.listFrom(
      msg.activeMetadata?[key] ?? msg.metadata?[key],
    );
    for (final s in stamps) {
      try {
        await retireFor(s.owner, s.item);
        await journalStore().addCard(
          sessionId: sid,
          characterId: s.owner,
          content: s.content,
          category: 'item',
          kind: 'item',
          extraMetadata: {'item': s.item},
          sourcePositions: s.positions,
          storyDay: s.storyDay,
          storyClock: s.storyClock,
          heat: s.heat,
          pinned: s.pinned,
          maxCards: memorySettings().journalMaxCards,
        );
      } catch (e) {
        debugPrint('[Journal] item card re-plant skipped (${s.item}): $e');
      }
    }
  }
}
