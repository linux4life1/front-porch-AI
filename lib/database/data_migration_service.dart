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

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';

part 'data_migration_service.imports.dart';
part 'data_migration_service.cleanup.dart';

/// Handles one-time migration of existing JSON files & SharedPreferences
/// data into the Drift SQLite database.
class DataMigrationService {
  final AppDatabase _db;

  /// Absolute paths of legacy files this run could NOT import.
  ///
  /// Every per-item import swallows its exception and moves on, and the
  /// cleanup that follows used to delete every legacy `.json` it could find —
  /// so one malformed chat file was logged to a console the user never sees
  /// and then deleted from disk, having never reached the database. Migration
  /// is also marked complete before the cleanup, so there is no second
  /// attempt: whatever is deleted here is gone for good. Anything recorded in
  /// this set is therefore kept on disk, which is the only copy left.
  final Set<String> _unimportedFiles = <String>{};

  DataMigrationService(this._db);

  /// Returns true if migration has already been completed.
  static Future<bool> isMigrated() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('db_migration_complete') ?? false;
  }

  /// Mark migration as complete so it never runs again.
  static Future<void> _markComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('db_migration_complete', true);
  }

  /// Persisted copy of [_unimportedFiles].
  ///
  /// [cleanupLegacyFiles] is ALSO called with no arguments on every launch
  /// (main.dart), long after this object is gone. Without a durable skip list
  /// that second call would delete on launch 2 exactly the files migration
  /// spared on launch 1, which is the same data loss by a slower route.
  static const String _unimportedPrefsKey = 'db_migration_unimported_files';

  /// Run the full migration. Reports progress via [onProgress].
  /// Format: (step description, current, total)
  Future<void> migrate({
    void Function(String step, int current, int total)? onProgress,
  }) async {
    if (await isMigrated()) return;

    const totalSteps = 6;
    int step = 0;

    // 1. Migrate characters
    onProgress?.call('Importing characters...', ++step, totalSteps);
    await _migrateCharacters();

    // 2. Migrate chat sessions
    onProgress?.call('Importing chat history...', ++step, totalSteps);
    await _migrateChatSessions();

    // 3. Migrate group chats
    onProgress?.call('Importing group chats...', ++step, totalSteps);
    await _migrateGroupChats();

    // 4. Migrate worlds
    onProgress?.call('Importing worlds...', ++step, totalSteps);
    await _migrateWorlds();

    // 5. Migrate folders
    onProgress?.call('Importing folders...', ++step, totalSteps);
    await _migrateFolders();

    // 6. Migrate user personas
    onProgress?.call('Importing personas...', ++step, totalSteps);
    await _migratePersonas();

    await _markComplete();

    // Clean up old JSON files now that data lives in the DB — except the ones
    // that never made it in. Deleting those would destroy the only copy.
    onProgress?.call('Cleaning up old files...', totalSteps, totalSteps);
    if (_unimportedFiles.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_unimportedPrefsKey, _unimportedFiles.toList());
    }
    await cleanupLegacyFiles(preserve: _unimportedFiles);

    if (_unimportedFiles.isNotEmpty) {
      debugPrint(
        'DB_MIGRATION: ${_unimportedFiles.length} legacy file(s) could not be '
        'imported and were LEFT ON DISK (not deleted): '
        '${_unimportedFiles.join(', ')}',
      );
    }
    debugPrint('DB_MIGRATION: Migration complete!');
  }

  static Future<void> cleanupLegacyFiles({
    Set<String> preserve = const <String>{},
  }) => _cleanupLegacyFilesImpl(preserve: preserve);
}
