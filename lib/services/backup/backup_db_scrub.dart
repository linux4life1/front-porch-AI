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

import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// Edits a database copy that is not open anywhere else: a backup about to
/// be zipped, or a restored database about to be swapped in. It never runs
/// the app's migrations or touches the file's schema version.
///
/// The web login lives in the database (`web_auth_credentials` holds the
/// password hash, recovery-code hashes and the TOTP seed; `web_auth_sessions`
/// holds signed-in devices). A backup must not carry the seed unless the
/// user asked for secrets, and a restore must not roll this machine's login
/// back or bring a signed-out device back in.
class BackupDbScrub {
  BackupDbScrub._();

  static const String credentials = 'web_auth_credentials';
  static const String sessions = 'web_auth_sessions';

  /// Removes signed-in devices from the copy at [path], and the web login
  /// itself unless [keepLogin]. Deleted rows are overwritten and the file
  /// is vacuumed, so nothing removed can be read back out of free pages.
  static Future<void> forExport(String path, {required bool keepLogin}) =>
      _run(path, (db) {
        db.execute('PRAGMA secure_delete = ON');
        if (_has(db, 'main', sessions)) db.execute('DELETE FROM $sessions');
        if (!keepLogin && _has(db, 'main', credentials)) {
          db.execute('DELETE FROM $credentials');
        }
        db.execute('VACUUM');
      });

  /// Makes the restored database at [restored] keep the web login of the
  /// database at [live] (this machine's), and signs every device out. When
  /// this machine has no login table yet, the backup's login is kept.
  static Future<void> keepMachineLogin(String restored, String live) => _run(
    restored,
    (db) {
      if (_has(db, 'main', sessions)) db.execute('DELETE FROM $sessions');
      if (!File(live).existsSync()) return;
      db.execute('ATTACH DATABASE ? AS live', [live]);
      try {
        if (!_has(db, 'live', credentials) || !_has(db, 'main', credentials)) {
          return;
        }
        final cols = _columns(
          db,
          'main',
        ).where(_columns(db, 'live').contains).map((c) => '"$c"').join(', ');
        db.execute('DELETE FROM main.$credentials');
        if (cols.isNotEmpty) {
          db.execute(
            'INSERT INTO main.$credentials ($cols) '
            'SELECT $cols FROM live.$credentials',
          );
        }
      } finally {
        db.execute('DETACH DATABASE live');
      }
    },
  );

  /// Copies the backup at [from] to [to] and, when it is a SQLite file,
  /// makes it keep [live]'s login, all in one background isolate: the copy
  /// is ready to rename over the live database in one step. Removes [to]
  /// and rethrows on failure.
  static Future<void> stageCopy(String from, String to, String live) =>
      Isolate.run(() async {
        try {
          File(from).copySync(to);
          if (_isSqlite(to)) await keepMachineLogin(to, live);
        } catch (_) {
          final staged = File(to);
          if (staged.existsSync()) staged.deleteSync();
          rethrow;
        }
      });

  static bool _isSqlite(String path) {
    final raf = File(path).openSync();
    try {
      return String.fromCharCodes(raf.readSync(16)) == 'SQLite format 3\u0000';
    } finally {
      raf.closeSync();
    }
  }

  static bool _has(dynamic db, String schema, String table) =>
      (db.select(
                'SELECT 1 FROM $schema.sqlite_master '
                "WHERE type = 'table' AND name = ?",
                [table],
              )
              as List)
          .isNotEmpty;

  static List<String> _columns(dynamic db, String schema) => [
    for (final row in db.select('PRAGMA $schema.table_info($credentials)'))
      '${row['name']}',
  ];

  static Future<void> _run(String path, void Function(dynamic db) body) async {
    final executor = NativeDatabase(
      File(path),
      enableMigrations: false,
      setup: body,
    );
    try {
      await executor.ensureOpen(_NoMigrations());
    } finally {
      await executor.close();
    }
  }
}

class _NoMigrations implements QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails details) =>
      Future.value();
}
