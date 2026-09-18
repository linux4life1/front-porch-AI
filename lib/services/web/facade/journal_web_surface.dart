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

import 'dart:convert';

import 'package:front_porch_ai/database/database.dart' show JournalMemoryData;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/chat.dart';

/// Web Journal diary surface (audit P2.12) — Growth's twin for memory cards.
/// Plant / edit / pin / retire + review-first park/apply/discard, all via the
/// same [JournalStore] / [JournalReview] the desktop dialog uses so behaviour
/// cannot diverge. Kept as its own class so [ChatToolsFacade] stays under the
/// 1,000-line ratchet.
class JournalWebSurface {
  JournalWebSurface({
    required this.chat,
    required this.storage,
    required this.notify,
    required this.resolveOwner,
  });

  final ChatService chat;
  final StorageService storage;
  final void Function() notify;
  final ChatParticipant? Function(String? participantId) resolveOwner;

  /// Cards + pass/review state for the focused diary owner.
  Future<Map<String, dynamic>> list(String? participantId) async {
    final owner = resolveOwner(participantId);
    final sessionId = chat.currentSessionId;
    if (owner == null || sessionId == null) {
      return {
        'name': '',
        'ownerId': '',
        'cards': const [],
        'passRunning': false,
        'reviewPending': 0,
      };
    }
    final cards = await chat.journalStore.cardsFor(sessionId, owner.id);
    final pending = chat.journalReview.hasPendingFor(sessionId)
        ? chat.journalReview.pending!.totalProposals
        : 0;
    return {
      'name': owner.name,
      'ownerId': owner.id,
      'passRunning': chat.isSummaryGenerating,
      'reviewPending': pending,
      'cards': [
        for (final c in cards)
          {
            'id': c.id,
            'content': c.content,
            'category': c.category,
            'feeling': c.emotionLabel,
            'intensity': c.emotionIntensity,
            'pinned': c.pinned,
            'heat': c.heat,
            'storyDay': JournalStore.stampOf(c).$1,
            'receipts': _receiptsOf(c),
          },
      ],
    };
  }

  /// One diary mutation — same store surface the desktop journal dialog uses.
  Future<Map<String, dynamic>> action(
    String? participantId,
    String action,
    Map<String, dynamic> body,
  ) async {
    final owner = resolveOwner(participantId);
    final sessionId = chat.currentSessionId;
    if (owner == null || sessionId == null) {
      return list(participantId);
    }
    final cardId = body['cardId'] as String? ?? '';
    switch (action) {
      case 'plant':
        final text = (body['text'] as String? ?? '').trim();
        if (text.isNotEmpty) {
          await chat.journalStore.addCard(
            sessionId: sessionId,
            characterId: owner.id,
            content: text,
            category: body['category'] as String? ?? 'moment',
            emotionLabel: body['feeling'] as String?,
            storyDay: chat.timeService.dayCount,
            storyClock: chat.timeService.storyClockIso,
            maxCards: storage.memorySettings.journalMaxCards,
          );
        }
        break;
      case 'edit':
        final card = await _ownedCard(cardId, sessionId, owner.id);
        if (card != null) {
          await chat.journalStore.reviseCard(
            card,
            content: body['text'] as String? ?? card.content,
            feeling: body['feeling'] as String?,
          );
        }
        break;
      case 'pin':
        final card = await _ownedCard(cardId, sessionId, owner.id);
        if (card != null) {
          await chat.journalStore.setPinned(card.id, !card.pinned);
        }
        break;
      case 'retire':
        final card = await _ownedCard(cardId, sessionId, owner.id);
        if (card != null) {
          await chat.journalStore.retireCard(card.id);
        }
        break;
      case 'check':
        await chat.forceSummaryUpdate();
        break;
    }
    notify();
    return list(participantId);
  }

  /// Parked review-first batch (default OFF), flat for the web modal.
  Map<String, dynamic> reviewBatch() {
    final batch = chat.journalReview.pending;
    if (batch == null || batch.sessionId != chat.currentSessionId) {
      return {'pending': false, 'owners': const [], 'recap': null};
    }
    return {
      'pending': true,
      'recap': batch.recap,
      'recapAccepted': batch.recapAccepted,
      'owners': [
        for (final owner in batch.owners)
          {
            'ownerName': owner.ownerName,
            'ops': [
              for (final op in owner.ops)
                {
                  'action': op.action.name,
                  'text': op.text,
                  'oldContent': op.oldContent ?? '',
                  'category': op.category,
                  'feeling': op.feeling ?? op.emotionLabel ?? '',
                },
            ],
          },
      ],
    };
  }

  /// Settle parked batch: [rejected] keys are `"o:i"`; optional recapAccepted
  /// drops the proposed recap. Apply uses the same applier as autonomous mode.
  Future<Map<String, dynamic>> settleReview({
    required bool apply,
    List<String> rejected = const [],
    bool? recapAccepted,
  }) async {
    final batch = chat.journalReview.pending;
    if (batch != null) {
      if (recapAccepted != null) batch.recapAccepted = recapAccepted;
      for (var o = 0; o < batch.owners.length; o++) {
        final ops = batch.owners[o].ops;
        for (var i = 0; i < ops.length; i++) {
          if (rejected.contains('$o:$i')) ops[i].accepted = false;
        }
      }
    }
    if (apply) {
      await chat.journalReview.apply();
    } else {
      await chat.journalReview.discard();
    }
    notify();
    return reviewBatch();
  }

  /// Same owner-scope Growth uses via [ChatService.growthRingsForOwner]:
  /// a card from another chat or diary is a no-op, not a cross-owner write.
  Future<JournalMemoryData?> _ownedCard(
    String cardId,
    String sessionId,
    String ownerId,
  ) async {
    final card = await chat.journalStore.findCardById(cardId);
    if (card == null) return null;
    if (card.sessionId != sessionId || card.characterId != ownerId) {
      return null;
    }
    return card;
  }

  static List<int> _receiptsOf(JournalMemoryData card) {
    final raw = card.sourceMessageIds;
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final e in decoded)
          if (e is num)
            e.toInt()
          else if (int.tryParse('$e') != null)
            int.parse('$e'),
      ];
    } catch (_) {
      return const [];
    }
  }
}
