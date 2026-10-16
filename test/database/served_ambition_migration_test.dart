// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// The v45→v46 `objectives.served_ambition` column
// (docs/design/pockets-and-preferences.md Part 3 — Ambition → Objectives →
// Tasks).
//
// The property that matters here is the opposite of v45's. There the default
// had to be ON, because objectives had always run. Here the value for every
// pre-existing row must be **NULL**, because "which ambition does this quest
// serve" has no honest answer for a quest proposed before ambitions steered
// anything. A backfill — even a clever one matching text — would put a
// confident "→ open her own bakery" chip under quests the character never
// took for that reason, and the user has no way to tell it was invented.
//
// So this checks the three places that value is written and which must agree:
// the Drift table definition, the migration ladder's ALTER, and the repair
// path's column list. Same trio v45 pinned; they have drifted before.

import 'package:drift/drift.dart' show Migrator, Value, Variable;
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() async => db.close());

  Future<String?> readServed(String id) async {
    final row = await db
        .customSelect(
          'SELECT served_ambition FROM objectives WHERE id = ?',
          variables: [Variable(id)],
        )
        .getSingle();
    return row.read<String?>('served_ambition');
  }

  Future<void> insert(
    String id, {
    Value<String?> served = const Value.absent(),
  }) => db.insertObjective(
    ObjectivesCompanion.insert(
      id: id,
      characterId: 'Jennifer_1782587668376',
      objective: 'Bake something worth selling',
      servedAmbition: served,
    ),
  );

  group('NULL is the answer for anything that predates the column', () {
    test(
      'an objective that never mentions the field reads back NULL',
      () async {
        await insert('o-untagged');
        expect(
          await readServed('o-untagged'),
          isNull,
          reason:
              'every objective in every existing library is this case — a '
              'non-null default here would claim each of them serves whatever '
              'that default named',
        );
      },
    );

    test(
      'the column is genuinely nullable, not empty-string-defaulted',
      () async {
        await insert('o-null-explicit', served: const Value(null));
        expect(
          await readServed('o-null-explicit'),
          isNull,
          reason:
              "'' and NULL must not be conflated: the UI shows a chip when "
              'this is non-null, and an empty chip is worse than no chip',
        );
      },
    );
  });

  group('the tag round-trips when the proposal set one', () {
    test('stores and returns the ambition TEXT verbatim', () async {
      await insert('o-tagged', served: const Value('open her own bakery'));
      expect(await readServed('o-tagged'), 'open her own bakery');
    });

    test('the generated row exposes it as a nullable String', () async {
      await insert(
        'o-tagged2',
        served: const Value('reconcile with her sister'),
      );
      final objs = await db.getObjectivesForCharacter('Jennifer_1782587668376');
      final row = objs.firstWhere((o) => o.id == 'o-tagged2');
      expect(
        row.servedAmbition,
        'reconcile with her sister',
        reason:
            'this is the field AmbitionService reads to skip re-asking '
            'which ambition a completed quest belonged to',
      );
    });
  });

  // 2026-10-16, objectives that keep up (v58). Old libraries have the v8
  // objectives table: created_at DEFAULT 0 and no origin column. The upgrade
  // must say who each existing goal came from, and every new goal must get a
  // real creation time, or "how long since this goal began" reads 1970.
  group('v58 on an old library', () {
    late AppDatabase old;

    setUp(() async {
      old = AppDatabase.forTesting(sameIsolate: true);
      await old.customStatement('DROP TABLE objectives');
      await old.customStatement(
        'CREATE TABLE objectives (id TEXT NOT NULL, '
        'character_id TEXT NOT NULL, chat_id TEXT, objective TEXT NOT NULL, '
        "tasks TEXT NOT NULL DEFAULT '[]', active INTEGER NOT NULL DEFAULT 1, "
        'is_primary INTEGER NOT NULL DEFAULT 0, '
        'check_frequency INTEGER NOT NULL DEFAULT 3, '
        'injection_depth INTEGER NOT NULL DEFAULT 4, served_ambition TEXT, '
        'created_at INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (id))',
      );
    });
    tearDown(() async => old.close());

    test('origin is backfilled from served ambition', () async {
      await old.customStatement(
        'INSERT INTO objectives (id, character_id, objective, served_ambition) '
        "VALUES ('mine', 'c', 'bake bread', 'open a bakery'), "
        "('yours', 'c', 'find the key', NULL)",
      );
      await old.migration.onUpgrade(Migrator(old), 57, old.schemaVersion);
      final rows = {
        for (final o in await old.getObjectivesForCharacter('c')) o.id: o,
      };
      expect(rows['mine']!.origin, 'character');
      expect(rows['yours']!.origin, 'user');
      expect(rows['yours']!.status, isNull, reason: 'still open, not ended');
    });

    test('a goal made after the upgrade gets a real creation time', () async {
      await old.migration.onUpgrade(Migrator(old), 57, old.schemaVersion);
      await old.insertObjective(
        ObjectivesCompanion.insert(
          id: 'new',
          characterId: 'c',
          objective: 'mend the porch',
        ),
      );
      final row = (await old.getObjectivesForCharacter('c')).single;
      expect(row.createdAt.year, greaterThan(2000));
    });
  });
}
