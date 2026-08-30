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
  /// here in the same change that adds it to the Table class.
  Future<void> _repairMissingSchemaColumns() async {
    final stopwatch = Stopwatch()..start();
    bool anyRepairDone = false;

    // Physical table -> list of "col_name TYPE [NOT NULL DEFAULT 'lit']" fragments.
    // These are the columns that were added (or re-added) via the old
    // silent-catch ALTERs in onUpgrade — v5 onward, not just the v9-v32 window
    // this comment used to name; the v5/v6/v10/v12-v19/v24 columns are on the
    // same fragile pattern and are listed below for exactly that reason.
    // The presence of these in the list is what guarantees 1:1 + group chat parity
    // features will not produce "no such column" on real user databases.
    const Map<String, List<String>> columnsToEnsure = {
      'characters': [
        // Every one of these was added by a bare `try { ALTER } catch (_) {}`
        // in the ladder, so a failure (disk full, DB locked by a second
        // instance) leaves the column permanently absent — and Drift's
        // generated SELECT for `characters` names them all, so the library
        // then throws "no such column" on every read with no way back.
        "memory_sources TEXT NOT NULL DEFAULT '[]'", // v5
        "evolved_personality TEXT NOT NULL DEFAULT ''", // v10
        "evolved_scenario TEXT NOT NULL DEFAULT ''", // v10
        'evolution_count INTEGER NOT NULL DEFAULT 0', // v10
        'prime_avatar_index INTEGER NOT NULL DEFAULT 1', // v24
      ],
      'messages': [
        // v14 — same silent-catch pattern. Without these the whole transcript
        // is unreadable, not merely un-annotated.
        'metadata TEXT',
        'swipe_metadata TEXT',
      ],
      'personas': [
        // v6. Dormant since the Journal replaced auto-persona, but Drift still
        // names it in every personas SELECT.
        "learned_facts TEXT NOT NULL DEFAULT '[]'",
        // v3 (the UUID rebuild). Epoch 0 rather than "now" because SQLite
        // rejects a non-constant DEFAULT in ALTER TABLE ADD COLUMN; a 1970
        // timestamp on a row that would otherwise be unreadable is the better
        // of the two outcomes.
        'updated_at INTEGER NOT NULL DEFAULT 0',
        'deleted_at INTEGER',
        // v50 — calendar birthday. NULL = unset.
        'birthday TEXT',
      ],
      'objectives': [
        'chat_id TEXT', // v29 — the one that was actively crashing group objective loads
        'is_primary INTEGER NOT NULL DEFAULT 1', // v20
        'injection_depth INTEGER NOT NULL DEFAULT 4', // safety (was in v8 CREATE + v9 ALTER)
        // v46 — must match the Table definition and the ladder exactly:
        // nullable, no default. NULL means "this quest serves no ambition",
        // which is a real answer and the only honest one for every objective
        // that predates the column.
        'served_ambition TEXT',
      ],
      'message_embeddings': [
        // Added to the MessageEmbeddings Table class during the Journal work
        // WITHOUT a migration: the only CREATE TABLE for this table is the
        // v4→v5 one above, which predates both columns, and no ALTER ever adds
        // them. Fresh installs get them from onCreate's createAll(), so the
        // gap is invisible on any recently-created database — but a library
        // that has simply been upgraded since before the Journal landed has
        // neither column, and Drift's generated SELECT names them, so every
        // RAG read throws "no such column: memory_type". Both are dormant, so
        // the defaults below match the Table class exactly and change nothing
        // for databases that already have them.
        "memory_type TEXT NOT NULL DEFAULT 'message'",
        'metadata TEXT',
      ],
      'groups': [
        // v30
        'default_member_realism_state TEXT NOT NULL DEFAULT "{}"',
        // v31 — the full set of explicit typed columns for Group Card roundtrip + Chaos + lore scoping
        'chaos_mode_enabled INTEGER NOT NULL DEFAULT 0',
        'chaos_nsfw_enabled INTEGER NOT NULL DEFAULT 0',
        "group_lorebook TEXT NOT NULL DEFAULT ''",
        "world_ids TEXT NOT NULL DEFAULT '[]'",
        'inherit_character_lorebooks INTEGER NOT NULL DEFAULT 1',
        'baseline_realism_state TEXT NOT NULL DEFAULT "{}"',
        // v32 — final deprecation of the last blob hack
        'character_system_prompts TEXT NOT NULL DEFAULT "{}"',
        // v42 — groups foldering (nullable; null = home top level)
        'folder_id TEXT',
        // v34 — portable group stable id (Stoop update-in-place)
        'stable_id TEXT',
        // v3 (the UUID rebuild) — see the personas note on the epoch default.
        'updated_at INTEGER NOT NULL DEFAULT 0',
        'deleted_at INTEGER',
      ],
      'sessions': [
        // v12–v19 Realism columns. All added with the same silent catch, and
        // all named unconditionally by Drift's generated SELECT for sessions —
        // one missing column makes every chat open and every session-list
        // query throw "no such column". Defaults match the Sessions Table
        // class; where the historical ALTER disagreed (v12 wrote
        // relationship_tier DEFAULT 2, a scale that no longer exists) the
        // Table class wins, because that is the value every fresh install has.
        // v4 — the Journal's "Where we are" recap reuses these two.
        'summary TEXT',
        'summary_last_index INTEGER',
        'affection_score INTEGER NOT NULL DEFAULT 0', // v12
        'relationship_tier INTEGER NOT NULL DEFAULT 0', // v12
        'realism_enabled INTEGER NOT NULL DEFAULT 0', // v13
        'short_term_mood INTEGER NOT NULL DEFAULT 0', // v13
        'mood_decay_counter INTEGER NOT NULL DEFAULT 0', // v13
        "character_emotion TEXT NOT NULL DEFAULT ''", // v13
        "emotion_intensity TEXT NOT NULL DEFAULT ''", // v13
        "time_of_day TEXT NOT NULL DEFAULT 'morning'", // v13
        'day_count INTEGER NOT NULL DEFAULT 1', // v13
        'arousal_level INTEGER NOT NULL DEFAULT 0', // v15
        'long_term_score INTEGER NOT NULL DEFAULT 0', // v16
        'long_term_tier INTEGER NOT NULL DEFAULT 0', // v16
        'turns_since_long_term_check INTEGER NOT NULL DEFAULT 0', // v16
        'short_term_deltas_summary INTEGER NOT NULL DEFAULT 0', // v16
        'trust_level INTEGER NOT NULL DEFAULT 0', // v17
        "active_fixation TEXT NOT NULL DEFAULT ''", // v17
        'fixation_lifespan INTEGER NOT NULL DEFAULT 0', // v17
        "spatial_stance TEXT NOT NULL DEFAULT ''", // v17
        'trust_repair_pending INTEGER NOT NULL DEFAULT 0', // v18
        "evolved_personality TEXT NOT NULL DEFAULT ''", // v19
        "evolved_scenario TEXT NOT NULL DEFAULT ''", // v19
        'evolution_count INTEGER NOT NULL DEFAULT 0', // v19
        // v30 — the live per-group-member realism state (clean replacement for hidden checkpoint msgs)
        'group_realism_state TEXT NOT NULL DEFAULT "{}"',
        // Additional columns added with the same fragile pattern that group/per-char
        // Realism, Needs, Chaos, and evolution paths now depend on unconditionally.
        'group_evolved_personalities TEXT NOT NULL DEFAULT "{}"',
        'group_evolved_scenarios TEXT NOT NULL DEFAULT "{}"',
        'needs_sim_enabled INTEGER NOT NULL DEFAULT 0',
        'needs_vector TEXT',
        'start_day_of_week INTEGER NOT NULL DEFAULT 0',
        'chaos_mode_enabled INTEGER NOT NULL DEFAULT 0',
        'chaos_pressure INTEGER NOT NULL DEFAULT 0',
        'generation_settings TEXT',
        'user_persona_id TEXT',
        'passage_of_time_enabled INTEGER NOT NULL DEFAULT 1',
        'nsfw_cooldown_enabled INTEGER NOT NULL DEFAULT 0',
        'cooldown_turns_remaining INTEGER NOT NULL DEFAULT 0',
        'cooldown_turns_total INTEGER NOT NULL DEFAULT 0',
        'selected_look_avatar_id TEXT', // v37 gallery look
        'theme_overrides TEXT', // per-chat theme
        'context_budget_json TEXT', // v44 Context Viewer snapshot
        // v45 per-chat Objectives switch. DEFAULT 1 must match the Table
        // definition and the ladder exactly — objectives ran unconditionally
        // before v45, so 1 is the only value that preserves existing chats.
        'objectives_enabled INTEGER NOT NULL DEFAULT 1',
        // v47 — matches the Table definition and the ladder: nullable, no
        // default. NULL means nothing was recorded, which is true for every
        // chat older than the column.
        'pockets TEXT',
        // v48 — live Today side-quest row id. Nullable, no default. NULL
        // means this chat has no Today hold, which is true for every row
        // older than the column. Do not guess among secondaries.
        'today_objective_id TEXT',
        // v49 — 1:1 with-you glance. Nullable; NULL = never judged.
        'with_user INTEGER',
        // v38 Story Calendar — nullable; NULL = legacy row, synthesized on load
        'story_clock TEXT',
        'story_start_date TEXT',
        // v43 — 0 = world attachments not yet decided (lets back-fill run)
        'worlds_initialized INTEGER NOT NULL DEFAULT 0',
      ],
      'worlds': [
        // v40 Living Worlds (must match _migrateLivingWorldsV40)
        'cover_image TEXT',
        'format_version INTEGER NOT NULL DEFAULT 1',
        'source_id TEXT',
        'linked_character_id TEXT',
        'biome_id TEXT',
        'biome_json TEXT',
        'inject_description INTEGER NOT NULL DEFAULT 1',
        // v41
        'place_traits TEXT',
      ],
      'group_members': [
        // Per current GroupMembers Dart definition + created_at (to match the repair-path CREATE TABLE).
        // This gives the PRAGMA+ALTER+backup guard for any future columns added to the table
        // (addresses the previous limitation where only IF NOT EXISTS creation was used).
        'group_id TEXT NOT NULL',
        'name TEXT NOT NULL',
        "description TEXT NOT NULL DEFAULT ''",
        "personality TEXT NOT NULL DEFAULT ''",
        "scenario TEXT NOT NULL DEFAULT ''",
        "first_message TEXT NOT NULL DEFAULT ''",
        "mes_example TEXT NOT NULL DEFAULT ''",
        "system_prompt TEXT NOT NULL DEFAULT ''",
        "post_history_instructions TEXT NOT NULL DEFAULT ''",
        "alternate_greetings TEXT NOT NULL DEFAULT '[]'",
        "tags TEXT NOT NULL DEFAULT '[]'",
        'avatar_filename TEXT',
        'tts_voice TEXT',
        'lorebook TEXT',
        "world_names TEXT NOT NULL DEFAULT '[]'",
        'front_porch_extensions TEXT',
        'raw_extensions TEXT',
        "member_state TEXT NOT NULL DEFAULT '{}'",
        'updated_at INTEGER NOT NULL DEFAULT 0',
        'created_at INTEGER NOT NULL DEFAULT 0',
      ],
    };

    for (final entry in columnsToEnsure.entries) {
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

  /// Public helper so that direct-open paths (reunification, certain test or recovery
  /// scenarios) can explicitly ensure the schema matches before using group or objective
  /// features. The primary AppDatabase.instance() path calls the repair automatically.
  Future<void> ensureSchemaIsRepaired() => _repairMissingSchemaColumns();
}
