// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Chat History Save used to call updateSession with only name/description
// through Drift replace(), which snapped every defaulted column: Realism /
// Needs / Chaos off, group realism blob emptied, scores/emotion reset,
// created-at jumped to now (full-codebase audit P0).
//
// Proven red: restore `.replace(session)` in updateSession and the first
// test fails (realismEnabled reads back false).

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() async => db.close());

  test(
    'a name-only updateSession keeps Realism/Needs/Chaos and group state',
    () async {
      final created = DateTime.utc(2024, 6, 15, 12);
      await db.insertSession(
        SessionsCompanion.insert(
          id: 's-rename',
          characterId: const Value('char-1'),
          groupId: const Value('group-1'),
          name: const Value('Old title'),
          description: const Value('old desc'),
          realismEnabled: const Value(true),
          needsSimEnabled: const Value(true),
          chaosModeEnabled: const Value(true),
          groupRealismState: const Value('{"Alex":{"affection":42}}'),
          affectionScore: const Value(99),
          characterEmotion: const Value('amused'),
          createdAt: Value(created),
        ),
      );

      await db.updateSession(
        const SessionsCompanion(
          id: Value('s-rename'),
          name: Value('New title'),
        ),
      );

      final row = await db.getSessionById('s-rename');
      expect(row, isNotNull);
      expect(row!.name, 'New title');
      expect(row.characterId, 'char-1');
      expect(row.groupId, 'group-1');
      expect(row.description, 'old desc');
      expect(row.realismEnabled, isTrue);
      expect(row.needsSimEnabled, isTrue);
      expect(row.chaosModeEnabled, isTrue);
      expect(row.groupRealismState, '{"Alex":{"affection":42}}');
      expect(row.affectionScore, 99);
      expect(row.characterEmotion, 'amused');
      // replace() would rewrite created_at to now. SQLite stores the
      // timestamp without a zone, so compare the calendar day not the
      // UTC DateTime object.
      expect(row.createdAt.year, 2024);
      expect(row.createdAt.month, 6);
      expect(row.createdAt.day, 15);
    },
  );

  test('Chat History Save two writes keep name AND description', () async {
    // The dialog calls renameSession then updateSessionDescription.
    // Two sequential replace()s would null the name on the second write.
    await db.insertSession(
      SessionsCompanion.insert(
        id: 's-save',
        characterId: const Value('char-1'),
        name: const Value('old'),
        description: const Value('old desc'),
        realismEnabled: const Value(true),
      ),
    );
    await db.updateSession(
      const SessionsCompanion(id: Value('s-save'), name: Value('New title')),
    );
    await db.updateSession(
      const SessionsCompanion(
        id: Value('s-save'),
        description: Value('new desc'),
      ),
    );
    final row = await db.getSessionById('s-save');
    expect(row!.name, 'New title');
    expect(row.description, 'new desc');
    expect(row.characterId, 'char-1');
    expect(row.realismEnabled, isTrue);
  });
}
