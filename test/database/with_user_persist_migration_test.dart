// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// v48→v49 sessions.with_user. NULL for every chat that predates the column.

import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() async => db.close());

  Future<int?> readBit(String id) async {
    final row = await db
        .customSelect(
          'SELECT with_user FROM sessions WHERE id = ?',
          variables: [Variable(id)],
        )
        .getSingle();
    return row.read<int?>('with_user');
  }

  test('a session that never mentions with_user reads back NULL', () async {
    await db.insertSession(SessionsCompanion.insert(id: 's-old'));
    expect(await readBit('s-old'), isNull);
  });

  test('true and false round-trip; null stays null', () async {
    await db.insertSession(
      SessionsCompanion.insert(id: 's-yes', withUser: const Value(true)),
    );
    await db.insertSession(
      SessionsCompanion.insert(id: 's-no', withUser: const Value(false)),
    );
    expect(await readBit('s-yes'), 1);
    expect(await readBit('s-no'), 0);

    final loaded = await db.getSessionById('s-yes');
    expect(loaded?.withUser, isTrue);
  });
}
