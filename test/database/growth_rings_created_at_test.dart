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
    // The companion insert names every current column (advance_count since
    // v68), so the raw v36 table has to come up the ladder before addRing
    // can write it — which is the whole point: real installs ARE upgraded.
    await db.migration.onUpgrade(Migrator(db), 53, db.schemaVersion);
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

  test(
    'a later-edited receipt cannot date the ring after its last reinforce',
    () async {
      // messages.updated_at is the last edit. A bulk touch can move it
      // past the ring's last_reinforced_at. created_at must not follow.
      const reinforced = 1790600000;
      const editedLater = 1790800000;
      await db.customStatement(
        "INSERT INTO messages (id, session_id, position, sender, is_user, "
        "updated_at) VALUES ('m3', 's1', 3, 'Tess', 0, ?)",
        [editedLater],
      );
      await db.customStatement(
        "INSERT INTO growth_rings (id, session_id, character_id, content, "
        "source_message_ids, last_reinforced_at) "
        "VALUES ('rLate', 's1', 'tess', 'habit', '[3]', ?)",
        [reinforced],
      );

      await db.migration.onUpgrade(Migrator(db), 53, db.schemaVersion);

      final row = await ringRow("id = 'rLate'");
      expect(row['last_reinforced_at'], reinforced);
      final created = row['created_at'] as int;
      expect(created, greaterThan(0));
      expect(created, lessThanOrEqualTo(reinforced));

      await db.migration.onUpgrade(Migrator(db), 53, db.schemaVersion);
      expect((await ringRow("id = 'rLate'"))['created_at'], created);
    },
  );

  test('a restamped receipt dates the ring at its own earlier time', () async {
    const t = 1790500000;
    const reinforced = 1790700000;
    const restamped = 1790900000;
    await db.customStatement(
      "INSERT INTO messages (id, session_id, position, sender, is_user, "
      "updated_at) VALUES ('m3', 's1', 3, 'Tess', 0, ?)",
      [restamped],
    );
    await db.customStatement(
      "INSERT INTO growth_rings (id, session_id, character_id, content, "
      "source_message_ids, last_reinforced_at, updated_at) "
      "VALUES ('rEarly', 's1', 'tess', 'habit', '[3]', ?, ?)",
      [reinforced, t],
    );

    await db.migration.onUpgrade(Migrator(db), 53, db.schemaVersion);

    final row = await ringRow("id = 'rEarly'");
    expect(row['created_at'], t);
    expect(row['last_reinforced_at'], reinforced);
    expect(row['updated_at'], t);

    await db.migration.onUpgrade(Migrator(db), 53, db.schemaVersion);
    expect((await ringRow("id = 'rEarly'"))['created_at'], t);
  });

  test('a malformed receipt list still lets the library open', () async {
    await db.customStatement(
      "INSERT INTO growth_rings (id, session_id, character_id, content, "
      "source_message_ids) VALUES ('rBad', 's1', 'tess', 'x', 'oops')",
    );
    await db.migration.onUpgrade(Migrator(db), 53, db.schemaVersion);
    final row = await ringRow("id = 'rBad'");
    expect(row['created_at'] as int, greaterThan(0));
  });

  test('v68 adds the bogey columns and the moments queue', () async {
    // setUp built the raw v36 table, so the v68 columns are genuinely absent
    // (the in-memory createAll path would hide that).
    await db.customStatement('DROP TABLE IF EXISTS growth_moments');
    await db.migration.onUpgrade(Migrator(db), 67, 68);

    final cols = await db.customSelect('PRAGMA table_info(growth_rings)').get();
    final names = [for (final c in cols) c.data['name'] as String];
    expect(
      names,
      containsAll(const [
        'advance_count',
        'bogey_pressure',
        'bogey_cooldown',
        'bogey_pending',
        'bogey_delivered',
        'master_declined',
      ]),
    );
    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master "
          "WHERE type = 'table' AND name = 'growth_moments'",
        )
        .get();
    expect(tables, isNotEmpty);

    // Re-running is a no-op, never a crash (the silent-catch contract).
    await db.migration.onUpgrade(Migrator(db), 67, 68);
    expect(
      (await db.customSelect('PRAGMA table_info(growth_rings)').get()).length,
      names.length,
    );
  });

  test(
    'v72 gives growth_state its kit_seen column; an old row reads null',
    () async {
      // growth_state as v69 left it (v36 table + v69's kit_seed_state), with a
      // settled chat in it; climbing from 71 must add kit_seen as null, and a
      // second climb must not add it twice.
      await db.customStatement('DROP TABLE IF EXISTS growth_state');
      await db.customStatement(
        'CREATE TABLE growth_state (session_id TEXT NOT NULL PRIMARY KEY, '
        'cursor INTEGER NOT NULL DEFAULT 0, '
        'kit_seed_state INTEGER NOT NULL DEFAULT 0)',
      );
      await db.customStatement(
        "INSERT INTO growth_state (session_id, kit_seed_state) VALUES ('s1', 1)",
      );
      await db.migration.onUpgrade(Migrator(db), 71, db.schemaVersion);

      final cols = await db
          .customSelect('PRAGMA table_info(growth_state)')
          .get();
      final names = [for (final c in cols) c.data['name'] as String];
      expect(names, contains('kit_seen'));
      final row =
          (await db
                  .customSelect(
                    "SELECT * FROM growth_state WHERE session_id = 's1'",
                  )
                  .getSingle())
              .data;
      expect(row['kit_seen'], isNull);
      expect(row['kit_seed_state'], 1);

      await db.migration.onUpgrade(Migrator(db), 71, db.schemaVersion);
      expect(
        (await db.customSelect('PRAGMA table_info(growth_state)').get()).length,
        names.length,
      );
    },
  );

  test('v71 gives a v68 moments queue its milestone columns', () async {
    // Rebuild growth_moments in its exact v68 shape (the ladder's own DDL),
    // then climb from 70: status/payload/shown_at must arrive, and a row
    // written before them reads as a pending, never-shown moment.
    await db.customStatement('DROP TABLE IF EXISTS growth_moments');
    await db.migration.onUpgrade(Migrator(db), 67, 68);
    await db.customStatement(
      "INSERT INTO growth_moments (id, session_id, character_id, kind) "
      "VALUES ('m1', 's1', 'tess', 'new_boon')",
    );
    await db.migration.onUpgrade(Migrator(db), 70, db.schemaVersion);

    final cols = await db
        .customSelect('PRAGMA table_info(growth_moments)')
        .get();
    final names = [for (final c in cols) c.data['name'] as String];
    expect(names, containsAll(const ['status', 'payload', 'shown_at']));
    final row =
        (await db
                .customSelect("SELECT * FROM growth_moments WHERE id = 'm1'")
                .getSingle())
            .data;
    expect(row['status'], 'pending');
    expect(row['shown_at'], isNull);

    await db.migration.onUpgrade(Migrator(db), 70, db.schemaVersion);
    expect(
      (await db.customSelect('PRAGMA table_info(growth_moments)').get()).length,
      names.length,
    );
  });
}
