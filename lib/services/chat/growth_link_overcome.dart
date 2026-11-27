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

import 'package:front_porch_ai/database/database.dart' show GrowthRingData;

import 'growth_bb_link.dart';
import 'growth_boons_bogies.dart';
import 'growth_milestones.dart';
import 'growth_store/growth_bogey_store.dart' show MasterLinkedCope;

/// "A linked Master makes overcome likely" (phase 7, maintainer ruling
/// 2026-11-26): the app itself offers the Overcome milestone for a
/// Master-linked bogey a cope wore down to nothing (or, for a pinned flaw
/// that never wears down, on the cope itself). It is the same moment a
/// model's retire proposes — the user still Accepts or Rejects.
///
/// The offer cites the cope's messages, so a regen, swipe, delete or edit
/// of them drops it with every other pending moment
/// (`GrowthMilestones.invalidatePendingFrom`). A Reject is remembered by
/// the count the offer was made at; the app asks again only after the flaw
/// has fired since ([BoonLink.overcomeRipe]).
abstract final class LinkedOvercome {
  /// Weigh one pass's Master-linked copes ([touched]) and queue the ripe
  /// offers. [sources] maps each coped ring id to the in-window messages
  /// that showed it. Returns how many offers were queued (or already were).
  static Future<int> offer(
    GrowthMilestones milestones,
    List<MasterLinkedCope> touched,
    Map<String, List<int>> sources,
  ) async {
    var queued = 0;
    for (final t in touched) {
      final ring = t.ring;
      final declinedAt = await _declinedAt(milestones, ring.sessionId, ring);
      if (!BoonLink.overcomeRipe(
        pinned: ring.pinned,
        before: t.before,
        after: t.after,
        declinedAt: declinedAt,
      )) {
        continue;
      }
      final id = await milestones.propose(
        sessionId: ring.sessionId,
        characterId: ring.characterId,
        kind: MilestoneKind.overcome,
        ringId: ring.id,
        proposal: _OfferedOvercome(
          text: ring.content,
          sourcePositions: sources[ring.id] ?? const [],
          offeredAt: t.after,
        ),
      );
      if (id != null) queued++;
    }
    return queued;
  }

  /// The count the newest REJECTED app offer for [ring] was made at, or
  /// null (never offered, or only a model's proposal was rejected).
  static Future<int?> _declinedAt(
    GrowthMilestones milestones,
    String sessionId,
    GrowthRingData ring,
  ) async {
    final moments = await milestones.momentsFor(
      sessionId,
      characterId: ring.characterId,
    );
    for (final m in moments) {
      if (m.kind != MilestoneKind.overcome.wire || m.ringId != ring.id) {
        continue;
      }
      if (m.status != 'rejected') continue;
      final at = BoonLink.offeredAtOf(m.payload);
      if (at != null) return at;
    }
    return null;
  }
}

/// An app-offered Overcome's payload: the shared proposal shape plus the
/// fire count it was offered at (the Reject memory).
class _OfferedOvercome extends MilestoneProposal {
  const _OfferedOvercome({
    required super.text,
    super.sourcePositions,
    required this.offeredAt,
  }) : super(category: BoonsBogies.kCategoryBogey);

  final int offeredAt;

  @override
  String encode() => jsonEncode({
    ...jsonDecode(super.encode()) as Map<String, dynamic>,
    BoonLink.kOfferedAtKey: offeredAt,
  });
}
