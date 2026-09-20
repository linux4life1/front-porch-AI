// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// v51→v52 Setting backfill must not re-run after a dual-version open.
// Drift stamps user_version down when an older binary opens a newer library;
// the next launch re-enters `from < 52`. Re-forcing the first climate-enabled
// place to Primary revives a Setting the user moved to lore (weather off).

import 'package:drift/drift.dart' show Migrator, Value, Variable;
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(sameIsolate: true));
  tearDown(() async => db.close());

  Future<void> rerunFrom51() =>
      db.migration.onUpgrade(Migrator(db), 51, db.schemaVersion);

  Future<int> primaryFlag(String chatId, String worldId) async {
    final row = await db
        .customSelect(
          'SELECT is_primary AS p FROM chat_worlds '
          'WHERE chat_id = ? AND world_id = ?',
          variables: [Variable(chatId), Variable(worldId)],
        )
        .getSingle();
    return row.read<int>('p');
  }

  test('re-run of v52 keeps a user-cleared Setting as lore', () async {
    await db.insertWorld(
      WorldsCompanion.insert(
        id: 'earth',
        name: 'Earth',
        climateEnabled: const Value(true),
      ),
    );
    await db.setChatWorldAttachments(
      'chat-lore',
      primaryId: null,
      loreIds: ['earth'],
    );
    expect(await primaryFlag('chat-lore', 'earth'), 0);

    await rerunFrom51();

    expect(
      await primaryFlag('chat-lore', 'earth'),
      0,
      reason:
          'is_primary already existed, so this pass is a re-entry after a '
          'rollback — a lore-only chat must stay lore',
    );
  });

  test('the real first pass still backfills first climate-enabled', () async {
    await db.insertWorld(
      WorldsCompanion.insert(
        id: 'soul',
        name: 'Soul',
        climateEnabled: const Value(false),
      ),
    );
    await db.insertWorld(
      WorldsCompanion.insert(
        id: 'mars',
        name: 'Mars',
        climateEnabled: const Value(true),
      ),
    );
    await db.customStatement('ALTER TABLE chat_worlds DROP COLUMN is_primary');
    await db.customStatement(
      "INSERT INTO chat_worlds (id, chat_id, world_id, sort_order) VALUES "
      "('r1', 'c-old', 'soul', 0), ('r2', 'c-old', 'mars', 1)",
    );

    await rerunFrom51();

    expect(await primaryFlag('c-old', 'soul'), 0);
    expect(
      await primaryFlag('c-old', 'mars'),
      1,
      reason: 'the genuine upgrade still marks the first climate-enabled place',
    );
  });
}
