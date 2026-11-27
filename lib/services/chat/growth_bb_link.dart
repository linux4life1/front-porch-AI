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

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:front_porch_ai/database/database.dart' show GrowthRingData;

import 'growth_boons_bogies.dart';
import 'growth_kit_seed.dart';

/// The boon link (docs/design/boons-and-bogies.md phase 7, maintainer
/// rulings 2026-11-26): a bogey may name the boon that pushes against it.
///
/// - **Slowdown.** Each tier of the linked boon scales the bogey's fire
///   chance ([chancePercentFor]): Novice about one fire in 8 replies,
///   Skilled about one in 10, Master about one in 12, against about one in
///   7 unlinked. A simulation test over the function the roll calls pins
///   those gaps.
/// - **Master makes overcome likely.** While the linked boon is Master,
///   each cope wears the flaw down [copeStepsFor] = 2 steps instead of 1,
///   and once it is worn to nothing the app itself offers the Overcome
///   milestone ([overcomeRipe]). The user still decides.
///
/// The link is `metadata.bb.linkedBoon`: a boon ring id (the user's pick
/// in the sidebar, or the Growth pass's link on a new bogey), or the boon's
/// words as a card kit names it. Pure lookups only; the content writer
/// stores it ([GrowthBbWriter.setBogeyLink]).
abstract final class BoonLink {
  /// Fire-chance percent per linked-boon tier. 100 = unlinked, unchanged.
  static const int kNovicePercent = 80;
  static const int kSkilledPercent = 50;
  static const int kMasterPercent = 33;

  /// Cope steps while the linked boon is Master.
  static const int kMasterCopeSteps = 2;

  /// The stored link value, or null when the bogey names no boon.
  static String? linkOf(GrowthRingData bogey) {
    final raw = BoonsBogies.bbOf(bogey)[BoonsBogies.kLinkedBoonKey];
    if (raw is! String) return null;
    final link = raw.trim();
    return link.isEmpty ? null : link;
  }

  /// The live boon [bogey] is linked to among [ownerRings] (the same
  /// owner's rings, this chat), or null: unlinked, or the named boon is
  /// gone, retired or no longer a boon. An id match wins; a kit link
  /// matches the boon's words the way kit seeding does.
  static GrowthRingData? linkedBoonOf(
    GrowthRingData bogey,
    Iterable<GrowthRingData> ownerRings,
  ) {
    final link = linkOf(bogey);
    if (link == null || !BoonsBogies.isBogey(bogey)) return null;
    final boons = [
      for (final r in ownerRings)
        if (!r.retired &&
            BoonsBogies.isBoon(r) &&
            r.characterId == bogey.characterId)
          r,
    ];
    for (final r in boons) {
      if (r.id == link) return r;
    }
    final key = GrowthKitSeed.sameTextKey(link);
    for (final r in boons) {
      if (GrowthKitSeed.sameTextKey(r.content) == key) return r;
    }
    return null;
  }

  /// The boon ring id a Growth pass's bogey add names with `against="N"`,
  /// or null: no handle, not a bogey add, out of range, or [shown][N-1] is
  /// not a live boon. [shown] is the list the pass prompt numbered.
  static String? boonIdForHandle(
    int? handle, {
    required String category,
    required List<GrowthRingData> shown,
  }) {
    if (handle == null || category != BoonsBogies.kCategoryBogey) return null;
    if (handle < 1 || handle > shown.length) return null;
    final ring = shown[handle - 1];
    return BoonsBogies.isBoon(ring) && !ring.retired ? ring.id : null;
  }

  /// The fire-chance percent for a bogey whose linked boon sits at [tier]
  /// (a [BoonsBogies.tierOf] value); null or '' = no live link.
  static int chancePercentFor(String? tier) => switch (tier) {
    'master' => kMasterPercent,
    'skilled' => kSkilledPercent,
    'novice' => kNovicePercent,
    _ => 100,
  };

  /// [chancePercentFor] for [bogey] among [ownerRings].
  static int chancePercentOf(
    GrowthRingData bogey,
    Iterable<GrowthRingData> ownerRings,
  ) {
    final boon = linkedBoonOf(bogey, ownerRings);
    return boon == null ? 100 : chancePercentFor(BoonsBogies.tierOf(boon));
  }

  /// How many steps one cope wears [bogey] down.
  static int copeStepsFor(
    GrowthRingData bogey,
    Iterable<GrowthRingData> ownerRings,
  ) => masterLinked(bogey, ownerRings) ? kMasterCopeSteps : 1;

  /// Whether [bogey]'s linked boon is at Master.
  static bool masterLinked(
    GrowthRingData bogey,
    Iterable<GrowthRingData> ownerRings,
  ) {
    final boon = linkedBoonOf(bogey, ownerRings);
    return boon != null && BoonsBogies.tierOf(boon) == 'master';
  }

  /// Whether a cope on a Master-linked bogey should offer Overcome.
  ///
  /// [before] / [after] are the fire counts around the cope. A flaw that
  /// can wear down offers once it reaches zero; a pinned flaw never wears
  /// down (the pin's promise), so the cope itself is the moment. After a
  /// Reject ([declinedAt] = the count the rejected offer was made at), the
  /// app asks again only once the flaw has fired since — a count above the
  /// declined one — so a no is never re-asked on the very next pass.
  static bool overcomeRipe({
    required bool pinned,
    required int before,
    required int after,
    int? declinedAt,
  }) {
    if (declinedAt != null && before <= declinedAt) return false;
    return pinned || after == 0;
  }

  /// The payload key carrying the count an app-offered Overcome was made at.
  static const String kOfferedAtKey = 'offeredAt';

  /// The count an Overcome moment's payload records, or null (a model's
  /// proposal, or no payload).
  static int? offeredAtOf(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final m = jsonDecode(payload);
      final v = m is Map ? m[kOfferedAtKey] : null;
      return v is int ? v : null;
    } catch (e) {
      debugPrint('[Growth] unreadable overcome payload: $e');
      return null;
    }
  }
}
