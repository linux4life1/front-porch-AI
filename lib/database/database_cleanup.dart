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

    orphanCounts['avatar_images'] = await _countOrphanRows(
      db,
      'avatar_images',
      'character_id',
    );
    orphanCounts['objectives'] = await _countOrphanRows(
      db,
      'objectives',
      'character_id',
    );
    orphanCounts['data_bank_entries'] = await _countOrphanRows(
      db,
      'data_bank_entries',
      'character_id',
    );
    orphanCounts['message_embeddings'] = await _countOrphanMessageEmbeddings(
      db,
    );
    orphanCounts['sessions'] = await _countOrphanSessions(db);
    orphanCounts['group_orphan_sessions'] = await _countOrphanGroupSessions(db);
    orphanCounts['messages'] = await _countOrphanMessages(db);
    orphanCounts['journal_memories'] = await _countOrphanJournalMemories(db);

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
  static Future<CleanupResult> cleanOrphans(AppDatabase db) async {
    final removedCounts = <String, int>{};
    final fixedRefCounts = <String, int>{};

    removedCounts['avatar_images'] = await _deleteOrphanRows(
      db,
      'avatar_images',
      'character_id',
    );
    removedCounts['data_bank_entries'] = await _deleteOrphanRows(
      db,
      'data_bank_entries',
      'character_id',
    );
    removedCounts['objectives'] = await _deleteOrphanRows(
      db,
      'objectives',
      'character_id',
    );
    removedCounts['message_embeddings'] = await _deleteOrphanMessageEmbeddings(
      db,
    );
    removedCounts['sessions'] = await _deleteOrphanSessionsCascade(db);
    removedCounts['group_orphan_sessions'] =
        await _deleteOrphanGroupSessionsCascade(db);
    removedCounts['messages'] = await _deleteOrphanMessages(db);
    // After the session cascades above so cards from just-removed sessions
    // are swept in the same run. Journal cards are strictly session-scoped,
    // so orphan = session gone (character_id is a stableGroupId, not a
    // characters.id — do not check it against the characters table).
    removedCounts['journal_memories'] = await _deleteOrphanJournalMemories(db);

    fixedRefCounts['memory_sources'] = await _fixBrokenMemorySources(db);
    fixedRefCounts['group_character_ids'] = await _fixBrokenGroupCharIds(db);
    fixedRefCounts['group_world_refs'] = await _fixBrokenGroupWorldIds(db);

    await db.bumpSyncVersion();

    return CleanupResult(
      removedCounts: removedCounts,
      fixedRefCounts: fixedRefCounts,
    );
  }

  // ── Counting helpers ────────────────────────────────────────────────

  static Future<int> _countOrphanRows(
    AppDatabase db,
    String table,
    String column,
  ) async {
    final result = await db.customSelect('''
      SELECT COUNT(*) AS c FROM $table t
      LEFT JOIN characters c ON c.id = t.$column
      WHERE c.id IS NULL OR c.deleted_at IS NOT NULL
    ''').get();
    return (result.first.data['c'] as int?) ?? 0;
  }

  static Future<int> _countOrphanMessageEmbeddings(AppDatabase db) async {
    final result = await db.customSelect('''
      SELECT COUNT(*) AS c FROM message_embeddings me
      WHERE (me.character_id IS NOT NULL AND (
        NOT EXISTS (SELECT 1 FROM characters c WHERE c.id = me.character_id AND c.deleted_at IS NULL)
      ))
      OR NOT EXISTS (SELECT 1 FROM sessions s WHERE s.id = me.session_id)
    ''').get();
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

  // ── Deletion helpers ────────────────────────────────────────────────

  static Future<int> _deleteOrphanRows(
    AppDatabase db,
    String table,
    String column,
  ) async {
    return db.customUpdate('''
      DELETE FROM $table WHERE rowid IN (
        SELECT t.rowid FROM $table t
        LEFT JOIN characters c ON c.id = t.$column
        WHERE c.id IS NULL OR c.deleted_at IS NOT NULL
      )
    ''', updates: {});
  }

  static Future<int> _deleteOrphanMessageEmbeddings(AppDatabase db) async {
    return db.customUpdate('''
      DELETE FROM message_embeddings WHERE rowid IN (
        SELECT me.rowid FROM message_embeddings me
        WHERE (me.character_id IS NOT NULL AND (
          NOT EXISTS (SELECT 1 FROM characters c WHERE c.id = me.character_id AND c.deleted_at IS NULL)
        ))
        OR NOT EXISTS (SELECT 1 FROM sessions s WHERE s.id = me.session_id)
      )
    ''', updates: {});
  }

  /// Deletes orphan sessions and cascades to their messages + embeddings.
  static Future<int> _deleteOrphanSessionsCascade(AppDatabase db) async {
    await db.customUpdate('''
      DELETE FROM message_embeddings WHERE session_id IN (
        SELECT id FROM sessions WHERE character_id IS NOT NULL AND (
          NOT EXISTS (SELECT 1 FROM characters c WHERE c.id = sessions.character_id AND c.deleted_at IS NULL)
        )
      )
    ''', updates: {});
    await db.customUpdate('''
      DELETE FROM messages WHERE session_id IN (
        SELECT id FROM sessions WHERE character_id IS NOT NULL AND (
          NOT EXISTS (SELECT 1 FROM characters c WHERE c.id = sessions.character_id AND c.deleted_at IS NULL)
        )
      )
    ''', updates: {});
    return db.customUpdate('''
      DELETE FROM sessions WHERE character_id IS NOT NULL AND (
        NOT EXISTS (SELECT 1 FROM characters c WHERE c.id = sessions.character_id AND c.deleted_at IS NULL)
      )
    ''', updates: {});
  }

  /// Deletes group-orphaned sessions and cascades to their messages + embeddings.
  static Future<int> _deleteOrphanGroupSessionsCascade(AppDatabase db) async {
    await db.customUpdate('''
      DELETE FROM message_embeddings WHERE session_id IN (
        SELECT s.id FROM sessions s
        LEFT JOIN groups g ON g.id = s.group_id
        WHERE s.character_id IS NULL AND s.group_id IS NOT NULL
          AND (g.id IS NULL OR g.deleted_at IS NOT NULL)
      )
    ''', updates: {});
    await db.customUpdate('''
      DELETE FROM messages WHERE session_id IN (
        SELECT s.id FROM sessions s
        LEFT JOIN groups g ON g.id = s.group_id
        WHERE s.character_id IS NULL AND s.group_id IS NOT NULL
          AND (g.id IS NULL OR g.deleted_at IS NOT NULL)
      )
    ''', updates: {});
    return db.customUpdate('''
      DELETE FROM sessions WHERE rowid IN (
        SELECT s.rowid FROM sessions s
        LEFT JOIN groups g ON g.id = s.group_id
        WHERE s.character_id IS NULL AND s.group_id IS NOT NULL
          AND (g.id IS NULL OR g.deleted_at IS NOT NULL)
      )
    ''', updates: {});
  }

  static Future<int> _deleteOrphanMessages(AppDatabase db) async {
    return db.customUpdate('''
      DELETE FROM messages WHERE session_id NOT IN (
        SELECT id FROM sessions
      )
    ''', updates: {});
  }

  static Future<int> _deleteOrphanJournalMemories(AppDatabase db) async {
    return db.customUpdate('''
      DELETE FROM journal_memories WHERE session_id NOT IN (
        SELECT id FROM sessions
      )
    ''', updates: {});
  }

  // ── JSON fix helpers ────────────────────────────────────────────────

  static Future<int> _fixBrokenMemorySources(AppDatabase db) async {
    final validIds = await _getValidCharacterIds(db);
    final rows = await db.customSelect('''
      SELECT id, memory_sources FROM characters
      WHERE deleted_at IS NULL AND memory_sources IS NOT NULL AND memory_sources != '[]'
    ''').get();
    int fixed = 0;
    for (final row in rows) {
      final charId = row.data['id'] as String;
      final raw = row.data['memory_sources'] as String?;
      if (raw == null || raw.isEmpty) continue;
      try {
        final ids = List<String>.from(jsonDecode(raw));
        final cleaned = ids.where((id) => validIds.contains(id)).toList();
        if (cleaned.length != ids.length) {
          await db.customUpdate(
            'UPDATE characters SET memory_sources = ? WHERE id = ?',
            variables: [Variable(jsonEncode(cleaned)), Variable(charId)],
            updates: {db.characters},
          );
          fixed++;
        }
      } catch (e) {
        debugPrint(
          '[DB Cleanup] Failed to parse memory_sources for character $charId: $e',
        );
      }
    }
    return fixed;
  }

  static Future<int> _fixBrokenGroupCharIds(AppDatabase db) async {
    final validIds = await _getValidCharacterIds(db);
    return _fixJsonRefs(db, 'groups', 'character_ids', validIds);
  }

  static Future<int> _fixBrokenGroupWorldIds(AppDatabase db) async {
    final valid = await _getValidWorldRefs(db);
    return _fixGroupWorldRefs(db, valid);
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

  /// Drop unresolvable refs; rewrite surviving names → UUID.
  static Future<int> _fixGroupWorldRefs(
    AppDatabase db,
    ({Set<String> ids, Map<String, String> nameToId}) valid,
  ) async {
    final rows = await db.customSelect('''
      SELECT id, world_ids FROM groups
      WHERE deleted_at IS NULL AND world_ids IS NOT NULL AND world_ids != '[]'
    ''').get();
    var fixed = 0;
    for (final row in rows) {
      final groupId = row.data['id'] as String;
      final raw = row.data['world_ids'] as String?;
      if (raw == null || raw.isEmpty) continue;
      try {
        final refs = List<String>.from(jsonDecode(raw));
        final cleaned = <String>[];
        final seen = <String>{};
        for (final ref in refs) {
          final id = valid.ids.contains(ref)
              ? ref
              : valid.nameToId[ref];
          if (id == null) continue;
          if (seen.add(id)) cleaned.add(id);
        }
        final encoded = jsonEncode(cleaned);
        if (encoded != raw) {
          await db.customUpdate(
            'UPDATE groups SET world_ids = ? WHERE id = ?',
            variables: [Variable(encoded), Variable(groupId)],
            updates: {db.groups},
          );
          fixed++;
        }
      } catch (e) {
        debugPrint(
          '[DB Cleanup] Failed to parse world_ids in group $groupId: $e',
        );
      }
    }
    return fixed;
  }

  static Future<int> _fixJsonRefs(
    AppDatabase db,
    String table,
    String column,
    Set<String> validIds,
  ) async {
    final rows = await db.customSelect('''
      SELECT id, $column FROM $table
      WHERE deleted_at IS NULL AND $column IS NOT NULL AND $column != '[]'
    ''').get();
    int fixed = 0;
    for (final row in rows) {
      final groupId = row.data['id'] as String;
      final raw = row.data[column] as String?;
      if (raw == null || raw.isEmpty) continue;
      try {
        final ids = List<String>.from(jsonDecode(raw));
        final cleaned = ids.where((id) => validIds.contains(id)).toList();
        if (cleaned.length != ids.length) {
          await db.customUpdate(
            'UPDATE $table SET $column = ? WHERE id = ?',
            variables: [Variable(jsonEncode(cleaned)), Variable(groupId)],
            updates: {db.groups},
          );
          fixed++;
        }
      } catch (e) {
        debugPrint(
          '[DB Cleanup] Failed to parse $column in $table row $groupId: $e',
        );
      }
    }
    return fixed;
  }

  // ── Valid ID sets ───────────────────────────────────────────────────

  static Future<Set<String>> _getValidCharacterIds(AppDatabase db) async {
    final rows = await db.customSelect('''
      SELECT id FROM characters WHERE deleted_at IS NULL
    ''').get();
    return rows.map((r) => r.data['id'] as String).toSet();
  }

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
