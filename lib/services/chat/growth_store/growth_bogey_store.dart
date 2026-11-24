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
  /// bogey wears down one step through [GrowthBbWriter.fadeBogey], undo
  /// snapshot included. Silence never reaches here — it holds the flaw.
  Future<void> cope(
    String sessionId,
    String characterId,
    Set<String> ringIds,
  ) async {
    if (ringIds.isEmpty) return;
    for (final ring in await _ringsFor(sessionId, characterId)) {
      if (ring.retired || !ringIds.contains(ring.id)) continue;
      if (!BoonsBogies.isBogey(ring)) continue;
      await _writer.fadeBogey(ring);
    }
  }
}
