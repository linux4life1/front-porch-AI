// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Group re-key must move objectives rows with the maps. Session-scoped
// always; card-level (chat_id IS NULL) only when asked.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/database/database.dart';

void main() {
  test(
    'rekeyObjectiveCharacterId moves session rows, not other chats',
    () async {
      final db = AppDatabase.forTesting();
      addTearDown(db.close);

      await db.insertObjective(
        ObjectivesCompanion.insert(
          id: 'o-sess',
          characterId: 'Ana',
          chatId: const Value('chat-a'),
          objective: 'Keep the porch swept',
        ),
      );
      await db.insertObjective(
        ObjectivesCompanion.insert(
          id: 'o-other',
          characterId: 'Ana',
          chatId: const Value('chat-b'),
          objective: 'Other chat quest',
        ),
      );
      await db.insertObjective(
        ObjectivesCompanion.insert(
          id: 'o-card',
          characterId: 'Ana',
          objective: 'Card-level quest',
        ),
      );

      await db.rekeyObjectiveCharacterId('Ana', 'mem-ana', chatId: 'chat-a');

      expect(
        (await db.getObjectivesForCharacter(
          'mem-ana',
          chatId: 'chat-a',
        )).single.id,
        'o-sess',
      );
      expect(
        (await db.getObjectivesForCharacter('Ana', chatId: 'chat-b')).single.id,
        'o-other',
      );
      expect((await db.getObjectivesForCharacter('Ana')).single.id, 'o-card');

      await db.rekeyObjectiveCharacterId('Ana', 'mem-ana');
      expect(
        (await db.getObjectivesForCharacter('mem-ana')).single.id,
        'o-card',
      );
      expect(await db.getObjectivesForCharacter('Ana'), isEmpty);
      expect(
        (await db.getObjectivesForCharacter('Ana', chatId: 'chat-b')).single.id,
        'o-other',
      );

      await db.rekeyObjectiveCharacterId('Ana', 'mem-ana', chatId: 'chat-a');
      expect(
        (await db.getObjectivesForCharacter(
          'mem-ana',
          chatId: 'chat-a',
        )).single.id,
        'o-sess',
      );
    },
  );
}
