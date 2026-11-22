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

// Boons & Bogies writes (docs/design/boons-and-bogies.md §3.2): the boon
// ladder step, the bogey fire/coping step and the one-step undo restore.
// Split from GrowthRingWriter to keep both files under the size law; the
// content applier still reaches these through GrowthReview.

import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:front_porch_ai/database/database.dart';
import '../growth_boons_bogies.dart';
import '../growth_physics.dart';
import 'growth_ring_codec.dart';

class GrowthBbWriter {
  final AppDatabase? Function() getDb;
  final String Function(String characterId, String text) _resolve;

  GrowthBbWriter({
    required this.getDb,
    required String Function(String characterId, String text) resolve,
  }) : _resolve = resolve;

  /// Strengthen a boon one step, bump its used-pass count and store the
  /// pre-change snapshot.
  Future<void> reinforceBoon(
    GrowthRingData ring, {
    required int advanceCount,
    required String metadata,
    List<int> sourcePositions = const [],
  }) async {
    final db = getDb();
    if (db == null) return;
    await db.updateGrowthRing(
      ring.id,
      GrowthRingsCompanion(
        strength: Value(GrowthPhysics.reinforced(ring.strength)),
        advanceCount: Value(advanceCount),
        metadata: Value(metadata),
        sourceMessageIds: Value(
          jsonEncode(mergedGrowthReceipts(ring, sourcePositions)),
        ),
        lastReinforcedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Make a bogey worse: bump its fire/worse count and derive strength from
  /// the count.
  Future<void> reinforceBogey(
    GrowthRingData ring, {
    required int advanceCount,
    required String metadata,
    List<int> sourcePositions = const [],
  }) async {
    final db = getDb();
    if (db == null) return;
    await db.updateGrowthRing(
      ring.id,
      GrowthRingsCompanion(
        strength: Value(BoonsBogies.bogeyStrength(advanceCount)),
        advanceCount: Value(advanceCount),
        metadata: Value(metadata),
        sourceMessageIds: Value(
          jsonEncode(mergedGrowthReceipts(ring, sourcePositions)),
        ),
        lastReinforcedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// One coping step: the fire count drops (floor 0) and strength follows it.
  /// False when the ring cannot fade (pinned, or already at zero).
  ///
  /// The pass prompt reinforces a bogey only when the story makes it worse,
  /// so "this pass did not reinforce it" is the coping case (§3.2) — the same
  /// mapping the ordinary fade already uses, named here because the ruling
  /// talks about the story rather than the op list.
  Future<bool> fadeBogey(GrowthRingData ring) async {
    final db = getDb();
    if (db == null) return false;
    if (ring.pinned || ring.advanceCount == 0) return false;
    final next = BoonsBogies.fadedBogeyAdvance(ring.advanceCount);
    await db.updateGrowthRing(
      ring.id,
      GrowthRingsCompanion(
        advanceCount: Value(next),
        strength: Value(BoonsBogies.bogeyStrength(next)),
        metadata: Value(BoonsBogies.metadataWithUndo(ring)),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return true;
  }

  /// Restore a ring from its one-step undo snapshot: strength, advance count
  /// and text together, then clear the snapshot.
  Future<void> restoreUndo(GrowthRingData ring, BbUndo undo) async {
    final db = getDb();
    if (db == null) return;
    await db.updateGrowthRing(
      ring.id,
      GrowthRingsCompanion(
        strength: Value(undo.strength),
        advanceCount: Value(undo.advance),
        content: Value(_resolve(ring.characterId, undo.text)),
        metadata: Value(BoonsBogies.metadataWithoutUndo(ring)),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Persist one reply's gauge movement for a bogey (§6): pressure and
  /// cooldown, nothing else. Fired rings park through [parkBogey].
  Future<void> recordBogeyGauge(
    GrowthRingData ring, {
    required int pressure,
    required int cooldown,
  }) async {
    final db = getDb();
    if (db == null) return;
    await db.updateGrowthRing(
      ring.id,
      GrowthRingsCompanion(
        bogeyPressure: Value(pressure),
        bogeyCooldown: Value(cooldown),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// A fire: park the nudge for the next reply and restart the gauge. The
  /// delivered flag clears so regen/swipe of that reply re-inject the SAME
  /// line (ruling 19) until the next user turn clears the slot.
  Future<void> parkBogey(GrowthRingData ring, {required String text}) async {
    final db = getDb();
    if (db == null) return;
    await db.updateGrowthRing(
      ring.id,
      GrowthRingsCompanion(
        bogeyPending: Value(text),
        bogeyDelivered: const Value(false),
        bogeyPressure: const Value(0),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// The prompt builder consumed the parked nudge: a second build (regen,
  /// swipe) still sees it, so only the flag moves.
  Future<void> markBogeyDelivered(GrowthRingData ring) async {
    final db = getDb();
    if (db == null) return;
    await db.updateGrowthRing(
      ring.id,
      GrowthRingsCompanion(
        bogeyDelivered: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// The next user turn: the slot clears so the same flaw can be rolled
  /// again later. Delivered only — a parked-but-undelivered nudge survives.
  Future<void> clearDeliveredBogey(GrowthRingData ring) async {
    final db = getDb();
    if (db == null) return;
    await db.updateGrowthRing(
      ring.id,
      GrowthRingsCompanion(
        bogeyPending: const Value(null),
        bogeyDelivered: const Value(false),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
