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

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/database/session_gen_overrides_heal.dart';
import 'package:front_porch_ai/services/db_reunification_service.dart';

part 'database.g.dart'; part 'context_budget_db.dart';
part 'database.tables.core.dart';
part 'database.tables.features.dart';
part 'database.repair.dart';
part 'database.migrations.dart';
part 'database.migrations.data.dart';
part 'database.queries.library.dart';
part 'database.queries.chat.dart';
part 'database.queries.groups.dart';
part 'database.queries.worlds.dart';
part 'database.queries.memory.dart';
const _uuid = Uuid();

// ── Database Definition ─────────────────────────────────────────────────

@DriftDatabase(
  tables: [
    Characters,
    Sessions,
    Messages,
    Groups,
    Folders,
    Personas,
    Worlds,
    ChatWorlds, // v40 — Living Worlds: per-chat world attachments
    ChatBiomeSpans, // v40 — Living Worlds: biome changeover spans
    MessageEmbeddings,
    DataBankEntries,
    JournalMemories, // v35 — The Journal: per-chat, per-character memory cards
    GrowthRings, // v36 — Growth Rings: per-chat, per-character growth entries
    GrowthState, // v36 — Growth Rings: per-session pass cursor
    Objectives,
    StoryProjects,
    SyncMeta,
    AvatarImages,
    GroupMembers, // group-owned characters (clean break from library; see class docs)
    WebAuthCredentials, // v33 — web secure-login account
    WebAuthSessions, // v33 — persisted web-login sessions
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase._internal(super.e);

  static AppDatabase? _instance;
  static String? _dbPath;
  static String? _dbDir;

  /// The database that is open *right now*, or null before startup finished.
  ///
  /// Three flows swap the file out from under a running app — importing a
  /// stable DB, moving the storage root, and restoring a backup — and each one
  /// replaces [_instance] with a brand-new object. Anything that captured the
  /// old one (notably `Provider<AppDatabase>.value`, which is a startup
  /// snapshot) is holding a closed database whose next query throws. Read
  /// through [liveDatabase] rather than a captured reference.
  static AppDatabase? get current => _instance;

  /// Singleton access. Call [AppDatabase.instance()] to get the shared database.
  ///
  /// Pre-release builds (alpha/beta/rc/dev) automatically use a separate
  /// `front_porch_beta.db` to protect the production database from schema
  /// changes that may be incompatible with the stable release.
  static Future<AppDatabase> instance() async {
    if (_instance != null) return _instance!;
    final prefs = await SharedPreferences.getInstance();
    // Mirror StorageService: use a separate prefs key for beta builds so the
    // beta DB path never overwrites the stable user's custom root path.
    final rootPathKey = isPreRelease ? 'root_path_beta' : 'root_path';
    final rootPath = prefs.getString(rootPathKey);
    final defaultRootName = isPreRelease ? 'FrontPorchAI-Beta' : 'FrontPorchAI';
    final basePath =
        rootPath ??
        p.join(
          (await getApplicationDocumentsDirectory()).path,
          defaultRootName,
        );
    final dbDir = p.join(basePath, 'KoboldManager');
    _dbDir = dbDir;

    // Choose database filename based on release type
    final dbName = isPreRelease ? 'front_porch_beta.db' : 'front_porch.db';
    final file = File(p.join(dbDir, dbName));
    await file.parent.create(recursive: true);

    // For pre-release: if no beta DB exists yet, copy the production DB
    // so users get all their data without modifying the stable database.
    // The copy is gated by the import dialog — it only happens after the
    // user has seen the dialog and chosen Import (or skipped the dialog
    // entirely for non-pre-release builds).
    // Best-effort: a failed copy (disk full, permissions, a second instance
    // holding the file) must NOT abort startup with no window — fall through
    // and open whatever DB exists; the import dialog can retry the copy later.
    if (isPreRelease && !file.existsSync()) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final shown = prefs.getBool('beta_stable_import_shown') ?? false;
        if (shown) {
          // Dialog has been shown — respect the user's choice
          final skipped = prefs.getBool('beta_stable_import_skipped') ?? false;
          if (!skipped) {
            final prodFile = File(p.join(dbDir, 'front_porch.db'));
            if (prodFile.existsSync()) {
              debugPrint(
                '[DB] Pre-release build — copying production DB to beta DB',
              );
              await prodFile.copy(file.path);
            }
          }
        } else {
          // Dialog not yet shown — defer to the import dialog which will
          // show after the first frame and trigger the copy manually.
          debugPrint(
            '[DB] Pre-release build — import dialog pending, skipping copy',
          );
        }
      } catch (e) {
        debugPrint('[DB] Beta DB seed copy failed (non-fatal): $e');
      }
    }

    // For stable builds: reunify beta DB into production if both exist.
    // This is a one-time operation on the first 0.9.0 stable launch.
    // Steps 1-2 run here (backup + promote). Steps 3-5 (diff + import)
    // run later in main.dart with a UI overlay. Guarded: a reunification I/O
    // failure must not brick launch — retry next start on whatever DB opens.
    try {
      if (!isPreRelease &&
          await DbReunificationService.needsReunification(dbDir)) {
        debugPrint(
          '[DB] Reunification needed — backing up and promoting beta DB',
        );
        await DbReunificationService.createBackups(dbDir);
        await DbReunificationService.promoteBetaDb(dbDir);
      }
    } catch (e) {
      debugPrint('[DB] Reunification failed (non-fatal, will retry): $e');
    }

    _dbPath = file.path;
    _instance = AppDatabase._internal(
      NativeDatabase.createInBackground(
        file,
        setup: (db) {
          db.execute('PRAGMA synchronous = FULL');
          debugPrint('[DB] PRAGMA synchronous = FULL set');
        },
      ),
    );

    // Robust, always-on schema repair for long-lived user databases.
    // Any previous schemaVersion onUpgrade block that used bare `try { ALTER } catch (_) {}`
    // could leave the physical DB permanently behind the Dart Table definitions (e.g. the
    // v29 `chat_id` on objectives, or v30-v32 group columns). This repair uses PRAGMA
    // table_info introspection + conditional ADD COLUMN only. It creates a timestamped
    // .db backup the first time it actually mutates schema, then guarantees the columns
    // the rest of the app (group chat, per-character objectives, Realism/Needs, Chaos)
    // now unconditionally reference. Never deletes or mutates user rows. Safe and cheap
    // to run on every normal launch.
    await _instance!._repairMissingSchemaColumns();

    return _instance!;
  }

  /// The absolute path to the database file on disk.
  static String? get dbFilePath => _dbPath;

  /// The directory containing the database files.
  static String? get dbDirPath => _dbDir;

  /// Close the database and clear the singleton so the next call to
  /// [instance()] will open a fresh connection to the file on disk.
  /// Used after cloud sync downloads a new .db file.
  static Future<void> closeAndReset() async {
    if (_instance != null) {
      await _instance!.close();
      _instance = null;
    }
  }

  /// Insert a character and return its UUID (convenience for callers that need the ID).
  ///
  /// Kept as a genuine instance method on [AppDatabase] rather than moving into
  /// `AppDatabaseLibraryQueries` with the rest of the character queries
  /// (database.queries.library.dart, split 2026-08-06): an existing test,
  /// `test/ui/avatar_creation/avatar_creation_controller_test.dart`, imports
  /// this file as `show AppDatabase, CharactersCompanion`, and Dart's `show`
  /// combinator only admits the named top-level declarations — extension
  /// members are invisible unless the extension's own name is also shown.
  /// Editing that test's import is off-limits for this split, so this one
  /// method stays a class member (every other caller, e.g.
  /// `character_repository.crud.dart`/`character_repository.import.dart` and
  /// the rest of the test suite, imports the library without a `show` clause
  /// and is unaffected either way).
  Future<String> insertCharacterReturningId(
    CharactersCompanion character,
  ) async {
    final id = character.id.present ? character.id.value : _uuid.v4();
    character = character.copyWith(id: Value(id));
    await into(characters).insert(character);
    await bumpSyncVersion();
    return id;
  }

  /// For testing: create a temporary database backed by a real file.
  /// Uses a system temp directory so the background isolate can access it.
  ///
  /// [sameIsolate] runs SQLite on the calling isolate (in-memory) instead of
  /// the background one. Required inside `testWidgets`: the fake-async test
  /// zone never yields to the real event loop, so a cross-isolate database
  /// response can never be delivered and the first awaited query deadlocks
  /// the whole run at 0% CPU. Plain `test()` bodies keep the default.
  factory AppDatabase.forTesting({bool sameIsolate = false}) {
    if (sameIsolate) {
      return AppDatabase._internal(NativeDatabase.memory());
    }
    final tmpDir = Directory.systemTemp.createTempSync('fpai_test_');
    final file = File('${tmpDir.path}/test.db');
    return AppDatabase._internal(
      NativeDatabase.createInBackground(
        file,
        setup: (db) => db.execute('PRAGMA synchronous = FULL'),
      ),
    );
  }

  /// Open a specific DB file for reunification (runs migrations, not a singleton).
  factory AppDatabase.forReunification(File file) {
    return AppDatabase._internal(
      NativeDatabase.createInBackground(
        file,
        setup: (db) => db.execute('PRAGMA synchronous = FULL'),
      ),
    );
  }

  @override
  int get schemaVersion => 48;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) => _onCreateMigration(m),
    onUpgrade: (Migrator m, int from, int to) => _onUpgradeMigration(m, from, to),
  );
}
