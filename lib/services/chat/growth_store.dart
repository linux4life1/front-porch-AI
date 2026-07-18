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

import 'package:front_porch_ai/database/database.dart';
import 'growth_ops.dart' show hasGrowthMacros;
import 'growth_physics.dart';

/// Growth Rings — ring persistence (docs/design/growth-rings.md §5) plus the
/// DB half of the ring physics (§4.4): reinforcement, per-pass fade, and
/// cap-trim.
///
/// Rings are strictly scoped per (sessionId, characterId) — no read or write
/// ever crosses chats; deleting a chat cascades in
/// [AppDatabase.deleteSessionById]. Rings never need embeddings (always few,
/// always ranked), so the no-RAG floor is trivially satisfied.
///
/// Unlike JournalStore, this store also keeps a small synchronous CACHE of
/// the current session's rings + legacy evolved blobs: the [Character Growth]
/// injection is built inside synchronous prompt assembly
/// (_getEffectivePersonality), so it cannot await the DB. [refresh] reloads
/// the cache — on session load, after every pass, and after every UI
/// mutation (the mutation helpers here do it themselves).
///
/// Holds the database via a closure (JournalStore precedent). No
/// bumpSyncVersion on writes (derived, session-local data).
class GrowthStore {
  final AppDatabase? Function() getDb;

  /// Resolves {{char}}/{{user}} to real names for one owner's text (the god
  /// wires the roster + persona lookup). Ring text is stored RESOLVED — the
  /// timeline displays it verbatim on both surfaces — so this runs on every
  /// content write here (the single choke point) and as a [refresh]-time
  /// self-heal for rings stored before resolution existed. Null in tests
  /// that don't care about macros.
  final String Function(String characterId, String text)? resolveMacros;

  GrowthStore({required this.getDb, this.resolveMacros});

  String _resolved(String characterId, String text) =>
      resolveMacros == null ? text : resolveMacros!(characterId, text);

  String? _cacheSessionId;
  final Map<String, List<GrowthRingData>> _ringCache = {};
  int _cursorCache = 0;

  /// charId → (legacy evolved personality, legacy evolved scenario) still
  /// waiting to be distilled into rings (design §8). Injection keeps using
  /// the blob until the distill pass succeeds — no behavior cliff.
  final Map<String, (String, String)> _legacyCache = {};

  /// Drop the cache (context switches). The next [refresh] repopulates it.
  void invalidate() {
    _cacheSessionId = null;
    _ringCache.clear();
    _legacyCache.clear();
    _cursorCache = 0;
  }

  /// Reload the cache for [sessionId]: every owner's rings, plus the
  /// not-yet-distilled legacy evolved blobs ([activeCharId] owns the flat 1:1
  /// columns; group members own their keys in the groupEvolved* JSON maps).
  Future<void> refresh(
    String sessionId, {
    required List<String> charIds,
    String? activeCharId,
    bool isGroup = false,
  }) async {
    final db = getDb();
    if (db == null) return;
    final rings = <String, List<GrowthRingData>>{};
    for (final id in charIds) {
      if (id.isEmpty) continue;
      var loaded = await db.getGrowthRings(sessionId, id);
      // Self-heal rings stored before macro resolution existed: resolve
      // {{char}}/{{user}} in place once, then re-read (idempotent — healed
      // rings never match again).
      if (resolveMacros != null &&
          loaded.any((r) => hasGrowthMacros(r.content))) {
        for (final ring in loaded) {
          final healed = _resolved(id, ring.content);
          if (healed != ring.content) {
            await db.updateGrowthRing(
              ring.id,
              GrowthRingsCompanion(content: Value(healed)),
            );
          }
        }
        loaded = await db.getGrowthRings(sessionId, id);
      }
      rings[id] = loaded;
    }

    final legacy = <String, (String, String)>{};
    try {
      final session = await db.getSessionById(sessionId);
      if (session != null) {
        if (isGroup) {
          final pers = _parseJsonMap(session.groupEvolvedPersonalities);
          final scen = _parseJsonMap(session.groupEvolvedScenarios);
          for (final id in charIds) {
            final p = pers[id] ?? '';
            final s = scen[id] ?? '';
            if (p.isNotEmpty || s.isNotEmpty) legacy[id] = (p, s);
          }
        } else if (activeCharId != null && activeCharId.isNotEmpty) {
          final p = session.evolvedPersonality;
          final s = session.evolvedScenario;
          if (p.isNotEmpty || s.isNotEmpty) legacy[activeCharId] = (p, s);
        }
      }
    } catch (_) {
      // Legacy blobs are best-effort — a read failure just means the distill
      // section is skipped this pass and retried on the next refresh.
    }

    final cursor = await db.getGrowthCursor(sessionId);

    // Swap atomically only if no context switch happened mid-load.
    _cacheSessionId = sessionId;
    _ringCache
      ..clear()
      ..addAll(rings);
    _legacyCache
      ..clear()
      ..addAll(legacy);
    _cursorCache = cursor;
  }

  bool _cacheValid(String? sessionId) =>
      sessionId != null && sessionId == _cacheSessionId;

  /// Active (non-retired) rings for one owner, strongest first — sync, from
  /// the cache (injection + prompt handles). Empty when the cache doesn't
  /// cover [sessionId].
  List<GrowthRingData> activeRingsFor(String? sessionId, String characterId) {
    if (!_cacheValid(sessionId)) return const [];
    return (_ringCache[characterId] ?? const [])
        .where((r) => !r.retired)
        .toList();
  }

  /// Every ring (active + retired) for one owner — sync, for the timeline UI.
  List<GrowthRingData> allRingsFor(String? sessionId, String characterId) {
    if (!_cacheValid(sessionId)) return const [];
    return List.unmodifiable(_ringCache[characterId] ?? const []);
  }

  /// The not-yet-distilled legacy evolved blob for one owner (personality,
  /// scenario), or null once distilled/absent.
  (String, String)? legacyBlobFor(String? sessionId, String characterId) {
    if (!_cacheValid(sessionId)) return null;
    return _legacyCache[characterId];
  }

  /// Fresh rings for one owner straight from the DB (the pass snapshot —
  /// the prompt numbers handles off this exact list's active subset).
  Future<List<GrowthRingData>> ringsFor(
    String sessionId,
    String characterId,
  ) async {
    final db = getDb();
    if (db == null) return const [];
    return db.getGrowthRings(sessionId, characterId);
  }

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
      final active = (await db.getGrowthRings(sessionId, characterId))
          .where((r) => !r.retired)
          .toList();
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
          jsonEncode(mergedReceipts(ring, sourcePositions)),
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
      GrowthRingsCompanion(pinned: Value(pinned), updatedAt: Value(DateTime.now())),
    );
  }

  /// Hard-delete a single ring (user action in the timeline).
  Future<void> deleteRing(String id) async {
    await getDb()?.deleteGrowthRing(id);
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

  Future<int> cursorFor(String sessionId) async =>
      (await getDb()?.getGrowthCursor(sessionId)) ?? 0;

  /// Sync cursor read for the due-check trigger (fresh after [refresh] and
  /// kept current by [setCursor]; 0 when the cache doesn't cover the
  /// session, which just makes the trigger fire and the pass re-check).
  int cursorCachedFor(String? sessionId) =>
      _cacheValid(sessionId) ? _cursorCache : 0;

  Future<void> setCursor(String sessionId, int cursor) async {
    await getDb()?.setGrowthCursor(sessionId, cursor);
    if (_cacheValid(sessionId)) _cursorCache = cursor;
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
            groupEvolvedPersonalities: Value(
              parent.groupEvolvedPersonalities,
            ),
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
        pers = _parseJsonMap(source.groupEvolvedPersonalities)[fromCharId] ?? '';
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

  /// Merged, deduplicated receipt positions for a ring + new citations.
  static List<int> mergedReceipts(GrowthRingData ring, List<int> extra) {
    final merged = <int>{...receiptsOf(ring), ...extra}.toList()..sort();
    return merged;
  }

  /// Decoded receipt positions of a ring (empty on null/garbage).
  static List<int> receiptsOf(GrowthRingData ring) {
    final raw = ring.sourceMessageIds;
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => e is int ? e : int.tryParse('$e'))
          .whereType<int>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _retire(AppDatabase db, String id) => db.updateGrowthRing(
    id,
    GrowthRingsCompanion(
      retired: const Value(true),
      updatedAt: Value(DateTime.now()),
    ),
  );

  Map<String, String> _parseJsonMap(String? json) {
    if (json == null || json.isEmpty) return {};
    try {
      return (jsonDecode(json) as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, v?.toString() ?? ''),
      );
    } catch (_) {
      return {};
    }
  }
}
