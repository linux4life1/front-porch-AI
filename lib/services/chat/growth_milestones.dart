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

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:uuid/uuid.dart';

import 'growth_boons_bogies.dart';
import 'growth_store.dart';

/// The five milestone moments (docs/design/boons-and-bogies.md §7), with
/// the wire strings `growth_moments.kind` stores.
enum MilestoneKind {
  newBoon('new_boon'),
  newBogey('new_bogey'),
  masterBoon('master_boon'),
  masterBogey('master_bogey'),
  overcome('overcome');

  const MilestoneKind(this.wire);
  final String wire;

  static MilestoneKind? fromWire(String wire) {
    for (final k in values) {
      if (k.wire == wire) return k;
    }
    return null;
  }

  /// A Master crossing: Reject latches `master_declined` on the ring.
  bool get isMaster => this == masterBoon || this == masterBogey;
}

/// What [GrowthMilestones.decide] did.
enum MilestoneOutcome {
  /// Accepted and applied, or rejected and recorded.
  done,

  /// Accepting a new bogey would pass the 3-bogey cap; the moment stays
  /// pending so the user can overcome one first.
  bogeyCapFull,

  /// The ring the moment is about is gone (deleted or retired meanwhile);
  /// recorded as rejected.
  ringGone,

  /// Already accepted or rejected — a second tap writes nothing.
  alreadyDecided,
}

/// A proposed add, as `growth_moments.payload` stores it: the ring text
/// (names resolved), its category and the messages that showed it.
class MilestoneProposal {
  const MilestoneProposal({
    required this.text,
    required this.category,
    this.sourcePositions = const [],
  });

  final String text;
  final String category;
  final List<int> sourcePositions;

  String encode() =>
      jsonEncode({'text': text, 'category': category, 'src': sourcePositions});

  static MilestoneProposal? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return MilestoneProposal(
        text: '${m['text'] ?? ''}',
        category: '${m['category'] ?? ''}',
        sourcePositions: [
          for (final p in (m['src'] as List? ?? const []))
            if (p is int) p,
        ],
      );
    } catch (e) {
      debugPrint('[Milestones] unreadable payload: $e');
      return null;
    }
  }
}

/// Phase-5 milestones (docs/design/boons-and-bogies.md §7, rulings 1, 8, 9,
/// 15): the moment queue and the one place an accepted milestone is applied.
///
/// New boons and bogies, a trait reaching Master and a bogey overcome never
/// apply on their own; they become pending moments here. [decide] applies an
/// Accept (the ring added, crowned or retired — the overcome retire is the
/// one deliberate exception to "pinned rings are never AI-retired") or
/// records a Reject (a Master Reject latches `master_declined`). The popup
/// budget is one moment per [BoonsBogies.kMilestoneMinGapMessages] user
/// messages, clocked by the highest `shown_at` in the chat; everything else
/// waits unread in Moments.
class GrowthMilestones {
  GrowthMilestones({required this.store, required this.getDb});

  final GrowthStore store;
  final AppDatabase? Function() getDb;

  /// Queue a pending moment. A moment already pending for the same owner,
  /// kind and ring (or, for an add, the same text) is not queued twice —
  /// a Growth pass that sees the same crossing again re-asks nothing.
  /// Returns the moment id (the existing one on a duplicate), or null with
  /// no database.
  Future<String?> propose({
    required String sessionId,
    required String characterId,
    required MilestoneKind kind,
    String? ringId,
    String? tier,
    MilestoneProposal? proposal,
  }) async {
    final db = getDb();
    if (db == null) return null;
    for (final m in await _pending(db, sessionId, characterId)) {
      if (m.kind != kind.wire) continue;
      if (ringId != null && m.ringId == ringId) return m.id;
      if (ringId == null &&
          proposal != null &&
          MilestoneProposal.decode(m.payload)?.text == proposal.text) {
        return m.id;
      }
    }
    final id = const Uuid().v4();
    await db
        .into(db.growthMoments)
        .insert(
          GrowthMomentsCompanion.insert(
            id: id,
            sessionId: sessionId,
            characterId: characterId,
            kind: kind.wire,
            ringId: Value(ringId),
            tier: Value(tier),
            payload: Value(proposal?.encode()),
          ),
        );
    return id;
  }

  /// One owner's moments (every owner when [characterId] is null), newest
  /// first — the Moments list.
  Future<List<GrowthMomentData>> momentsFor(
    String sessionId, {
    String? characterId,
  }) async {
    final db = getDb();
    if (db == null) return const [];
    final q = db.select(db.growthMoments)
      ..where(
        (m) => characterId == null
            ? m.sessionId.equals(sessionId)
            : m.sessionId.equals(sessionId) & m.characterId.equals(characterId),
      )
      ..orderBy([(m) => OrderingTerm.desc(m.createdAt)]);
    return q.get();
  }

  /// The one moment that may pop now, or null: Milestone popups on, nothing
  /// popped within the last [BoonsBogies.kMilestoneMinGapMessages] user
  /// messages, and the oldest pending moment that never popped.
  Future<GrowthMomentData?> nextToShow(
    String sessionId, {
    required int userMessages,
    required bool popupsOn,
  }) async {
    if (!popupsOn) return null;
    final all = await momentsFor(sessionId);
    var lastShown = -1;
    for (final m in all) {
      final at = m.shownAt;
      if (at != null && at > lastShown) lastShown = at;
    }
    if (lastShown >= 0 &&
        userMessages - lastShown < BoonsBogies.kMilestoneMinGapMessages) {
      return null;
    }
    final waiting = [
      for (final m in all)
        if (m.status == 'pending' && m.shownAt == null) m,
    ];
    return waiting.isEmpty
        ? null
        : waiting.last; // oldest: list is newest-first
  }

  /// The card popped at [userMessages]: the budget's clock, and it is seen.
  Future<void> markShown(String id, int userMessages) => _write(
    id,
    GrowthMomentsCompanion(
      shownAt: Value(userMessages),
      seen: const Value(true),
    ),
  );

  /// Opened in Moments (or replayed): no longer unread.
  Future<void> markSeen(String id) =>
      _write(id, const GrowthMomentsCompanion(seen: Value(true)));

  /// Moments a [decide] is still applying. A second tap (the desktop card
  /// and the web card can both answer) reads "pending" until the first
  /// write lands, so without this both would add the ring.
  final Set<String> _deciding = {};

  /// Accept or Reject one moment. Idempotent per moment: a decided one — or
  /// one being decided right now — returns [MilestoneOutcome.alreadyDecided]
  /// and writes nothing.
  Future<MilestoneOutcome> decide(String id, {required bool accept}) async {
    if (!_deciding.add(id)) return MilestoneOutcome.alreadyDecided;
    try {
      return await _decide(id, accept: accept);
    } finally {
      _deciding.remove(id);
    }
  }

  Future<MilestoneOutcome> _decide(String id, {required bool accept}) async {
    final db = getDb();
    if (db == null) return MilestoneOutcome.alreadyDecided;
    final m = await (db.select(
      db.growthMoments,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (m == null || m.status != 'pending') {
      return MilestoneOutcome.alreadyDecided;
    }
    final kind = MilestoneKind.fromWire(m.kind);
    if (kind == null) {
      await _close(id, accepted: false);
      return MilestoneOutcome.ringGone;
    }
    final rings = await store.ringsFor(m.sessionId, m.characterId);
    GrowthRingData? ring;
    for (final r in rings) {
      if (r.id == m.ringId) ring = r;
    }
    final needsRing = kind.isMaster || kind == MilestoneKind.overcome;
    if (needsRing && (ring == null || ring.retired)) {
      await _close(id, accepted: false);
      return MilestoneOutcome.ringGone;
    }

    if (!accept) {
      if (kind.isMaster) await store.bb.setMasterDeclined(ring!, true);
      await _close(id, accepted: false);
      return MilestoneOutcome.done;
    }

    switch (kind) {
      case MilestoneKind.newBoon:
      case MilestoneKind.newBogey:
        final p = MilestoneProposal.decode(m.payload);
        if (p == null || p.text.isEmpty) {
          await _close(id, accepted: false);
          return MilestoneOutcome.ringGone;
        }
        final bogey = kind == MilestoneKind.newBogey;
        if (bogey &&
            rings.where((r) => !r.retired && BoonsBogies.isBogey(r)).length >=
                BoonsBogies.kMaxActiveBogies) {
          return MilestoneOutcome.bogeyCapFull;
        }
        await store.addRing(
          sessionId: m.sessionId,
          characterId: m.characterId,
          content: p.text,
          category: bogey ? BoonsBogies.kCategoryBogey : 'skill',
          sourcePositions: p.sourcePositions,
          metadata: bogey
              ? BoonsBogies.bogeyMetadata()
              : BoonsBogies.boonMetadata(),
        );
      case MilestoneKind.masterBoon:
        await store.bb.crownMaster(
          ring!,
          advance: BoonsBogies.kBoonMasterPasses,
          strength: ring.strength > BoonsBogies.kBoonMasterStrength
              ? ring.strength
              : BoonsBogies.kBoonMasterStrength,
        );
      case MilestoneKind.masterBogey:
        await store.bb.crownMaster(
          ring!,
          advance: BoonsBogies.kBogeyMasterFires,
          strength: BoonsBogies.bogeyStrength(BoonsBogies.kBogeyMasterFires),
        );
      case MilestoneKind.overcome:
        // The one deliberate exception to "pinned rings are never
        // AI-retired" (§3.2): the user just said yes.
        await store.retireRing(ring!.id);
    }
    await _close(id, accepted: true);
    return MilestoneOutcome.done;
  }

  Future<List<GrowthMomentData>> _pending(
    AppDatabase db,
    String sessionId,
    String characterId,
  ) =>
      (db.select(db.growthMoments)..where(
            (m) =>
                m.sessionId.equals(sessionId) &
                m.characterId.equals(characterId) &
                m.status.equals('pending'),
          ))
          .get();

  Future<void> _close(String id, {required bool accepted}) => _write(
    id,
    GrowthMomentsCompanion(
      status: Value(accepted ? 'accepted' : 'rejected'),
      seen: const Value(true),
    ),
  );

  Future<void> _write(String id, GrowthMomentsCompanion row) async {
    final db = getDb();
    if (db == null) return;
    await (db.update(
      db.growthMoments,
    )..where((m) => m.id.equals(id))).write(row);
  }
}
