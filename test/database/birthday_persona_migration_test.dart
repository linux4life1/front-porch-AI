// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// v49→v50 personas.birthday. NULL for every persona that predates the column.

import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() async => db.close());

  test('a persona that never mentions birthday reads back NULL', () async {
    await db.insertPersona(PersonasCompanion.insert(id: 'p-old'));
    final row = await db
        .customSelect(
          'SELECT birthday FROM personas WHERE id = ?',
          variables: [Variable('p-old')],
        )
        .getSingle();
    expect(row.read<String?>('birthday'), isNull);
  });

  test('a set birthday round-trips', () async {
    await db.insertPersona(
      PersonasCompanion.insert(
        id: 'p-yes',
        birthday: const Value('1998-03-15'),
      ),
    );
    final loaded = await db.getAllPersonas();
    final p = loaded.singleWhere((e) => e.id == 'p-yes');
    expect(p.birthday, '1998-03-15');
  });
}
