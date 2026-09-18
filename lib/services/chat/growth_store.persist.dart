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

part of 'growth_store.dart';

/// Ring writes, fade, and session-carry. Cursor + cache stay on
/// [GrowthStore] so the sync injection readers keep one home.
extension GrowthStorePersist on GrowthStore {
  /// Insert a new ring, enforcing the active-ring cap by retiring the
  /// weakest unpinned, non-established ring (GrowthPhysics.capVictim).
  Future<void> addRing({
    required String sessionId,
    required String characterId,
    required String content,
    required String category,
    List<int> sourcePositions = const [],
    double strength = GrowthPhysics.kNewRingStrength,
    bool pinned = false,
    bool retired = false,
  }) async {
    final db = getDb();
    if (db == null) return;
    if (!retired) {
      final active = (await db.getGrowthRings(
        sessionId,
        characterId,
      )).where((r) => !r.retired).toList();
      if (active.length >= GrowthPhysics.kMaxActiveRings) {
        final victim = GrowthPhysics.capVictim(active);
        if (victim != null) await _retire(db, victim.id);
      }
    }
    await db.insertGrowthRing(
      GrowthRingsCompanion(
        sessionId: Value(sessionId),
        characterId: Value(characterId),
        content: Value(_resolved(characterId, content)),
        category: Value(category),
        strength: Value(strength),
        pinned: Value(pinned),
        retired: Value(retired),
        sourceMessageIds: Value(
          sourcePositions.isEmpty ? null : jsonEncode(sourcePositions),
        ),
      ),
    );
  }

  /// Strengthen a ring one step and append the new receipts.
  Future<void> reinforceRing(
    GrowthRingData ring, {
    List<int> sourcePositions = const [],
  }) async {
    final db = getDb();
    if (db == null) return;
    await db.updateGrowthRing(
      ring.id,
      GrowthRingsCompanion(
        strength: Value(GrowthPhysics.reinforced(ring.strength)),
        sourceMessageIds: Value(
          jsonEncode(GrowthStore.mergedReceipts(ring, sourcePositions)),
        ),
        lastReinforcedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Reword a ring in place (model revise op or user edit).
  Future<void> reviseRing(
    GrowthRingData ring, {
    required String content,
    String? category,
  }) async {
    final db = getDb();
    if (db == null) return;
    await db.updateGrowthRing(
      ring.id,
      GrowthRingsCompanion(
        content: Value(_resolved(ring.characterId, content)),
        category: category == null ? const Value.absent() : Value(category),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Demote a ring to Past growth (never a deletion — history stays visible).
  Future<void> retireRing(String id) async {
    final db = getDb();
    if (db == null) return;
    await _retire(db, id);
  }

  /// Restore a retired ring to the active set (user "bring it back").
  /// Re-enters as emerging unless it left established.
  Future<void> unretireRing(GrowthRingData ring) async {
    final db = getDb();
    if (db == null) return;
    await db.updateGrowthRing(
      ring.id,
      GrowthRingsCompanion(
        retired: const Value(false),
        strength: Value(
          ring.strength < GrowthPhysics.kNewRingStrength
              ? GrowthPhysics.kNewRingStrength
              : ring.strength,
        ),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> setPinned(String id, bool pinned) async {
    final db = getDb();
    if (db == null) return;
    await db.updateGrowthRing(
      id,
      GrowthRingsCompanion(
        pinned: Value(pinned),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Hard-delete a single ring (user action in the timeline).
  Future<void> deleteRing(String id) async {
    await getDb()?.deleteGrowthRing(id);
  }

  /// Timeline integrity (Journal twin, audit P1.9): content at/after
  /// [fromPosition] was rewritten, so every ring CITING that region describes
  /// discarded plot — delete them (pinned included). Rings with no receipts
  /// (manual plants) are never touched. Sweeps all owners for the session.
  Future<int> invalidateRingsCitingFrom(
    String sessionId,
    int fromPosition,
  ) async {
    final db = getDb();
    if (db == null) return 0;
    var removed = 0;
    for (final ring in await db.getGrowthRingsForSession(sessionId)) {
      final raw = ring.sourceMessageIds;
      if (raw == null || raw.isEmpty) continue;
      List<dynamic> positions;
      try {
        positions = jsonDecode(raw) as List<dynamic>;
      } catch (_) {
        continue;
      }
      final cites = positions.whereType<num>().any(
        (p) => p.toInt() >= fromPosition,
      );
      if (cites) {
        await db.deleteGrowthRing(ring.id);
        removed++;
      }
    }
    if (removed > 0 && _cacheValid(sessionId)) {
      // Drop cache so injection/timeline re-read DB without phantom rings.
      invalidate();
    }
    return removed;
  }

  /// Delete every ring for one owner in one chat (user Reset, or hard cast
  /// removal). The original card was never touched, so this fully restores
  /// the pre-growth character.
  Future<void> deleteAllFor(String sessionId, String characterId) async {
    await getDb()?.deleteGrowthRingsForCharacter(sessionId, characterId);
  }

  /// Fade every active ring that was NOT reinforced this pass one step
  /// (established/pinned never fade — GrowthPhysics owns the numbers).
  /// A ring faded to 0 retires to Past growth.
  Future<void> fadeUnreinforced(
    String sessionId,
    String characterId,
    Set<String> reinforcedIds,
  ) async {
    final db = getDb();
    if (db == null) return;
    for (final ring in await db.getGrowthRings(sessionId, characterId)) {
      if (ring.retired || reinforcedIds.contains(ring.id)) continue;
      final faded = GrowthPhysics.fadedStrength(ring);
      if (faded == ring.strength) continue; // established or pinned
      if (faded <= 0.0) {
        await _retire(db, ring.id);
      } else {
        await db.updateGrowthRing(
          ring.id,
          GrowthRingsCompanion(strength: Value(faded)),
        );
      }
    }
  }

  /// Archive the legacy evolved blob as a pinned, retired timeline entry and
  /// clear the session's evolved fields (design §8 — nothing destroyed, and
  /// injection switches from the blob to rings). [isGroup] selects the
  /// column shape; 1:1 clears the flat columns.
  Future<void> archiveLegacyBlob(
    String sessionId,
    String characterId, {
    required bool isGroup,
  }) async {
    final blob = _legacyCache[characterId];
    if (blob == null) return;
    final (pers, scen) = blob;
    final text = [
      if (pers.isNotEmpty) pers,
      if (scen.isNotEmpty) scen,
    ].join('\n\n');
    if (text.isNotEmpty) {
      await addRing(
        sessionId: sessionId,
        characterId: characterId,
        content: text,
        category: GrowthPhysics.kArchiveCategory,
        pinned: true,
        retired: true,
      );
    }
    await discardLegacyBlob(sessionId, characterId, isGroup: isGroup);
  }

  /// Clear one owner's legacy evolved fields WITHOUT archiving (user Reset).
  Future<void> discardLegacyBlob(
    String sessionId,
    String characterId, {
    required bool isGroup,
  }) async {
    final db = getDb();
    if (db == null) return;
    final session = await db.getSessionById(sessionId);
    if (session == null) return;
    if (isGroup) {
      final persMap = _parseJsonMap(session.groupEvolvedPersonalities);
      final scenMap = _parseJsonMap(session.groupEvolvedScenarios);
      persMap.remove(characterId);
      scenMap.remove(characterId);
      await db.patchSession(
        SessionsCompanion(
          id: Value(sessionId),
          groupEvolvedPersonalities: Value(jsonEncode(persMap)),
          groupEvolvedScenarios: Value(jsonEncode(scenMap)),
        ),
      );
    } else {
      await db.patchSession(
        SessionsCompanion(
          id: Value(sessionId),
          evolvedPersonality: const Value(''),
          evolvedScenario: const Value(''),
        ),
      );
    }
    _legacyCache.remove(characterId);
  }

  /// Carry growth into a forked session: copy every ring (fresh ids), the
  /// pass [cursor] (the fork's message count), and any not-yet-distilled
  /// legacy evolved columns from the parent session row (so pre-update chats
  /// still migrate in the fork). The parent session is left untouched.
  Future<void> copySessionTo(
    String fromSessionId,
    String toSessionId, {
    required int cursor,
  }) async {
    final db = getDb();
    if (db == null) return;
    for (final ring in await db.getGrowthRingsForSession(fromSessionId)) {
      final raw = ring.sourceMessageIds;
      if (raw != null && raw.isNotEmpty) {
        try {
          final positions = jsonDecode(raw) as List<dynamic>;
          if (positions.whereType<num>().any((p) => p.toInt() >= cursor)) {
            continue;
          }
        } catch (_) {}
      }
      await db.insertGrowthRing(
        GrowthRingsCompanion(
          sessionId: Value(toSessionId),
          characterId: Value(ring.characterId),
          content: Value(ring.content),
          category: Value(ring.category),
          strength: Value(ring.strength),
          pinned: Value(ring.pinned),
          retired: Value(ring.retired),
          sourceMessageIds: Value(ring.sourceMessageIds),
          createdAt: Value(ring.createdAt),
          lastReinforcedAt: Value(ring.lastReinforcedAt),
        ),
      );
    }
    await db.setGrowthCursor(toSessionId, cursor);
    try {
      final parent = await db.getSessionById(fromSessionId);
      final parentGroupBlobs =
          parent != null &&
          parent.groupEvolvedPersonalities.isNotEmpty &&
          parent.groupEvolvedPersonalities != '{}';
      if (parent != null &&
          (parent.evolvedPersonality.isNotEmpty ||
              parent.evolvedScenario.isNotEmpty ||
              parentGroupBlobs)) {
        await db.patchSession(
          SessionsCompanion(
            id: Value(toSessionId),
            evolvedPersonality: Value(parent.evolvedPersonality),
            evolvedScenario: Value(parent.evolvedScenario),
            groupEvolvedPersonalities: Value(parent.groupEvolvedPersonalities),
            groupEvolvedScenarios: Value(parent.groupEvolvedScenarios),
          ),
        );
      }
    } catch (_) {
      // Legacy-blob carry is best-effort; rings + cursor already copied.
    }
  }

  /// Carry one owner's growth into another (session, owner) home — the
  /// 1:1→group fork carry (COPY, not move: the source stays the revert
  /// snapshot). Rings are duplicated under the target keys; any undistilled
  /// legacy evolved text is copied into the target session's column shape so
  /// the distill migration still finds it there.
  Future<void> carryOwnerGrowth({
    required String fromSessionId,
    required String fromCharId,
    required String toSessionId,
    required String toCharId,
    required bool fromIsGroup,
    required bool toIsGroup,
  }) async {
    final db = getDb();
    if (db == null) return;
    for (final ring in await db.getGrowthRings(fromSessionId, fromCharId)) {
      await db.insertGrowthRing(
        GrowthRingsCompanion(
          sessionId: Value(toSessionId),
          characterId: Value(toCharId),
          content: Value(ring.content),
          category: Value(ring.category),
          strength: Value(ring.strength),
          pinned: Value(ring.pinned),
          retired: Value(ring.retired),
          sourceMessageIds: Value(ring.sourceMessageIds),
          createdAt: Value(ring.createdAt),
          lastReinforcedAt: Value(ring.lastReinforcedAt),
        ),
      );
    }
    try {
      final source = await db.getSessionById(fromSessionId);
      if (source == null) return;
      final String pers;
      final String scen;
      if (fromIsGroup) {
        pers =
            _parseJsonMap(source.groupEvolvedPersonalities)[fromCharId] ?? '';
        scen = _parseJsonMap(source.groupEvolvedScenarios)[fromCharId] ?? '';
      } else {
        pers = source.evolvedPersonality;
        scen = source.evolvedScenario;
      }
      if (pers.isEmpty && scen.isEmpty) return;
      final target = await db.getSessionById(toSessionId);
      if (target == null) return;
      if (toIsGroup) {
        final persMap = _parseJsonMap(target.groupEvolvedPersonalities);
        final scenMap = _parseJsonMap(target.groupEvolvedScenarios);
        if (pers.isNotEmpty) persMap[toCharId] = pers;
        if (scen.isNotEmpty) scenMap[toCharId] = scen;
        await db.patchSession(
          SessionsCompanion(
            id: Value(toSessionId),
            groupEvolvedPersonalities: Value(jsonEncode(persMap)),
            groupEvolvedScenarios: Value(jsonEncode(scenMap)),
          ),
        );
      } else {
        await db.patchSession(
          SessionsCompanion(
            id: Value(toSessionId),
            evolvedPersonality: Value(pers),
            evolvedScenario: Value(scen),
          ),
        );
      }
    } catch (_) {
      // Legacy-blob carry is best-effort; rings already copied.
    }
  }

  Future<void> _retire(AppDatabase db, String id) => db.updateGrowthRing(
    id,
    GrowthRingsCompanion(
      retired: const Value(true),
      updatedAt: Value(DateTime.now()),
    ),
  );
}
