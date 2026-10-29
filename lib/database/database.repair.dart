// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Always-on schema repair + integrity machinery (see _repairMissingSchemaColumns docs).

part of 'database.dart';

/// Always-on schema repair + integrity machinery (see _repairMissingSchemaColumns docs).
extension AppDatabaseMaintenance on AppDatabase {
  /// Run a fast integrity check on the database.
  /// Returns `true` if the database is healthy, `false` if corruption is detected.
  Future<bool> integrityCheck() async {
    try {
      final result = await customSelect('PRAGMA quick_check').get();
      if (result.isNotEmpty && result.first.data.values.first == 'ok') {
        debugPrint('[DB] Integrity check passed');
        return true;
      }
      debugPrint(
        '[DB] Integrity check FAILED: ${result.map((r) => r.data).toList()}',
      );
      return false;
    } catch (e) {
      debugPrint('[DB] Integrity check error: $e');
      return false;
    }
  }

  /// True when this database holds no library content at all — no characters,
  /// no chats, no groups.
  ///
  /// This is the "is this a brand-new install?" question the beta stable-DB
  /// import needs. It used to ask whether the beta `.db` FILE existed, which
  /// can never be false by the time any UI runs: startup opens (and therefore
  /// creates) the database before the first frame. Emptiness is the honest
  /// signal, and it also refuses to offer an import that would overwrite a
  /// beta library the user has already put work into.
  ///
  /// Personas are deliberately not counted — startup seeds a default one, so
  /// a fresh database always has exactly one.
  Future<bool> hasNoUserContent() async {
    try {
      final row = await customSelect(
        'SELECT (SELECT COUNT(*) FROM characters) '
        '+ (SELECT COUNT(*) FROM sessions) '
        '+ (SELECT COUNT(*) FROM groups) AS n',
      ).getSingle();
      return (row.data['n'] as int? ?? 0) == 0;
    } catch (e) {
      // Unreadable counts must not be read as "empty" — that would offer to
      // overwrite a library we simply failed to measure.
      debugPrint('[DB] Could not count library content: $e');
      return false;
    }
  }

  /// Ensures all columns that the current Dart schema and application code expect
  /// are physically present in the database. This is the robust, always-on safety
  /// net for users whose databases predate recent features (group cards, per-character
  /// objectives, expanded Realism/Needs/Chaos columns). It replaces the fragile
  /// pattern of silent `try { ALTER ... } catch (_) {}` inside versioned migration blocks.
  ///
  /// Strategy:
  /// - Uses PRAGMA table_info (fast, reliable even on ancient SQLite files).
  /// - Only ever does ADD COLUMN with exact NOT NULL DEFAULTs that match the Table
  ///   class definitions and the historical ALTER statements.
  /// - On first actual mutation for a given launch, creates a timestamped backup of
  ///   the .db file next to the original so users with years of chats have an
  ///   immediate rollback artifact.
  /// - Failures to add a single column are logged but do not prevent app launch.
  /// - Idempotent and safe to call on every open (including after cloud sync restore).
  ///
  /// This must be kept in sync with any future columns added to Sessions, Groups,
  /// Objectives, Characters, etc. Add the new "COL TYPE [NOT NULL DEFAULT x]" entry
  /// to kSchemaRepairColumns in the same change that adds it to the Table class.
  Future<void> _repairMissingSchemaColumns() async {
    final stopwatch = Stopwatch()..start();
    bool anyRepairDone = false;

    // The columns live in schema_repair_columns.dart (kSchemaRepairColumns).

    for (final entry in kSchemaRepairColumns.entries) {
      final table = entry.key;
      final expectedDefs = entry.value;

      final existing = await _getExistingColumnNames(table);
      if (existing.isEmpty) {
        // Table does not exist in this DB yet. A future onCreate or onUpgrade CREATE
        // TABLE will bring it in with the full modern definition. Nothing to repair.
        continue;
      }

      final missingDefs = <String>[];
      for (final def in expectedDefs) {
        final colName = def.split(' ').first;
        if (!existing.contains(colName)) {
          missingDefs.add(def);
        }
      }

      if (missingDefs.isNotEmpty) {
        if (!anyRepairDone) {
          await _createPreRepairBackup();
          anyRepairDone = true;
        }

        for (final def in missingDefs) {
          final colName = def.split(' ').first;
          try {
            final sql = 'ALTER TABLE $table ADD COLUMN $def';
            await customStatement(sql);
            debugPrint(
              '[DB] Schema repair: added $table.$colName (recovered from incomplete past migration)',
            );
            if (table == 'chat_worlds' && colName == 'is_primary') {
              await _backfillChatWorldsIsPrimary();
            }
          } catch (e) {
            debugPrint(
              '[DB] Schema repair: FAILED to add $table.$colName — $e (app will continue; some features may be limited until manual intervention)',
            );
            // Intentionally not re-thrown. The user's irreplaceable chats must remain accessible.
          }
        }
      }
    }

    stopwatch.stop();
    if (anyRepairDone) {
      debugPrint(
        '[DB] Schema repair completed in ${stopwatch.elapsedMilliseconds}ms — your database is now consistent with app v32+ expectations',
      );
    }

    // ── New table for decoupled group members (clean break, no legacy, no blobs) ──
    // This table + private per-group avatar files (groups/<groupId>/avatars/*.png)
    // replace all previous characterIds + library materialization for groups.
    // Created with IF NOT EXISTS + the backup-on-mutation guard for users on old DBs.
    // Matches the GroupMembers Dart definition (snake_case) + created_at (repair path).
    // Multi-avatar never supported here; only primary avatarFilename per member.
    try {
      final hasMembersTable = await customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='group_members'",
      ).get();
      if (hasMembersTable.isEmpty) {
        if (!anyRepairDone) {
          await _createPreRepairBackup();
          anyRepairDone = true;
        }
        // v33+ contract per the GroupMembers Dart class docs above. Do not
        // assume legacy characterIds behavior here.
        await customStatement('''
          CREATE TABLE IF NOT EXISTS group_members (
            -- v33+ table (GroupMembers Dart docs): strict UUID PKs + private-avatar semantics only. No legacy characterIds.
            id TEXT NOT NULL PRIMARY KEY,
            group_id TEXT NOT NULL,
            name TEXT NOT NULL,
            description TEXT NOT NULL DEFAULT '',
            personality TEXT NOT NULL DEFAULT '',
            scenario TEXT NOT NULL DEFAULT '',
            first_message TEXT NOT NULL DEFAULT '',
            mes_example TEXT NOT NULL DEFAULT '',
            system_prompt TEXT NOT NULL DEFAULT '',
            post_history_instructions TEXT NOT NULL DEFAULT '',
            alternate_greetings TEXT NOT NULL DEFAULT '[]',
            tags TEXT NOT NULL DEFAULT '[]',
            avatar_filename TEXT,
            tts_voice TEXT,
            lorebook TEXT,
            world_names TEXT NOT NULL DEFAULT '[]',
            front_porch_extensions TEXT,
            raw_extensions TEXT,
            member_state TEXT NOT NULL DEFAULT '{}',
            created_at INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL DEFAULT 0
          )
        ''');
        debugPrint(
          '[DB] Schema repair: created group_members table (decoupled group characters; v33+ contract)',
        );
      }
    } catch (e) {
      debugPrint(
        '[DB] Schema repair: FAILED to ensure group_members table — $e (continuing; groups may be limited)',
      );
    }

    // Post-creation lightweight orphan diagnostic (one query, non-fatal, launch-time only).
    try {
      final res = await customSelect(
        'SELECT COUNT(*) as cnt FROM group_members gm LEFT JOIN groups g ON gm.group_id = g.id WHERE g.id IS NULL',
      ).get();
      final cnt = res.isNotEmpty ? (res.first.data['cnt'] as int? ?? 0) : 0;
      if (cnt > 0) {
        debugPrint(
          '[DB] WARNING: $cnt orphaned group_members row(s) with no matching group (pre-v33 DB integrity issue)',
        );
      }
    } catch (_) {}

    if (anyRepairDone) {
      // Re-log if we did table creation after the column phase
      debugPrint(
        '[DB] Schema repair (including new tables) completed in ${stopwatch.elapsedMilliseconds}ms total',
      );
    }
    await _ensureMessageSessionIndex();
  }

  /// Tail and older-page reads are `session_id = ? ORDER BY position`.
  /// Without this index each page scans every message blob in the
  /// library. A long chat then holds the loading cover for minutes.
  Future<void> _ensureMessageSessionIndex() async {
    try {
      final sw = Stopwatch()..start();
      await customStatement(
        'CREATE INDEX IF NOT EXISTS messages_session_position '
        'ON messages (session_id, position)',
      );
      if (sw.elapsedMilliseconds > 50) {
        debugPrint(
          '[DB] messages_session_position ready in '
          '${sw.elapsedMilliseconds}ms',
        );
      }
    } catch (e) {
      debugPrint('[DB] messages_session_position skipped: $e');
    }
  }

  /// Introspects the live physical columns using the SQLite PRAGMA that works
  /// even when Drift's internal schema snapshot is ahead of the on-disk reality.
  Future<Set<String>> _getExistingColumnNames(String tableName) async {
    try {
      final result = await customSelect('PRAGMA table_info($tableName)').get();
      return result
          .map((row) => row.data['name'] as String?)
          .where((name) => name != null && name.isNotEmpty)
          .cast<String>()
          .toSet();
    } catch (e) {
      debugPrint(
        '[DB] Could not PRAGMA table_info for $tableName (table may be very old or locked): $e',
      );
      return <String>{};
    }
  }

  /// Creates a byte-for-byte copy of the current .db file with a timestamped suffix
  /// the first time this launch is about to perform any ALTER. This is the belt-and-
  /// suspenders protection for users who have explicitly stated that DB deletion or
  /// any risk of losing character chat history is unacceptable.
  Future<void> _createPreRepairBackup() async {
    try {
      final path = AppDatabase.dbFilePath;
      if (path == null) return;
      final dbFile = File(path);
      if (!await dbFile.exists()) return;

      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final backupPath = '$path.pre-schema-repair-$ts';
      await dbFile.copy(backupPath);
      debugPrint(
        '[DB] SAFETY BACKUP created before schema repair: $backupPath',
      );
      debugPrint(
        '[DB] If anything ever goes wrong, you can rename this file back to front_porch.db to restore your exact previous state (all chats, objectives, groups, etc.).',
      );
    } catch (e) {
      debugPrint(
        '[DB] Could not create pre-repair backup (non-fatal — repair will still attempt): $e',
      );
    }
  }

  /// Public helper so that direct-open paths (certain test or recovery
  /// scenarios) can explicitly ensure the schema matches before using group or objective
  /// features. The primary AppDatabase.instance() path calls the repair automatically.
  Future<void> ensureSchemaIsRepaired() => _repairMissingSchemaColumns();
}
