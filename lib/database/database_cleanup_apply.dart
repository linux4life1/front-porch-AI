// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Destructive cleanup: delete orphans and rewrite broken JSON refs.
// Scan counts stay on DatabaseCleanup. Identity is
// DatabaseCleanup._liveCharacterIdentities (stableGroupIdFrom, never
// characters.id alone for objectives / embeddings / data bank).

part of 'database_cleanup.dart';

Future<CleanupResult> _cleanOrphansImpl(AppDatabase db) async {
  final removedCounts = <String, int>{};
  final fixedRefCounts = <String, int>{};
  final liveIds = await DatabaseCleanup._liveCharacterIdentities(db);

  removedCounts['avatar_images'] = await _deleteOrphanRows(
    db,
    'avatar_images',
    'character_id',
    liveIds,
  );
  removedCounts['data_bank_entries'] = await _deleteOrphanRows(
    db,
    'data_bank_entries',
    'character_id',
    liveIds,
  );
  removedCounts['objectives'] = await _deleteOrphanRows(
    db,
    'objectives',
    'character_id',
    liveIds,
  );
  removedCounts['message_embeddings'] = await _deleteOrphanMessageEmbeddings(
    db,
    liveIds,
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
  // audit P2.20 — growth + Living Worlds + dead-chat objectives
  removedCounts['growth_rings'] = await _deleteOrphanBySession(
    db,
    'growth_rings',
  );
  removedCounts['growth_state'] = await _deleteOrphanBySession(
    db,
    'growth_state',
  );
  removedCounts['chat_worlds'] = await _deleteOrphanChatWorlds(db);
  removedCounts['chat_biome_spans'] = await _deleteOrphanChatBiomeSpans(db);
  removedCounts['dead_chat_objectives'] = await _deleteOrphanObjectivesByChat(
    db,
  );

  fixedRefCounts['memory_sources'] = await _fixBrokenMemorySources(db);
  fixedRefCounts['group_character_ids'] = await _fixBrokenGroupCharIds(db);
  fixedRefCounts['group_world_refs'] = await _fixBrokenGroupWorldIds(db);

  await db.bumpSyncVersion();

  return CleanupResult(
    removedCounts: removedCounts,
    fixedRefCounts: fixedRefCounts,
  );
}

Future<int> _deleteOrphanRows(
  AppDatabase db,
  String table,
  String column,
  Set<String> liveIds,
) async {
  return db.customUpdate(
    'DELETE FROM $table '
    'WHERE $column IS NOT NULL${DatabaseCleanup._notInClause(column, liveIds)}',
    variables: DatabaseCleanup._idVars(liveIds),
    updates: {},
  );
}

Future<int> _deleteOrphanMessageEmbeddings(
  AppDatabase db,
  Set<String> liveIds,
) async {
  return db.customUpdate(
    'DELETE FROM message_embeddings '
    'WHERE (character_id IS NOT NULL'
    '${DatabaseCleanup._notInClause('character_id', liveIds)}) '
    'OR NOT EXISTS '
    '(SELECT 1 FROM sessions s WHERE s.id = message_embeddings.session_id)',
    variables: DatabaseCleanup._idVars(liveIds),
    updates: {},
  );
}

/// Deletes orphan sessions and cascades to their messages + embeddings.
Future<int> _deleteOrphanSessionsCascade(AppDatabase db) async {
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
Future<int> _deleteOrphanGroupSessionsCascade(AppDatabase db) async {
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

Future<int> _deleteOrphanMessages(AppDatabase db) async {
  return db.customUpdate('''
      DELETE FROM messages WHERE session_id NOT IN (
        SELECT id FROM sessions
      )
    ''', updates: {});
}

Future<int> _deleteOrphanJournalMemories(AppDatabase db) async {
  return db.customUpdate('''
      DELETE FROM journal_memories WHERE session_id NOT IN (
        SELECT id FROM sessions
      )
    ''', updates: {});
}

Future<int> _deleteOrphanBySession(AppDatabase db, String table) async {
  return db.customUpdate('''
      DELETE FROM $table WHERE session_id NOT IN (SELECT id FROM sessions)
    ''', updates: {});
}

Future<int> _deleteOrphanChatWorlds(AppDatabase db) async {
  return db.customUpdate('''
      DELETE FROM chat_worlds WHERE
        chat_id NOT IN (SELECT id FROM sessions)
        OR world_id NOT IN (SELECT id FROM worlds WHERE deleted_at IS NULL)
    ''', updates: {});
}

Future<int> _deleteOrphanChatBiomeSpans(AppDatabase db) async {
  return db.customUpdate('''
      DELETE FROM chat_biome_spans WHERE chat_id NOT IN (SELECT id FROM sessions)
    ''', updates: {});
}

Future<int> _deleteOrphanObjectivesByChat(AppDatabase db) async {
  return db.customUpdate('''
      DELETE FROM objectives WHERE chat_id IS NOT NULL
        AND chat_id NOT IN (SELECT id FROM sessions)
    ''', updates: {});
}

Future<int> _fixBrokenMemorySources(AppDatabase db) async {
  final validIds = await DatabaseCleanup._getValidCharacterIds(db);
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

Future<int> _fixBrokenGroupCharIds(AppDatabase db) async {
  final validIds = await DatabaseCleanup._getValidCharacterIds(db);
  return _fixJsonRefs(db, 'groups', 'character_ids', validIds);
}

Future<int> _fixBrokenGroupWorldIds(AppDatabase db) async {
  final valid = await DatabaseCleanup._getValidWorldRefs(db);
  return _fixGroupWorldRefs(db, valid);
}

/// Drop unresolvable refs; rewrite surviving names → UUID.
Future<int> _fixGroupWorldRefs(
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
        final id = valid.ids.contains(ref) ? ref : valid.nameToId[ref];
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

Future<int> _fixJsonRefs(
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
