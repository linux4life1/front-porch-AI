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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/database/database.dart' show GrowthRingData;
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/web/facade/chat_tools/chat_tools_context.dart';

/// Journal, Growth Rings, the recap, promises and the milestone timeline:
/// the memory surfaces of the chat tools sidebar. Every one delegates to the
/// store the desktop panel uses, so the two cannot drift.
class ChatToolsMemory {
  ChatToolsMemory(this._ctx);

  final ChatToolsContext _ctx;
  ChatService get _chat => _ctx.chat;
  StorageService get _storage => _ctx.storage;
  void _notify() => _ctx.notify();

  /// Growth Rings payload for the focused participant (group-aware via the
  /// same owner-id keying the desktop GrowthPanel uses; 1:1 falls back to the
  /// host). Rings ship with derived tier + decoded receipts so the web
  /// renders without re-implementing the physics.
  Map<String, dynamic> growth(String? participantId) {
    final owner = _ctx.growthOwner(participantId);
    if (owner == null) {
      return {
        'name': '',
        'ownerId': '',
        'rings': const [],
        'passRunning': false,
      };
    }
    final rings = _chat.growthRingsForOwner(owner.id);
    return {
      'name': owner.name,
      'ownerId': owner.id,
      'passRunning': _chat.isGrowthPassRunning,
      'hasLegacyBlob': _chat.hasLegacyGrowthBlobFor(owner.id),
      'reviewPending': _chat.growthReview.hasPendingFor(_chat.currentSessionId)
          ? _chat.growthReview.pending!.totalProposals
          : 0,
      // Kit offer is a CHAT fact (it names the whole cast); every member's
      // payload carries it so the panel sees it however it is focused.
      'kitOffer': _chat.growthKitOffer == null
          ? null
          : {
              'names': _chat.growthKitOffer!.names,
              'entryCount': _chat.growthKitOffer!.entryCount,
            },
      'kitReplay': _chat.growthKitReplayAvailable,
      'rings': [for (final r in rings) growthRingToJson(r)],
    };
  }

  /// One growth mutation from the web timeline — same ChatService surface the
  /// desktop panel uses, so behavior can't diverge. Unknown ids no-op.
  Future<void> growthAction(
    String? participantId,
    String action,
    Map<String, dynamic> body,
  ) async {
    final owner = _ctx.growthOwner(participantId);
    if (owner == null) return;
    final ringId = body['ringId'] as String? ?? '';
    final rings = _chat.growthRingsForOwner(owner.id);
    final ring = rings.where((r) => r.id == ringId).firstOrNull;
    switch (action) {
      case 'plant':
        await _chat.plantGrowthRingFor(
          owner.id,
          body['text'] as String? ?? '',
          category: body['category'] as String? ?? 'trait',
        );
        break;
      case 'edit':
        if (ring == null) return;
        await _chat.editGrowthRing(
          ring,
          text: body['text'] as String? ?? ring.content,
          category: body['category'] as String?,
        );
        break;
      case 'pin':
        if (ring == null) return;
        await _chat.setGrowthRingPinned(ring.id, !(ring.pinned));
        break;
      case 'retire':
        if (ring == null) return;
        await _chat.retireGrowthRing(ring.id);
        break;
      case 'restore':
        if (ring == null) return;
        await _chat.unretireGrowthRing(ring);
        break;
      case 'delete':
        if (ring == null) return;
        await _chat.deleteGrowthRing(ring.id);
        break;
      case 'undoBb':
        final sessionId = _chat.currentSessionId;
        if (ring == null || sessionId == null) return;
        await _chat.growthReview.undoBoonBogey(sessionId, owner.id, ring.id);
        break;
      case 'reset':
        await _chat.resetGrowthFor(owner.id);
        break;
      case 'check':
        await _chat.forceGrowthPass();
        break;
      case 'acceptKit':
        await _chat.acceptGrowthKit();
        break;
      case 'declineKit':
        await _chat.declineGrowthKit();
        break;
      case 'kitAgain':
        await _chat.offerGrowthKitAgain();
        break;
      // Phase-5 milestones (§7): the card's and Moments' answers, by id.
      case 'milestoneAnswer':
        lastMilestoneOutcome = (await _chat.answerMilestone(
          body['momentId'] as String? ?? '',
          accept: body['accept'] == true,
        )).name;
        break;
      case 'milestoneReplay':
        await _chat.replayMilestone(body['momentId'] as String? ?? '');
        break;
      case 'milestoneDismiss':
        _chat.dismissMilestone();
        break;
    }
    _notify();
  }

  /// What the last `milestoneAnswer` did (a [MilestoneOutcome] name), so the
  /// web card can say why it stayed up (the bogey cap is full).
  String? lastMilestoneOutcome;

  /// One owner's Moments for the web line, newest first, with the revision
  /// the list was read at (re-read when the snapshot's differs).
  Future<Map<String, dynamic>> moments(String? participantId) async {
    final owner = _ctx.growthOwner(participantId);
    return {
      'revision': _chat.milestoneRevision,
      'moments': owner == null
          ? const []
          : [
              for (final v in await _chat.milestoneViewsFor(owner.id))
                v.toJson(),
            ],
    };
  }

  /// The parked growth-review batch (review-first mode, default OFF) in a
  /// flat, index-addressed shape for the web modal.
  Map<String, dynamic> growthReviewBatch() {
    final batch = _chat.growthReview.pending;
    if (batch == null || batch.sessionId != _chat.currentSessionId) {
      return {'pending': false, 'owners': const []};
    }
    return {
      'pending': true,
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
                },
            ],
          },
      ],
    };
  }

  /// Settle the parked batch: [rejected] is a list of "ownerIdx:opIdx" keys
  /// to uncheck; the rest applies (or everything discards).
  Future<void> settleGrowthReview({
    required bool apply,
    List<String> rejected = const [],
  }) async {
    final batch = _chat.growthReview.pending;
    if (batch != null) {
      for (var o = 0; o < batch.owners.length; o++) {
        final ops = batch.owners[o].ops;
        for (var i = 0; i < ops.length; i++) {
          if (rejected.contains('$o:$i')) ops[i].accepted = false;
        }
      }
    }
    if (apply) {
      await _chat.growthReview.apply();
    } else {
      await _chat.growthReview.discard();
    }
    _notify();
  }

  // ── Summary controls ─────────────────────────────────────────────────────
  Future<void> regenerateSummary() async {
    if (!_storage.memorySettings.journalEnabled) return;
    await _chat.forceSummaryUpdate();
    _notify();
  }

  void setSummaryPaused(bool v) {
    _chat.setSummaryPaused(v);
    _notify();
  }

  void setSummaryText(String text) {
    if (!_storage.memorySettings.journalEnabled) return;
    _chat.setSummary(text);
    _notify();
  }

  /// "Our Story" milestones timeline (Living Time §7) — the same read-model
  /// the desktop journal dialog's timeline tab uses (ChatService.milestoneFeed),
  /// so the two surfaces cannot drift. Additive endpoint; owner defaults to
  /// the first diary owner like [calendar].
  Future<Map<String, dynamic>> timeline(String? ownerId) async {
    final sessionId = _chat.currentSessionId;
    final owners = _chat.cast.where((p) => !p.isLite).toList();
    final owner =
        owners.where((p) => p.id == ownerId).firstOrNull ?? owners.firstOrNull;
    final entries = <Map<String, dynamic>>[];
    if (sessionId != null && owner != null) {
      for (final e in JournalReadingOrder.timeline(
        await _chat.milestoneFeed.entriesFor(
          sessionId: sessionId,
          characterId: owner.id,
        ),
      )) {
        entries.add({
          'kind': e.kind,
          'text': e.text,
          'day': ?e.storyDay,
          'position': ?e.position,
          'emotion': ?e.emotion,
        });
      }
    }
    return {
      'owner': owner?.id,
      'owners': [
        for (final p in owners) {'id': p.id, 'name': p.name},
      ],
      'entries': entries,
    };
  }

  /// Promise ledger read (web Promises panel — desktop Journal "Promises"
  /// tab parity). Owner defaults to the first diary owner like [calendar].
  /// Additive endpoint; old clients never call it.
  Future<Map<String, dynamic>> promises(String? ownerId) async {
    final sessionId = _chat.currentSessionId;
    final owners = _chat.cast.where((p) => !p.isLite).toList();
    final owner =
        owners.where((p) => p.id == ownerId).firstOrNull ?? owners.firstOrNull;
    final rows = <Map<String, dynamic>>[];
    if (sessionId != null && owner != null) {
      for (final card in await _chat.journalStore.cardsFor(
        sessionId,
        owner.id,
      )) {
        final meta = PromiseDebtService.metaOf(card.metadata);
        if (meta['kind'] != 'promise') continue;
        final desc = meta['description'];
        rows.add({
          'id': card.id,
          'text': desc is String && desc.isNotEmpty ? desc : card.content,
          'party': (meta['party'] as String?) == 'char' ? 'char' : 'user',
          'status': (meta['status'] as String?) ?? 'open',
        });
      }
      // Open commitments first, then the kept/broken history.
      rows.sort(
        (a, b) => (a['status'] == 'open' ? 0 : 1).compareTo(
          b['status'] == 'open' ? 0 : 1,
        ),
      );
    }
    return {'owner': owner?.id, 'ownerName': owner?.name, 'promises': rows};
  }

  /// Manual kept/broken — the SAME applier as automatic detection
  /// (trust/bond deltas, milestone card, cache refresh).
  Future<bool> resolvePromise({
    required String ownerId,
    required String cardId,
    required bool kept,
  }) => _chat.resolvePromiseManually(
    characterId: ownerId,
    cardId: cardId,
    kept: kept,
  );
}

/// One growth ring on the wire — the Growth panel and the sidebar's Boons &
/// Bogies line must receive the same shape, or one surface renders a blander
/// row than the other (maintainer, 2026-11-23).
Map<String, dynamic> growthRingToJson(GrowthRingData r) => {
  'id': r.id,
  'content': r.content,
  'category': r.category,
  // Physics tier (ordinary ring grouping) and the boon/bogey tier
  // (Novice/Skilled/Master) travel separately so the web panel can render
  // both kinds without re-implementing either ladder.
  'tier': GrowthPhysics.tierOf(r),
  'kind': BoonsBogies.isBogey(r)
      ? BoonsBogies.kKindBogey
      : (BoonsBogies.isBoon(r) ? BoonsBogies.kKindBoon : null),
  'bbTier': BoonsBogies.tierOf(r),
  'advanceCount': r.advanceCount,
  'pressure': r.bogeyPressure,
  'cooldown': r.bogeyCooldown,
  'seeded': BoonsBogies.bbOf(r)[BoonsBogies.kSeededKey] == true,
  'canUndo': BoonsBogies.undoOf(r) != null,
  'strength': r.strength,
  'pinned': r.pinned,
  'retired': r.retired,
  'receipts': GrowthStore.receiptsOf(r),
};
