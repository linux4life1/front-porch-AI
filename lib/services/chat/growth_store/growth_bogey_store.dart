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

import 'package:drift/drift.dart' show Value;
import 'package:front_porch_ai/database/database.dart';

import '../growth_bb_link.dart';
import '../growth_boons_bogies.dart';
import 'growth_bb_writer.dart';

/// The bogey half of [GrowthStore]'s writes (docs/design/boons-and-bogies.md
/// §6): the roll's gauge and fire, the delivered/cleared slot, and the
/// Growth pass's coping verdict.
///
/// The slot writes patch the store's cache as well as the row. The roll gate
/// and the reply's nudge both read the cache, and a cache still holding a
/// delivered-but-cleared nudge put the flaw into every reply — and blocked
/// every roll — until some unrelated refresh came along.
class GrowthBogeyStore {
  GrowthBogeyStore({
    required GrowthBbWriter writer,
    required Future<List<GrowthRingData>> Function(String, String) ringsFor,
    required void Function(GrowthRingData) patchCached,
  }) : _writer = writer,
       _ringsFor = ringsFor,
       _patch = patchCached;

  final GrowthBbWriter _writer;
  final Future<List<GrowthRingData>> Function(String, String) _ringsFor;
  final void Function(GrowthRingData) _patch;

  /// See [GrowthBbWriter.recordBogeyGauge] — one reply's gauge movement.
  Future<void> recordGauge(
    GrowthRingData ring, {
    required int pressure,
    required int cooldown,
  }) => _writer.recordBogeyGauge(ring, pressure: pressure, cooldown: cooldown);

  /// See [GrowthBbWriter.fireBogey] — a fire parks the nudge and counts.
  Future<void> fire(
    GrowthRingData ring, {
    required String text,
    required int cooldown,
    required int advance,
  }) =>
      _writer.fireBogey(ring, text: text, cooldown: cooldown, advance: advance);

  /// The prompt builder consumed the parked nudge.
  Future<void> markDelivered(GrowthRingData ring) async {
    await _writer.markBogeyDelivered(ring);
    _patch(ring.copyWith(bogeyDelivered: true));
  }

  /// The next user turn: the slot reads free to the next roll.
  Future<void> clearDelivered(GrowthRingData ring) async {
    await _writer.clearDeliveredBogey(ring);
    _patch(
      ring.copyWith(bogeyPending: const Value(null), bogeyDelivered: false),
    );
  }

  /// One coping verdict per ring id (§3 absence amendment): each cited
  /// bogey wears down through [GrowthBbWriter.fadeBogey], undo snapshot
  /// included — one step, or two while its linked boon is Master (phase
  /// 7). Silence never reaches here — it holds the flaw.
  ///
  /// Returns the Master-linked bogeys this cope touched, with their count
  /// before it, for the caller to weigh an Overcome offer
  /// ([BoonLink.overcomeRipe]). Empty when no cited flaw is Master-linked.
  Future<List<MasterLinkedCope>> cope(
    String sessionId,
    String characterId,
    Set<String> ringIds,
  ) async {
    if (ringIds.isEmpty) return const [];
    final rings = await _ringsFor(sessionId, characterId);
    final touched = <MasterLinkedCope>[];
    for (final ring in rings) {
      if (ring.retired || !ringIds.contains(ring.id)) continue;
      if (!BoonsBogies.isBogey(ring)) continue;
      final steps = BoonLink.copeStepsFor(ring, rings);
      final faded = await _writer.fadeBogey(ring, steps: steps);
      final after = faded
          ? BoonsBogies.fadedBogeyAdvance(ring.advanceCount, steps: steps)
          : ring.advanceCount;
      // A declined Master re-arms once the flaw falls back below the re-arm
      // count; climbing to Master again then asks again (§3.2).
      if (faded &&
          ring.masterDeclined &&
          after < BoonsBogies.kBogeyMasterRearmBelow) {
        await _writer.setMasterDeclined(ring, false);
      }
      if (BoonLink.masterLinked(ring, rings)) {
        touched.add((ring: ring, before: ring.advanceCount, after: after));
      }
    }
    return touched;
  }

  /// The user's linked-boon pick for [ring] (null unlinks).
  Future<void> setLink(GrowthRingData ring, String? boonRingId) =>
      _writer.setBogeyLink(ring, boonRingId);
}

/// One Master-linked bogey a cope touched: the ring as it was, and its fire
/// count before and after the cope.
typedef MasterLinkedCope = ({GrowthRingData ring, int before, int after});
