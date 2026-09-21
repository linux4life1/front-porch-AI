// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Startup repair must list every column the live app always reads. Story
// clock, worlds_initialized, groups.stable_id, and Living Worlds fields
// were on the migration ladder but missing from repair — an older upgrade
// that missed those ALTERs crashed with "no such column" on chat load.
// Trio: Table definition (Drift read), ladder SQL, repair list.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting());
  tearDown(() async => db.close());

  test(
    'fresh DB can read story clock + worlds_initialized + group stable_id',
    () async {
      await db.insertSession(SessionsCompanion.insert(id: 's-clock'));
      final session = await (db.select(
        db.sessions,
      )..where((s) => s.id.equals('s-clock'))).getSingle();
      expect(session.storyClock, isNull);
      expect(session.storyStartDate, isNull);
      expect(session.worldsInitialized, isFalse);

      await db.insertGroup(GroupsCompanion.insert(id: 'g1', name: 'Cast'));
      final group = await (db.select(
        db.groups,
      )..where((g) => g.id.equals('g1'))).getSingle();
      expect(group.stableId, isNull);
    },
  );

  test('schemaVersion covers the columns that need it', () {
    expect(db.schemaVersion, greaterThanOrEqualTo(43));
  });
}
