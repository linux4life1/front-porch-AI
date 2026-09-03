// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:drift/drift.dart';
import 'package:front_porch_ai/database/database.dart';

/// Insert a QueryRow into a target table using raw SQL (INSERT OR IGNORE).
Future<void> insertRowFromQuery(
  AppDatabase db,
  String tableName,
  QueryRow row,
) async {
  final data = row.data;
  final columns = data.keys.toList();
  final placeholders = List.filled(columns.length, '?').join(', ');
  final values = columns.map((c) => Variable(data[c])).toList();

  await db.customInsert(
    'INSERT OR IGNORE INTO $tableName (${columns.join(', ')}) VALUES ($placeholders)',
    variables: values,
  );
}
