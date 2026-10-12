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

import 'package:drift/drift.dart';

import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/database/database.dart';
import 'growth_ops.dart' show hasGrowthMacros;
import 'growth_physics.dart';
import 'growth_store/growth_ring_writer.dart';

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

  late final GrowthRingWriter _writer = GrowthRingWriter(
    getDb: getDb,
    resolve: _resolved,
  );

  String? _cacheSessionId;
  final Map<String, List<GrowthRingData>> _ringCache = {};
  int _cursorCache = 0;

  /// Bumped by every [refresh] and by [invalidate]. A load that finishes after
  /// a newer one started (or after an explicit invalidate) drops its result
  /// instead of stamping the cache with its own — otherwise a chat switch
  /// during a slow load left the cache tagged with the OLD session and every
  /// sync reader below returned empty for the live chat, silently dropping the
  /// [Character Growth] block from the prompt.
  int _refreshEpoch = 0;

  /// charId → (legacy evolved personality, legacy evolved scenario) still
  /// waiting to be distilled into rings (design §8). Injection keeps using
  /// the blob until the distill pass succeeds — no behavior cliff.
  final Map<String, (String, String)> _legacyCache = {};

  /// Drop the cache (context switches). The next [refresh] repopulates it.
  void invalidate() {
    _refreshEpoch++;
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
    final epoch = ++_refreshEpoch;
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
          final pers = parseEvolvedJsonMap(session.groupEvolvedPersonalities);
          final scen = parseEvolvedJsonMap(session.groupEvolvedScenarios);
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

    // Swap atomically only if no context switch happened mid-load. The comment
    // said this long before the check existed: the swap was unconditional, so
    // a load that started first but finished last re-stamped the cache with a
    // session the user had already left (release audit 2026-08-15).
    if (epoch != _refreshEpoch) return;
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

  /// Merged, deduplicated receipt positions for a ring + new citations.
  static List<int> mergedReceipts(GrowthRingData ring, List<int> extra) =>
      mergedGrowthReceipts(ring, extra);

  /// Decoded receipt positions of a ring (empty on null/garbage).
  static List<int> receiptsOf(GrowthRingData ring) =>
      decodeReceiptIds(ring.sourceMessageIds);

  // ── Ring writes (GrowthRingWriter) ─────────────────────────────────────

  /// See [GrowthRingWriter.addRing].
  Future<void> addRing({
    required String sessionId,
    required String characterId,
    required String content,
    required String category,
    List<int> sourcePositions = const [],
    double strength = GrowthPhysics.kNewRingStrength,
    bool pinned = false,
    bool retired = false,
  }) => _writer.addRing(
    sessionId: sessionId,
    characterId: characterId,
    content: content,
    category: category,
    sourcePositions: sourcePositions,
    strength: strength,
    pinned: pinned,
    retired: retired,
  );

  /// See [GrowthRingWriter.reinforceRing].
  Future<void> reinforceRing(
    GrowthRingData ring, {
    List<int> sourcePositions = const [],
  }) => _writer.reinforceRing(ring, sourcePositions: sourcePositions);

  /// See [GrowthRingWriter.reviseRing].
  Future<void> reviseRing(
    GrowthRingData ring, {
    required String content,
    String? category,
  }) => _writer.reviseRing(ring, content: content, category: category);

  /// See [GrowthRingWriter.retireRing].
  Future<void> retireRing(String id) => _writer.retireRing(id);

  /// See [GrowthRingWriter.unretireRing].
  Future<void> unretireRing(GrowthRingData ring) => _writer.unretireRing(ring);

  /// See [GrowthRingWriter.setPinned].
  Future<void> setPinned(String id, bool pinned) =>
      _writer.setPinned(id, pinned);

  /// See [GrowthRingWriter.deleteRing].
  Future<void> deleteRing(String id) => _writer.deleteRing(id);

  /// See [GrowthRingWriter.invalidateRingsCitingFrom].
  Future<int> invalidateRingsCitingFrom(
    String sessionId,
    int fromPosition,
  ) async {
    final removed = await _writer.invalidateRingsCitingFrom(
      sessionId,
      fromPosition,
    );
    if (removed > 0 && _cacheValid(sessionId)) {
      // Drop cache so injection/timeline re-read DB without phantom rings.
      invalidate();
    }
    return removed;
  }

  /// See [GrowthRingWriter.deleteAllFor].
  Future<void> deleteAllFor(String sessionId, String characterId) =>
      _writer.deleteAllFor(sessionId, characterId);

  /// See [GrowthRingWriter.fadeUnreinforced].
  Future<void> fadeUnreinforced(
    String sessionId,
    String characterId,
    Set<String> reinforcedIds,
  ) => _writer.fadeUnreinforced(sessionId, characterId, reinforcedIds);

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
    final cleared = await _writer.clearLegacyColumns(
      sessionId,
      characterId,
      isGroup: isGroup,
    );
    if (cleared) _legacyCache.remove(characterId);
  }

  /// See [GrowthRingWriter.copySessionTo].
  Future<void> copySessionTo(
    String fromSessionId,
    String toSessionId, {
    required int cursor,
  }) => _writer.copySessionTo(fromSessionId, toSessionId, cursor: cursor);

  /// See [GrowthRingWriter.carryOwnerGrowth].
  Future<void> carryOwnerGrowth({
    required String fromSessionId,
    required String fromCharId,
    required String toSessionId,
    required String toCharId,
    required bool fromIsGroup,
    required bool toIsGroup,
  }) => _writer.carryOwnerGrowth(
    fromSessionId: fromSessionId,
    fromCharId: fromCharId,
    toSessionId: toSessionId,
    toCharId: toCharId,
    fromIsGroup: fromIsGroup,
    toIsGroup: toIsGroup,
  );
}
