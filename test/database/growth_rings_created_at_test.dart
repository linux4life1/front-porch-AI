// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// growth_rings on a real (upgraded) library came from the raw v36 DDL with
// `created_at INTEGER NOT NULL DEFAULT 0`. addRing never wrote the column,
// so every ring on every upgraded install read 1970. These tests build the
// table through that exact DDL — the in-memory createAll path hides the bug.

import 'package:drift/drift.dart' show Migrator;
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/growth_store.dart';

const _v36Ddl = '''
  CREATE TABLE growth_rings (
    id TEXT NOT NULL PRIMARY KEY,
    session_id TEXT NOT NULL,
    character_id TEXT NOT NULL,
    content TEXT NOT NULL,
    category TEXT NOT NULL DEFAULT 'trait',
    strength REAL NOT NULL DEFAULT 0.3,
    pinned INTEGER NOT NULL DEFAULT 0,
    retired INTEGER NOT NULL DEFAULT 0,
    source_message_ids TEXT,
    created_at INTEGER NOT NULL DEFAULT 0,
    last_reinforced_at INTEGER NOT NULL DEFAULT 0,
    updated_at INTEGER NOT NULL DEFAULT 0,
    metadata TEXT
  )
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(sameIsolate: true);
    await db.customStatement('DROP TABLE IF EXISTS growth_rings');
    await db.customStatement(_v36Ddl);
  });
  tearDown(() async => db.close());

  Future<Map<String, Object?>> ringRow(String where) async =>
      (await db
              .customSelect(
                'SELECT created_at, last_reinforced_at, updated_at '
                'FROM growth_rings WHERE $where',
              )
              .getSingle())
          .data;

  test('addRing on an upgraded table stamps real timestamps', () async {
    final store = GrowthStore(getDb: () => db);
    await store.addRing(
      sessionId: 's1',
      characterId: 'tess',
      content: 'tightens bonds when exhausted',
      category: 'habit',
    );
    final row = await ringRow("character_id = 'tess'");
    expect(row['created_at'] as int, greaterThan(0));
    expect(row['last_reinforced_at'] as int, greaterThan(0));
    expect(row['updated_at'] as int, greaterThan(0));
  });

  test(
    'v54 backfills created_at from the first receipt; re-run is a no-op',
    () async {
      const t = 1790700000; // seconds, as Drift stores DateTime
      await db.customStatement(
        "INSERT INTO messages (id, session_id, position, sender, is_user, "
        "updated_at) VALUES ('m3', 's1', 3, 'Tess', 0, ?)",
        [t],
      );
      await db.customStatement(
        "INSERT INTO growth_rings (id, session_id, character_id, content, "
        "source_message_ids) VALUES ('r1', 's1', 'tess', 'x', '[3,5]')",
      );
      await db.customStatement(
        "INSERT INTO growth_rings (id, session_id, character_id, content, "
        "created_at, last_reinforced_at, updated_at) "
        "VALUES ('r2', 's1', 'tess', 'y', 42, 42, 42)",
      );

      await db.migration.onUpgrade(Migrator(db), 53, db.schemaVersion);

      final r1 = await ringRow("id = 'r1'");
      expect(r1['created_at'], t);
      expect(r1['last_reinforced_at'], t);
      expect(r1['updated_at'], t);
      final r2 = await ringRow("id = 'r2'");
      expect(r2['created_at'], 42, reason: 'only 0 rows are touched');

      await db.migration.onUpgrade(Migrator(db), 53, db.schemaVersion);
      expect((await ringRow("id = 'r1'"))['created_at'], t);
    },
  );

  test('schemaVersion covers the backfill', () {
    expect(db.schemaVersion, greaterThanOrEqualTo(54));
  });
}
