// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// v51→v52 chat_worlds.is_primary + backfill first climate-enabled → primary.

import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() async => db.close());

  test('schemaVersion is at least 52', () {
    expect(db.schemaVersion, greaterThanOrEqualTo(52));
  });

  test('Table, ladder, and repair declare is_primary DEFAULT 0', () async {
    final table = await File(
      'lib/database/database.tables.features.dart',
    ).readAsString();
    final ladder = await File(
      'lib/database/database.migrations.dart',
    ).readAsString();
    final repair = await File(
      'lib/database/database.repair.dart',
    ).readAsString();

    expect(table, contains('isPrimary'));
    expect(ladder, contains('ALTER TABLE chat_worlds ADD COLUMN is_primary'));
    expect(
      RegExp(
        r"is_primary[\s']+INTEGER NOT NULL DEFAULT 0",
      ).hasMatch(ladder),
      isTrue,
    );
    expect(
      repair,
      contains('is_primary INTEGER NOT NULL DEFAULT 0'),
    );
  });

  test('setChatWorldAttachments writes primary + lore roles', () async {
    await db.insertWorld(
      WorldsCompanion.insert(id: 'earth', name: 'Earth'),
    );
    await db.insertWorld(
      WorldsCompanion.insert(
        id: 'mars',
        name: 'Mars',
        climateEnabled: const Value(true),
      ),
    );
    await db.insertWorld(
      WorldsCompanion.insert(
        id: 'soul',
        name: 'Soul Society',
        climateEnabled: const Value(false),
      ),
    );

    await db.setChatWorldAttachments(
      'chat-1',
      primaryId: 'earth',
      loreIds: ['mars', 'soul'],
    );

    final slots = await db.getChatWorldAttachments('chat-1');
    expect(slots.primaryId, 'earth');
    expect(slots.loreIds, ['mars', 'soul']);
    expect(await db.getWorldIdsForChat('chat-1'), ['earth', 'mars', 'soul']);

    final rows = await db.customSelect(
      'SELECT world_id, is_primary, sort_order FROM chat_worlds '
      "WHERE chat_id = 'chat-1' ORDER BY sort_order",
    ).get();
    expect(rows, hasLength(3));
    final byId = {
      for (final r in rows) r.read<String>('world_id'): r,
    };
    expect(byId['earth']!.read<int>('is_primary'), 1);
    expect(byId['mars']!.read<int>('is_primary'), 0);
    expect(byId['soul']!.read<int>('is_primary'), 0);
  });

  test('setChatWorlds partitions first climate-enabled as primary', () async {
    await db.insertWorld(
      WorldsCompanion.insert(
        id: 'soul',
        name: 'Soul Society',
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
    await db.insertWorld(
      WorldsCompanion.insert(
        id: 'venus',
        name: 'Venus',
        climateEnabled: const Value(true),
      ),
    );

    await db.setChatWorlds('chat-2', ['soul', 'mars', 'venus']);
    final slots = await db.getChatWorldAttachments('chat-2');
    expect(slots.primaryId, 'mars');
    expect(slots.loreIds, ['soul', 'venus']);
  });

  test('backfill SQL picks first climate-enabled by sort_order', () async {
    await db.customStatement(
      'CREATE TABLE chat_worlds_v51_sim ('
      'id TEXT NOT NULL PRIMARY KEY, '
      'chat_id TEXT NOT NULL, '
      'world_id TEXT NOT NULL, '
      'sort_order INTEGER NOT NULL DEFAULT 0)',
    );
    await db.customStatement(
      'CREATE TABLE worlds_v51_sim ('
      'id TEXT NOT NULL PRIMARY KEY, '
      'climate_enabled INTEGER NOT NULL DEFAULT 1)',
    );
    await db.customStatement(
      "INSERT INTO worlds_v51_sim VALUES ('soul', 0), ('mars', 1), ('venus', 1)",
    );
    await db.customStatement(
      "INSERT INTO chat_worlds_v51_sim VALUES "
      "('r1', 'c', 'soul', 0), ('r2', 'c', 'mars', 1), ('r3', 'c', 'venus', 2)",
    );
    await db.customStatement(
      'ALTER TABLE chat_worlds_v51_sim '
      'ADD COLUMN is_primary INTEGER NOT NULL DEFAULT 0',
    );
    await db.customStatement(
      'UPDATE chat_worlds_v51_sim '
      'SET is_primary = 1 '
      'WHERE id IN ('
      '  SELECT cw.id FROM chat_worlds_v51_sim cw '
      '  INNER JOIN worlds_v51_sim w ON w.id = cw.world_id '
      '  WHERE w.climate_enabled = 1 AND cw.id = ('
      '    SELECT cw2.id FROM chat_worlds_v51_sim cw2 '
      '    INNER JOIN worlds_v51_sim w2 ON w2.id = cw2.world_id '
      '    WHERE cw2.chat_id = cw.chat_id AND w2.climate_enabled = 1 '
      '    ORDER BY cw2.sort_order ASC, cw2.id ASC LIMIT 1'
      '  )'
      ')',
    );
    final rows = await db.customSelect(
      'SELECT world_id, is_primary FROM chat_worlds_v51_sim ORDER BY sort_order',
    ).get();
    expect(
      {
        for (final r in rows)
          r.read<String>('world_id'): r.read<int>('is_primary'),
      },
      {'soul': 0, 'mars': 1, 'venus': 0},
    );
  });
}
