// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Group-member objective row re-key. Lives next to the memory queries
// so database.queries.memory.dart stays under the handwritten bar.

part of 'database.dart';

extension AppDatabaseObjectiveRekey on AppDatabase {
  /// Move group-member objective rows from a legacy name/basename key
  /// onto the member UUID. Scoped to one [chatId], or to card-level
  /// rows (`chat_id IS NULL`) when [chatId] is omitted.
  Future<void> rekeyObjectiveCharacterId(
    String fromId,
    String toId, {
    String? chatId,
  }) async {
    if (fromId == toId || fromId.isEmpty || toId.isEmpty) return;
    if (chatId != null) {
      await customUpdate(
        'UPDATE objectives SET character_id = ? WHERE character_id = ? AND chat_id = ?',
        variables: [Variable(toId), Variable(fromId), Variable(chatId)],
        updates: {objectives},
      );
      return;
    }
    await customUpdate(
      'UPDATE objectives SET character_id = ? WHERE character_id = ? AND chat_id IS NULL',
      variables: [Variable(toId), Variable(fromId)],
      updates: {objectives},
    );
  }
}
