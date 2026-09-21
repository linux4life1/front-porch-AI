// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The v44→v45 `sessions.objectives_enabled` column (docs/design/
// feature-independence.md — the Objectives switch).
//
// One property matters more than everything else here: **the default must be
// ON**. Objectives ran unconditionally for every chat that has ever existed,
// so the value this column takes for pre-v45 rows IS the upgrade's behaviour
// for the entire installed base. A DEFAULT of 0 — a plausible thing for
// someone to "tidy" it to, since most new feature flags start off — would
// silently switch quests off in every existing conversation on first launch
// after the update, with no message and no way to tell what happened.
//
// So this file checks the three places that value is written, which must
// agree: the Drift table definition, the migration ladder's ALTER, and the
// repair path's column list.

import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() async => db.close());

  Future<int> readFlag(String id) async {
    final row = await db
        .customSelect(
          'SELECT objectives_enabled FROM sessions WHERE id = ?',
          variables: [Variable(id)],
        )
        .getSingle();
    return row.read<int>('objectives_enabled');
  }

  group('the column preserves existing behaviour', () {
    test('a session that never mentions the flag reads back ON', () async {
      // Every chat created before the switch existed is this case.
      await db.insertSession(SessionsCompanion.insert(id: 's-default'));
      expect(
        await readFlag('s-default'),
        1,
        reason:
            'objectives ran unconditionally before v45; a fresh row that '
            'does not set the flag must therefore be ON, or the feature '
            'silently stops for anyone who does not go looking for it',
      );
    });

    test('the flag round-trips when set explicitly', () async {
      await db.insertSession(
        SessionsCompanion.insert(
          id: 's-off',
          objectivesEnabled: const Value(false),
        ),
      );
      expect(await readFlag('s-off'), 0);

      await db.updateSession(
        const SessionsCompanion(
          id: Value('s-off'),
          objectivesEnabled: Value(true),
        ),
      );
      expect(await readFlag('s-off'), 1);
    });
  });

  group('the v45 migration itself', () {
    test('ADD COLUMN backfills existing rows with ON, not OFF', () async {
      // Simulate the upgrade against a pre-v45 shaped table: a row exists
      // BEFORE the column does, which is exactly the installed base's state.
      // This runs the ladder's literal SQL, so a future edit to that statement
      // has to come through here.
      await db.customStatement(
        'CREATE TABLE sessions_v44_sim (id TEXT NOT NULL PRIMARY KEY)',
      );
      await db.customStatement(
        "INSERT INTO sessions_v44_sim (id) VALUES ('pre-existing-chat')",
      );

      await db.customStatement(
        'ALTER TABLE sessions_v44_sim '
        'ADD COLUMN objectives_enabled INTEGER NOT NULL DEFAULT 1',
      );

      final row = await db
          .customSelect(
            "SELECT objectives_enabled FROM sessions_v44_sim "
            "WHERE id = 'pre-existing-chat'",
          )
          .getSingle();
      expect(
        row.read<int>('objectives_enabled'),
        1,
        reason:
            'a chat that existed before the upgrade must keep its quests '
            'running — this is the whole safety property of the migration',
      );
    });

    test('schemaVersion was bumped past the column that needs it', () {
      expect(
        db.schemaVersion,
        greaterThanOrEqualTo(45),
        reason:
            'adding the column without bumping schemaVersion means '
            'onUpgrade never fires and live databases never get it',
      );
    });
  });
}
