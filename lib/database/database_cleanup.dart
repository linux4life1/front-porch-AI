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

import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/utils/utils.dart';

part 'database_cleanup_apply.dart';

/// Report from [DatabaseCleanup.checkOrphans] — all counts are zero if the
/// database is clean.
class OrphanReport {
  final Map<String, int> orphanCounts;
  final Map<String, int> brokenRefCounts;

  const OrphanReport({
    this.orphanCounts = const {},
    this.brokenRefCounts = const {},
  });

  int get totalOrphans => orphanCounts.values.fold(0, (a, b) => a + b);
  int get totalBrokenRefs => brokenRefCounts.values.fold(0, (a, b) => a + b);
}

/// Result from [DatabaseCleanup.cleanOrphans].
class CleanupResult {
  final Map<String, int> removedCounts;
  final Map<String, int> fixedRefCounts;

  const CleanupResult({
    this.removedCounts = const {},
    this.fixedRefCounts = const {},
  });

  int get totalRemoved => removedCounts.values.fold(0, (a, b) => a + b);
  int get totalFixed => fixedRefCounts.values.fold(0, (a, b) => a + b);
}

/// Scans for and removes orphaned database records that accumulate when
/// characters are deleted (avatar_images, objectives, data_bank_entries,
/// message_embeddings, dangling sessions/messages, and stale JSON
/// cross-references in memory_sources / groups).
///
/// Safe to run at any time — read-only scan via [checkOrphans], mutating
/// cleanup via [cleanOrphans].
class DatabaseCleanup {
  DatabaseCleanup._();

  /// Scan the database without making any changes.
  static Future<OrphanReport> checkOrphans(AppDatabase db) async {
    final orphanCounts = <String, int>{};
    final brokenRefCounts = <String, int>{};
    final liveIds = await _liveCharacterIdentities(db);

    orphanCounts['avatar_images'] = await _countOrphanRows(
      db,
      'avatar_images',
      'character_id',
      liveIds,
    );
    orphanCounts['objectives'] = await _countOrphanRows(
      db,
      'objectives',
      'character_id',
      liveIds,
    );
    orphanCounts['data_bank_entries'] = await _countOrphanRows(
      db,
      'data_bank_entries',
      'character_id',
      liveIds,
    );
    orphanCounts['message_embeddings'] = await _countOrphanMessageEmbeddings(
      db,
      liveIds,
    );
    orphanCounts['sessions'] = await _countOrphanSessions(db);
    orphanCounts['group_orphan_sessions'] = await _countOrphanGroupSessions(db);
    orphanCounts['messages'] = await _countOrphanMessages(db);
    orphanCounts['journal_memories'] = await _countOrphanJournalMemories(db);
    // audit P2.20 — growth + Living Worlds + dead-chat objectives
    orphanCounts['growth_rings'] = await _countOrphanBySession(
      db,
      'growth_rings',
    );
    orphanCounts['growth_state'] = await _countOrphanBySession(
      db,
      'growth_state',
    );
    orphanCounts['chat_worlds'] = await _countOrphanChatWorlds(db);
    orphanCounts['chat_biome_spans'] = await _countOrphanChatBiomeSpans(db);
    orphanCounts['dead_chat_objectives'] = await _countOrphanObjectivesByChat(
      db,
    );

    brokenRefCounts['memory_sources'] = await _countBrokenMemorySources(db);
    brokenRefCounts['group_character_ids'] = await _countBrokenGroupCharIds(db);
    // Living Worlds: world_ids hold UUIDs (names still accepted as resolvable).
    brokenRefCounts['group_world_refs'] = await _countBrokenGroupWorldIds(db);

    return OrphanReport(
      orphanCounts: orphanCounts,
      brokenRefCounts: brokenRefCounts,
    );
  }

  /// Remove all orphaned records and fix broken cross-references.
  static Future<CleanupResult> cleanOrphans(AppDatabase db) =>
      _cleanOrphansImpl(db);

  // ── Counting helpers ────────────────────────────────────────────────

  /// Every identity a live character can legitimately be referenced by.
  ///
  /// `objectives`, `message_embeddings` and `data_bank_entries` key their
  /// `character_id` by the character's **stableGroupId** — the portable
  /// image-filename id from [StableGroupId] — not by the `characters.id`
  /// UUID. These queries used to join those columns straight against
  /// `characters.id`, so a UUID was compared to a filename, nothing ever
  /// matched, and every single row looked orphaned. Measured on a real
  /// library: 107 of 107 objectives and 68 of 68 RAG embeddings would have
  /// been deleted by the Database Cleanup dialog. Group members carry their
  /// own `group_members.id` UUID, so those are valid identities too.
  static Future<Set<String>> _liveCharacterIdentities(AppDatabase db) async {
    final ids = <String>{};
    final characters = await db
        .customSelect(
          'SELECT id, image_path, name FROM characters '
          'WHERE deleted_at IS NULL',
        )
        .get();
    for (final row in characters) {
      final id = row.data['id'] as String?;
      if (id != null && id.isNotEmpty) ids.add(id);
      ids.add(
        stableGroupIdFrom(
          row.data['image_path'] as String?,
          (row.data['name'] as String?) ?? '',
        ),
      );
    }
    final members = await db.customSelect('SELECT id FROM group_members').get();
    for (final row in members) {
      final id = row.data['id'] as String?;
      if (id != null && id.isNotEmpty) ids.add(id);
    }
    // Group RAG / Data Bank rows are keyed `group_<groups.id>` (see
    // ChatService._getCharacterId). Missing this is the 68/68 wipe class
    // for every group corpus — one click in Settings.
    final groups = await db
        .customSelect('SELECT id FROM groups WHERE deleted_at IS NULL')
        .get();
    for (final row in groups) {
      final id = row.data['id'] as String?;
      if (id != null && id.isNotEmpty) ids.add('group_$id');
    }
    ids.remove('');
    return ids;
  }

  /// `AND <column> NOT IN (?, ?, …)`, or an empty string when there are no
  /// live characters at all (in which case every referencing row really is
  /// orphaned and the bare NULL check is correct).
  static String _notInClause(String column, Set<String> liveIds) =>
      liveIds.isEmpty
      ? ''
      : ' AND $column NOT IN (${List.filled(liveIds.length, '?').join(',')})';

  static List<Variable<Object>> _idVars(Set<String> liveIds) => [
    for (final id in liveIds) Variable<String>(id),
  ];

  static Future<int> _countOrphanRows(
    AppDatabase db,
    String table,
    String column,
    Set<String> liveIds,
  ) async {
    final result = await db
        .customSelect(
          'SELECT COUNT(*) AS c FROM $table '
          'WHERE $column IS NOT NULL${_notInClause(column, liveIds)}',
          variables: _idVars(liveIds),
        )
        .get();
    return (result.first.data['c'] as int?) ?? 0;
  }

  static Future<int> _countOrphanMessageEmbeddings(
    AppDatabase db,
    Set<String> liveIds,
  ) async {
    final result = await db
        .customSelect(
          'SELECT COUNT(*) AS c FROM message_embeddings '
          'WHERE (character_id IS NOT NULL'
          '${_notInClause('character_id', liveIds)}) '
          'OR NOT EXISTS '
          '(SELECT 1 FROM sessions s WHERE s.id = message_embeddings.session_id)',
          variables: _idVars(liveIds),
        )
        .get();
    return (result.first.data['c'] as int?) ?? 0;
  }

  static Future<int> _countOrphanSessions(AppDatabase db) async {
    final result = await db.customSelect('''
      SELECT COUNT(*) AS c FROM sessions s
      WHERE s.character_id IS NOT NULL AND (
        NOT EXISTS (SELECT 1 FROM characters c WHERE c.id = s.character_id AND c.deleted_at IS NULL)
      )
    ''').get();
    return (result.first.data['c'] as int?) ?? 0;
  }

  static Future<int> _countOrphanGroupSessions(AppDatabase db) async {
    final result = await db.customSelect('''
      SELECT COUNT(*) AS c FROM sessions s
      LEFT JOIN groups g ON g.id = s.group_id
      WHERE s.character_id IS NULL AND s.group_id IS NOT NULL
        AND (g.id IS NULL OR g.deleted_at IS NOT NULL)
    ''').get();
    return (result.first.data['c'] as int?) ?? 0;
  }

  static Future<int> _countOrphanMessages(AppDatabase db) async {
    final result = await db.customSelect('''
      SELECT COUNT(*) AS c FROM messages m
      WHERE NOT EXISTS (SELECT 1 FROM sessions s WHERE s.id = m.session_id)
    ''').get();
    return (result.first.data['c'] as int?) ?? 0;
  }

  static Future<int> _countOrphanJournalMemories(AppDatabase db) async {
    final result = await db.customSelect('''
      SELECT COUNT(*) AS c FROM journal_memories jm
      WHERE NOT EXISTS (SELECT 1 FROM sessions s WHERE s.id = jm.session_id)
    ''').get();
    return (result.first.data['c'] as int?) ?? 0;
  }

  /// Rows keyed by session_id whose session is gone (growth rings/state).
  static Future<int> _countOrphanBySession(AppDatabase db, String table) async {
    final result = await db.customSelect('''
      SELECT COUNT(*) AS c FROM $table t
      WHERE NOT EXISTS (SELECT 1 FROM sessions s WHERE s.id = t.session_id)
    ''').get();
    return (result.first.data['c'] as int?) ?? 0;
  }

  static Future<int> _countOrphanChatWorlds(AppDatabase db) async {
    final result = await db.customSelect('''
      SELECT COUNT(*) AS c FROM chat_worlds cw
      WHERE NOT EXISTS (SELECT 1 FROM sessions s WHERE s.id = cw.chat_id)
         OR NOT EXISTS (SELECT 1 FROM worlds w WHERE w.id = cw.world_id AND w.deleted_at IS NULL)
    ''').get();
    return (result.first.data['c'] as int?) ?? 0;
  }

  static Future<int> _countOrphanChatBiomeSpans(AppDatabase db) async {
    final result = await db.customSelect('''
      SELECT COUNT(*) AS c FROM chat_biome_spans cbs
      WHERE NOT EXISTS (SELECT 1 FROM sessions s WHERE s.id = cbs.chat_id)
    ''').get();
    return (result.first.data['c'] as int?) ?? 0;
  }

  /// Objectives that name a chat_id whose session no longer exists
  /// (character-level orphans are covered by [_countOrphanRows]).
  static Future<int> _countOrphanObjectivesByChat(AppDatabase db) async {
    final result = await db.customSelect('''
      SELECT COUNT(*) AS c FROM objectives o
      WHERE o.chat_id IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM sessions s WHERE s.id = o.chat_id)
    ''').get();
    return (result.first.data['c'] as int?) ?? 0;
  }

  // ── Broken ref counting ─────────────────────────────────────────────

  static Future<int> _countBrokenMemorySources(AppDatabase db) async {
    final validIds = await _getValidCharacterIds(db);
    final rows = await db.customSelect('''
      SELECT memory_sources FROM characters
      WHERE deleted_at IS NULL AND memory_sources IS NOT NULL AND memory_sources != '[]'
    ''').get();
    int broken = 0;
    for (final row in rows) {
      final raw = row.data['memory_sources'] as String?;
      if (raw == null || raw.isEmpty) continue;
      try {
        final ids = List<String>.from(jsonDecode(raw));
        if (ids.any((id) => !validIds.contains(id))) broken++;
      } catch (e) {
        debugPrint('[DB Cleanup] Failed to parse memory_sources: $e');
      }
    }
    return broken;
  }

  static Future<int> _countBrokenGroupCharIds(AppDatabase db) async {
    final validIds = await _getValidCharacterIds(db);
    return _countBrokenJsonRefs(db, 'groups', 'character_ids', validIds);
  }

  static Future<int> _countBrokenGroupWorldIds(AppDatabase db) async {
    final valid = await _getValidWorldRefs(db);
    return _countBrokenWorldRefs(db, valid);
  }

  static Future<int> _countBrokenJsonRefs(
    AppDatabase db,
    String table,
    String column,
    Set<String> validIds,
  ) async {
    final rows = await db.customSelect('''
      SELECT id, $column FROM $table
      WHERE deleted_at IS NULL AND $column IS NOT NULL AND $column != '[]'
    ''').get();
    int broken = 0;
    for (final row in rows) {
      final raw = row.data[column] as String?;
      final rowId = row.data['id'] as String? ?? '?';
      if (raw == null || raw.isEmpty) continue;
      try {
        final ids = List<String>.from(jsonDecode(raw));
        if (ids.any((id) => !validIds.contains(id))) broken++;
      } catch (e) {
        debugPrint(
          '[DB Cleanup] Failed to parse $column in $table row $rowId: $e',
        );
      }
    }
    return broken;
  }

  /// Count group world_ids entries that resolve to neither a live world id
  /// nor a live world name (post–Living Worlds UUID column + legacy names).
  static Future<int> _countBrokenWorldRefs(
    AppDatabase db,
    ({Set<String> ids, Map<String, String> nameToId}) valid,
  ) async {
    final rows = await db.customSelect('''
      SELECT id, world_ids FROM groups
      WHERE deleted_at IS NULL AND world_ids IS NOT NULL AND world_ids != '[]'
    ''').get();
    var broken = 0;
    for (final row in rows) {
      final raw = row.data['world_ids'] as String?;
      if (raw == null || raw.isEmpty) continue;
      try {
        final refs = List<String>.from(jsonDecode(raw));
        if (refs.any(
          (r) => !valid.ids.contains(r) && !valid.nameToId.containsKey(r),
        )) {
          broken++;
        }
      } catch (e) {
        debugPrint(
          '[DB Cleanup] Failed to parse world_ids in group '
          '${row.data['id']}: $e',
        );
      }
    }
    return broken;
  }

  // ── Valid ID sets ───────────────────────────────────────────────────

  /// Live identities for JSON cross-refs (`memory_sources`, group
  /// `character_ids`). Must include stableGroupId / embedding basenames —
  /// the Memory picker stores those, not `characters.id` UUIDs. Reuses
  /// [_liveCharacterIdentities] so the two scanners cannot drift.
  static Future<Set<String>> _getValidCharacterIds(AppDatabase db) =>
      _liveCharacterIdentities(db);

  static Future<({Set<String> ids, Map<String, String> nameToId})>
  _getValidWorldRefs(AppDatabase db) async {
    final rows = await db.customSelect('''
      SELECT id, name FROM worlds WHERE deleted_at IS NULL
    ''').get();
    final ids = <String>{};
    final nameToId = <String, String>{};
    for (final r in rows) {
      final id = r.data['id'] as String?;
      final name = r.data['name'] as String?;
      if (id == null) continue;
      ids.add(id);
      if (name != null && name.isNotEmpty) nameToId[name] = id;
    }
    return (ids: ids, nameToId: nameToId);
  }
}
