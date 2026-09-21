// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// v50→v51 worlds.climate_enabled. Default MUST be ON: every existing
// world already had climate/weather/atmosphere. A DEFAULT of 0 would
// silently unplug the weather machine for the whole installed library.

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
          'SELECT climate_enabled FROM worlds WHERE id = ?',
          variables: [Variable(id)],
        )
        .getSingle();
    return row.read<int>('climate_enabled');
  }

  group('the column preserves existing behaviour', () {
    test('a world that never mentions the flag reads back ON', () async {
      await db.insertWorld(
        WorldsCompanion.insert(id: 'w-default', name: 'Old Place'),
      );
      expect(
        await readFlag('w-default'),
        1,
        reason:
            'existing worlds had climate; a fresh row that does not '
            'set the flag must stay ON or every place loses weather',
      );
    });

    test('the flag round-trips when set explicitly off', () async {
      await db.insertWorld(
        WorldsCompanion.insert(
          id: 'w-off',
          name: 'Soul Society',
          climateEnabled: const Value(false),
        ),
      );
      expect(await readFlag('w-off'), 0);

      await db.updateWorld(
        const WorldsCompanion(
          id: Value('w-off'),
          name: Value('Soul Society'),
          climateEnabled: Value(true),
        ),
      );
      expect(await readFlag('w-off'), 1);
    });
  });

  group('the v51 migration itself', () {
    test('ADD COLUMN backfills existing rows with ON, not OFF', () async {
      await db.customStatement(
        'CREATE TABLE worlds_v50_sim (id TEXT NOT NULL PRIMARY KEY, '
        'name TEXT NOT NULL)',
      );
      await db.customStatement(
        "INSERT INTO worlds_v50_sim (id, name) VALUES ('pre-existing-place', 'Mars')",
      );
      await db.customStatement(
        'ALTER TABLE worlds_v50_sim '
        'ADD COLUMN climate_enabled INTEGER NOT NULL DEFAULT 1',
      );
      final row = await db
          .customSelect(
            "SELECT climate_enabled FROM worlds_v50_sim "
            "WHERE id = 'pre-existing-place'",
          )
          .getSingle();
      expect(
        row.read<int>('climate_enabled'),
        1,
        reason: 'a world that existed before the upgrade must keep climate',
      );
    });

    test('schemaVersion was bumped past the column that needs it', () {
      expect(
        db.schemaVersion,
        greaterThanOrEqualTo(51),
        reason:
            'adding the column without bumping schemaVersion means '
            'onUpgrade never fires and live databases never get it',
      );
    });
  });
}
