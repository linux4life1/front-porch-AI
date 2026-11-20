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
}
