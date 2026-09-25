// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Session-scoped journal / growth / embedding re-key. Lives next to
// the memory queries so database.queries.memory.dart stays under the
// handwritten bar.

part of 'database.dart';

extension AppDatabaseMemoryRekey on AppDatabase {
  /// Move this chat's journal, growth, and embedding rows from a
  /// legacy name/basename key onto the member UUID. Other sessions
  /// holding the same name are untouched. Safe to repeat: a second
  /// pass matches zero rows.
  Future<void> rekeySessionMemoryCharacterId(
    String fromId,
    String toId, {
    required String sessionId,
  }) async {
    if (fromId == toId || fromId.isEmpty || toId.isEmpty || sessionId.isEmpty) {
      return;
    }
    await customUpdate(
      'UPDATE journal_memories SET character_id = ? '
      'WHERE character_id = ? AND session_id = ?',
      variables: [Variable(toId), Variable(fromId), Variable(sessionId)],
      updates: {journalMemories},
    );
    await customUpdate(
      'UPDATE growth_rings SET character_id = ? '
      'WHERE character_id = ? AND session_id = ?',
      variables: [Variable(toId), Variable(fromId), Variable(sessionId)],
      updates: {growthRings},
    );
    await customUpdate(
      'UPDATE message_embeddings SET character_id = ? '
      'WHERE character_id = ? AND session_id = ?',
      variables: [Variable(toId), Variable(fromId), Variable(sessionId)],
      updates: {messageEmbeddings},
    );
  }
}
