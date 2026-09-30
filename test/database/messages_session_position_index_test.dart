// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Opening a long chat pages messages with
// `session_id = ? AND position < ? ORDER BY position DESC`.
// That plan scanned every blob in the library until this index existed.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting());
  tearDown(() async => db.close());

  test(
    'repair builds the session position index after it is dropped',
    () async {
      await db.customStatement(
        'DROP INDEX IF EXISTS messages_session_position',
      );
      await db.ensureSchemaIsRepaired();
      final rows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND name = 'messages_session_position'",
          )
          .get();
      expect(rows, hasLength(1));
    },
  );
}
