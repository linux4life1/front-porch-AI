// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The always-on schema repair is the ONLY remedy for a migration ALTER that
// failed and was swallowed (`try { ALTER ... } catch (_) {}` — the ladder is
// byte-verbatim, so those catches cannot be removed). A column that is on the
// ladder but missing from the repair list is therefore unrecoverable: Drift
// names it in the generated SELECT, so the chat load throws "no such column"
// forever. That has already happened twice in this codebase (message_embeddings
// memory_type, and the story-clock/worlds_initialized set).
//
// This pins the invariant mechanically rather than by naming today's columns:
// every column an ALTER adds to a table the repair covers must be in the
// repair's list, unless the live schema no longer has that column at all
// (sessions.relationship_enabled was added in v14 and later removed).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';

/// Extracts the `kSchemaRepairColumns` map literal as {table: {column names}}.
/// (Moved out of database.repair.dart into schema_repair_columns.dart with
/// schema v62, to keep the repair file under the 500-line limit; same list.)
Map<String, Set<String>> _parseRepairList(String source) {
  final start = source.indexOf('kSchemaRepairColumns = {');
  expect(
    start,
    greaterThan(0),
    reason: 'kSchemaRepairColumns literal not found',
  );
  var depth = 0;
  var end = start;
  for (var i = source.indexOf('{', start); i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) {
        end = i;
        break;
      }
    }
  }
  final block = source.substring(start, end);
  final tableLine = RegExp(r"^\s*'(\w+)':\s*\[");
  // A line may carry several entries ('origin TEXT', 'status TEXT', …).
  final colEntry = RegExp("['\"]([a-z_]+) [A-Z]");
  final out = <String, Set<String>>{};
  String? current;
  for (final line in block.split('\n')) {
    final t = tableLine.firstMatch(line);
    if (t != null) {
      current = t.group(1);
      out[current!] = <String>{};
      continue;
    }
    if (current == null) continue;
    for (final c in colEntry.allMatches(line)) {
      out[current]!.add(c.group(1)!);
    }
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'every ladder-added column of a repaired table is in the repair list',
    () async {
      // Every ladder part, not a fixed list: the ladder has been split across
      // database.migrations.*.dart files and a pinned pair silently skipped
      // the early/mid/late steps.
      final ladderFiles = Directory('lib/database')
          .listSync()
          .whereType<File>()
          .where(
            (f) =>
                RegExp(r'database\.migrations(\.\w+)?\.dart$').hasMatch(f.path),
          )
          .toList();
      expect(ladderFiles.length, greaterThan(1));
      final ladder = [
        for (final f in ladderFiles) await f.readAsString(),
      ].join('\n');
      final repairSource = await File(
        'lib/database/schema_repair_columns.dart',
      ).readAsString();

      final repaired = _parseRepairList(repairSource);
      expect(repaired.keys, contains('sessions'));
      expect(repaired.keys, contains('characters'));

      // The live schema, straight from Drift — not a second text parse.
      final db = AppDatabase.forTesting();
      final live = <String, Set<String>>{
        for (final t in db.allTables)
          t.actualTableName: t.$columns.map((c) => c.name).toSet(),
      };
      await db.close();

      final missing = <String>[];
      for (final m in RegExp(
        r'ALTER TABLE (\w+) ADD COLUMN (\w+)',
      ).allMatches(ladder)) {
        final table = m.group(1)!;
        final column = m.group(2)!;
        final covered = repaired[table];
        if (covered == null) continue; // repair does not claim this table
        // The column was dropped from the live schema later.
        if (!(live[table]?.contains(column) ?? false)) continue;
        if (!covered.contains(column)) missing.add('$table.$column');
      }

      expect(
        missing,
        isEmpty,
        reason: 'these columns can never be healed after a swallowed ALTER',
      );
    },
  );
}
