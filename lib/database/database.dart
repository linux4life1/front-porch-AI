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
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/services/db_reunification_service.dart';

part 'database.g.dart';

const _uuid = Uuid();

// ── Table Definitions ─────────────────────────────────────────────────

/// Characters table - stores metadata extracted from PNG tEXt chunks.
/// The PNG file remains the source of truth for import/export interop.
class Characters extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get personality => text().withDefault(const Constant(''))();
  TextColumn get scenario => text().withDefault(const Constant(''))();
  TextColumn get firstMessage => text().withDefault(const Constant(''))();
  TextColumn get mesExample => text().withDefault(const Constant(''))();
  TextColumn get systemPrompt => text().withDefault(const Constant(''))();
  TextColumn get postHistoryInstructions =>
      text().withDefault(const Constant(''))();
  TextColumn get alternateGreetings =>
      text().withDefault(const Constant('[]'))(); // JSON array
  TextColumn get tags =>
      text().withDefault(const Constant('[]'))(); // JSON array
  TextColumn get imagePath => text().nullable()();
  TextColumn get ttsVoice => text().nullable()();
  TextColumn get folderId => text().nullable()();
  TextColumn get lorebook => text().nullable()(); // JSON blob
  TextColumn get worldNames =>
      text().withDefault(const Constant('[]'))(); // JSON array
  TextColumn get memorySources => text().withDefault(
    const Constant('[]'),
  )(); // JSON array of character IDs for cross-character RAG
  TextColumn get evolvedPersonality => text().withDefault(
    const Constant(''),
  )(); // LLM-evolved personality overlay
  TextColumn get evolvedScenario =>
      text().withDefault(const Constant(''))(); // LLM-evolved scenario overlay
  IntColumn get evolutionCount =>
      integer().withDefault(const Constant(0))(); // number of evolutions
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get primeAvatarIndex => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Avatar images for characters.
/// Each character can have up to 10 avatars stored in their subdirectory.
class AvatarImages extends Table {
  TextColumn get id => text()();
  TextColumn get characterId => text()();
  TextColumn get filename => text()();
  TextColumn get label => text().nullable()();
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Chat sessions - one per conversation thread.
class Sessions extends Table {
  TextColumn get id => text()(); // timestamp-based ID
  TextColumn get characterId => text().nullable()();
  TextColumn get groupId => text().nullable()();
  TextColumn get name => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get authorNote => text().withDefault(const Constant(''))();
  IntColumn get authorNoteDepth => integer().withDefault(const Constant(4))();
  TextColumn get summary => text().nullable()(); // rolling chat summary
  IntColumn get summaryLastIndex =>
      integer().nullable()(); // message index at last summary update
  TextColumn get parentSession => text().nullable()();
  IntColumn get forkIndex => integer().nullable()();
  IntColumn get affectionScore =>
      integer().withDefault(const Constant(0))(); // short-term tension points
  IntColumn get relationshipTier =>
      integer().withDefault(const Constant(0))(); // short-term tier
  IntColumn get longTermScore =>
      integer().withDefault(const Constant(0))(); // slowly accumulating bond
  IntColumn get longTermTier =>
      integer().withDefault(const Constant(0))(); // long-term rank
  IntColumn get turnsSinceLongTermCheck =>
      integer().withDefault(const Constant(0))(); // 5-turn counter
  IntColumn get shortTermDeltasSummary =>
      integer().withDefault(const Constant(0))(); // trends over 5 turns
  BoolColumn get realismEnabled =>
      boolean().withDefault(const Constant(false))(); // master realism toggle
  IntColumn get shortTermMood =>
      integer().withDefault(const Constant(0))(); // -5 to +5
  IntColumn get moodDecayCounter =>
      integer().withDefault(const Constant(0))(); // msgs since last mood change
  TextColumn get characterEmotion =>
      text().withDefault(const Constant(''))(); // e.g. "amused"
  TextColumn get emotionIntensity =>
      text().withDefault(const Constant(''))(); // mild/moderate/strong
  TextColumn get timeOfDay =>
      text().withDefault(const Constant('morning'))(); // dawn/morning/etc
  IntColumn get dayCount =>
      integer().withDefault(const Constant(1))(); // starts at Day 1
  BoolColumn get nsfwCooldownEnabled =>
      boolean().withDefault(const Constant(false))(); // sub-toggle
  BoolColumn get passageOfTimeEnabled => boolean().withDefault(
    const Constant(true),
  )(); // sub-toggle for automatic time advancement
  IntColumn get arousalLevel =>
      integer().withDefault(const Constant(0))(); // 0 to 10 scale
  IntColumn get cooldownTurnsRemaining =>
      integer().withDefault(const Constant(0))(); // 0 = no cooldown

  // Realism Engine v3.0 Behavioral Mechanics
  IntColumn get trustLevel =>
      integer().withDefault(const Constant(0))(); // -100 to 100 paranoia/trust
  TextColumn get activeFixation =>
      text().withDefault(const Constant(''))(); // ongoing obsession topic
  IntColumn get fixationLifespan =>
      integer().withDefault(const Constant(0))(); // decay turns
  TextColumn get spatialStance =>
      text().withDefault(const Constant(''))(); // physical anchor
  BoolColumn get trustRepairPending => boolean().withDefault(
    const Constant(false),
  )(); // repair window armed after severe trust drop

  // Chance Time / Chaos Mode (v21)
  BoolColumn get chaosModeEnabled =>
      boolean().withDefault(const Constant(false))();
  IntColumn get chaosPressure => integer().withDefault(
    const Constant(0),
  )(); // 0-100 escalating trigger chance

  // Per-session character evolution (v19)
  // 1:1 chats: plain evolved text
  TextColumn get evolvedPersonality => text().withDefault(const Constant(''))();
  TextColumn get evolvedScenario => text().withDefault(const Constant(''))();
  IntColumn get evolutionCount => integer().withDefault(const Constant(0))();
  // Group chats: JSON maps { charId → evolved text }
  TextColumn get groupEvolvedPersonalities =>
      text().withDefault(const Constant('{}'))();
  TextColumn get groupEvolvedScenarios =>
      text().withDefault(const Constant('{}'))();

  // Per-session generation parameter overrides (v22)
  TextColumn get generationSettings =>
      text().nullable()(); // JSON blob, null = use global defaults

  // User persona linked to this session (v25)
  TextColumn get userPersonaId => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Individual chat messages within a session.
class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text()();
  IntColumn get position => integer()(); // ordering within session
  TextColumn get sender => text()();
  BoolColumn get isUser => boolean()();
  TextColumn get characterId => text().nullable()(); // for group chats
  TextColumn get swipes =>
      text().withDefault(const Constant('[]'))(); // JSON array
  IntColumn get swipeIndex => integer().withDefault(const Constant(0))();
  TextColumn get swipeDurations =>
      text().withDefault(const Constant('[]'))(); // JSON array
  TextColumn get metadata => text().nullable()();
  TextColumn get swipeMetadata => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Group chat definitions.
class Groups extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get characterIds =>
      text().withDefault(const Constant('[]'))(); // JSON array
  TextColumn get turnOrder =>
      text().withDefault(const Constant('roundRobin'))();
  BoolColumn get autoAdvance => boolean().withDefault(const Constant(false))();
  BoolColumn get directorMode => boolean().withDefault(const Constant(false))();
  TextColumn get firstMessage => text().withDefault(const Constant(''))();
  TextColumn get scenario => text().withDefault(const Constant(''))();
  TextColumn get systemPrompt => text().withDefault(const Constant(''))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Character folder organization.
class Folders extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get parentId => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// User personas.
class Personas extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get name => text().withDefault(const Constant('User'))();
  TextColumn get persona => text().withDefault(const Constant(''))();
  TextColumn get learnedFacts => text().withDefault(
    const Constant('[]'),
  )(); // JSON array of fact strings from auto-persona
  TextColumn get avatarPath => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// World/lorebook definitions.
class Worlds extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().unique()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get lorebook => text().nullable()(); // JSON blob
  TextColumn get linkedCharacterName => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Message embeddings for RAG memory retrieval.
class MessageEmbeddings extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text()();
  TextColumn get characterId => text().nullable()();
  IntColumn get positionStart => integer()();
  IntColumn get positionEnd => integer()();
  TextColumn get content => text()();
  BlobColumn get embedding => blob()();
  IntColumn get dimensions => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Single-row sync metadata for version-based cloud sync.
class SyncMeta extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  IntColumn get version => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastModifiedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Data Bank entries — user-provided knowledge per character for RAG retrieval.
class DataBankEntries extends Table {
  TextColumn get id => text()();
  TextColumn get characterId => text()(); // which character this belongs to
  TextColumn get title => text()(); // user-given label
  TextColumn get content => text()(); // the actual text content
  BlobColumn get embedding =>
      blob().nullable()(); // pre-computed embedding vector
  IntColumn get dimensions => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Objectives — quest/task system for guided roleplay.
class Objectives extends Table {
  TextColumn get id => text()();
  TextColumn get characterId =>
      text()(); // which character this objective belongs to
  TextColumn get objective => text()(); // the main goal
  TextColumn get tasks => text().withDefault(
    const Constant('[]'),
  )(); // JSON array of {description, completed}
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  BoolColumn get isPrimary => boolean().withDefault(
    const Constant(false),
  )(); // Primary vs secondary goal
  IntColumn get checkFrequency => integer().withDefault(
    const Constant(3),
  )(); // check task completion every N messages
  IntColumn get injectionDepth => integer().withDefault(
    const Constant(4),
  )(); // how many messages from end to inject (0=strongest)
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Porch Stories — AI-generated novel projects.
class StoryProjects extends Table {
  TextColumn get id => text()();
  TextColumn get title =>
      text().withDefault(const Constant('Untitled Story'))();
  TextColumn get data => text()(); // Full StoryProject JSON blob
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

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
    MessageEmbeddings,
    DataBankEntries,
    Objectives,
    StoryProjects,
    SyncMeta,
    AvatarImages,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase._internal(super.e);

  static AppDatabase? _instance;
  static String? _dbPath;
  static String? _dbDir;

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
    final basePath = rootPath ?? p.join(
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
    if (isPreRelease && !file.existsSync()) {
      final prefs = await SharedPreferences.getInstance();
      final shown = prefs.getBool('beta_stable_import_shown') ?? false;
      if (shown) {
        // Dialog has been shown — respect the user's choice
        final skipped = prefs.getBool('beta_stable_import_skipped') ?? false;
        if (!skipped) {
          final prodFile = File(p.join(dbDir, 'front_porch.db'));
          if (prodFile.existsSync()) {
            debugPrint('[DB] Pre-release build — copying production DB to beta DB');
            await prodFile.copy(file.path);
          }
        }
      } else {
        // Dialog not yet shown — defer to the import dialog which will
        // show after the first frame and trigger the copy manually.
        debugPrint('[DB] Pre-release build — import dialog pending, skipping copy');
      }
    }

    // For stable builds: reunify beta DB into production if both exist.
    // This is a one-time operation on the first 0.9.0 stable launch.
    // Steps 1-2 run here (backup + promote). Steps 3-5 (diff + import)
    // run later in main.dart with a UI overlay.
    if (!isPreRelease &&
        await DbReunificationService.needsReunification(dbDir)) {
      debugPrint(
        '[DB] Reunification needed — backing up and promoting beta DB',
      );
      await DbReunificationService.createBackups(dbDir);
      await DbReunificationService.promoteBetaDb(dbDir);
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
    return _instance!;
  }

  /// The absolute path to the database file on disk.
  static String? get dbFilePath => _dbPath;

  /// The directory containing the database files.
  static String? get dbDirPath => _dbDir;

  /// Flush WAL (Write-Ahead Log) to the main database file.
  /// Call this before uploading the .db file to ensure it's self-contained.
  Future<void> checkpoint() async {
    await customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
  }

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

  /// Close the database and clear the singleton so the next call to
  /// [instance()] will open a fresh connection to the file on disk.
  /// Used after cloud sync downloads a new .db file.
  static Future<void> closeAndReset() async {
    if (_instance != null) {
      await _instance!.close();
      _instance = null;
    }
  }

  /// For testing: create an in-memory database.
  factory AppDatabase.forTesting() {
    return AppDatabase._internal(
      NativeDatabase.createInBackground(
        File(':memory:'),
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
  int get schemaVersion => 25;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      // Seed the sync_meta row on fresh installs
      await customInsert(
        'INSERT OR IGNORE INTO sync_meta (id, version, last_modified_at) '
        'VALUES (1, 0, ?)',
        variables: [Variable(DateTime.now().millisecondsSinceEpoch ~/ 1000)],
      );
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        // v1→v2: create sync_meta table
        await customStatement(
          'CREATE TABLE IF NOT EXISTS sync_meta ('
          'id INTEGER NOT NULL DEFAULT 1, '
          'version INTEGER NOT NULL DEFAULT 0, '
          'last_modified_at INTEGER NOT NULL DEFAULT 0, '
          'PRIMARY KEY (id))',
        );
        await customInsert(
          'INSERT OR IGNORE INTO sync_meta (id, version, last_modified_at) '
          'VALUES (1, 0, ?)',
          variables: [Variable(DateTime.now().millisecondsSinceEpoch ~/ 1000)],
        );
      }
      if (from < 3) {
        // v2→v3: migrate int PKs to text UUIDs, add updatedAt/deletedAt
        await _migrateToUuids();
      }
      if (from < 4) {
        // v3→v4: add summary columns to sessions
        await customStatement('ALTER TABLE sessions ADD COLUMN summary TEXT');
        await customStatement(
          'ALTER TABLE sessions ADD COLUMN summary_last_index INTEGER',
        );
      }
      if (from < 5) {
        // v4→v5: add message_embeddings table for RAG + memorySources on characters
        await customStatement(
          'CREATE TABLE IF NOT EXISTS message_embeddings ('
          'id TEXT NOT NULL, '
          'session_id TEXT NOT NULL, '
          'character_id TEXT, '
          'position_start INTEGER NOT NULL, '
          'position_end INTEGER NOT NULL, '
          'content TEXT NOT NULL, '
          'embedding BLOB NOT NULL, '
          'dimensions INTEGER NOT NULL, '
          'created_at INTEGER NOT NULL DEFAULT 0, '
          'PRIMARY KEY (id))',
        );
        // Add memorySources column to characters for cross-character RAG
        try {
          await customStatement(
            "ALTER TABLE characters ADD COLUMN memory_sources TEXT NOT NULL DEFAULT '[]'",
          );
        } catch (_) {
          // Column may already exist
        }
      }
      if (from < 6) {
        // v5→v6: add learnedFacts column to personas for auto-persona
        try {
          await customStatement(
            "ALTER TABLE personas ADD COLUMN learned_facts TEXT NOT NULL DEFAULT '[]'",
          );
        } catch (_) {
          // Column may already exist
        }
      }
      if (from < 7) {
        // v6→v7: add data_bank_entries table for knowledge base
        await customStatement(
          'CREATE TABLE IF NOT EXISTS data_bank_entries ('
          'id TEXT NOT NULL, '
          'character_id TEXT NOT NULL, '
          'title TEXT NOT NULL, '
          'content TEXT NOT NULL, '
          'embedding BLOB, '
          'dimensions INTEGER NOT NULL DEFAULT 0, '
          'created_at INTEGER NOT NULL DEFAULT 0, '
          'PRIMARY KEY (id))',
        );
      }
      if (from < 8) {
        // v7→v8: add objectives table for quest/task system
        await customStatement(
          'CREATE TABLE IF NOT EXISTS objectives ('
          'id TEXT NOT NULL, '
          'character_id TEXT NOT NULL, '
          'objective TEXT NOT NULL, '
          'tasks TEXT NOT NULL DEFAULT \'[]\', '
          'active INTEGER NOT NULL DEFAULT 1, '
          'check_frequency INTEGER NOT NULL DEFAULT 3, '
          'injection_depth INTEGER NOT NULL DEFAULT 4, '
          'created_at INTEGER NOT NULL DEFAULT 0, '
          'PRIMARY KEY (id))',
        );
      }
      if (from < 9) {
        // v8→v9: add injection_depth column to objectives
        try {
          await customStatement(
            "ALTER TABLE objectives ADD COLUMN injection_depth INTEGER NOT NULL DEFAULT 4",
          );
        } catch (_) {
          // Column may already exist (fresh v8+ installs)
        }
      }
      if (from < 10) {
        // v9→v10: add character evolution columns
        try {
          await customStatement(
            "ALTER TABLE characters ADD COLUMN evolved_personality TEXT NOT NULL DEFAULT ''",
          );
        } catch (_) {}
        try {
          await customStatement(
            "ALTER TABLE characters ADD COLUMN evolved_scenario TEXT NOT NULL DEFAULT ''",
          );
        } catch (_) {}
        try {
          await customStatement(
            "ALTER TABLE characters ADD COLUMN evolution_count INTEGER NOT NULL DEFAULT 0",
          );
        } catch (_) {}
      }
      if (from < 11) {
        // v10→v11: add story_projects table for Porch Stories
        await customStatement(
          'CREATE TABLE IF NOT EXISTS story_projects ('
          'id TEXT NOT NULL, '
          'title TEXT NOT NULL DEFAULT \'Untitled Story\', '
          'data TEXT NOT NULL, '
          'created_at INTEGER NOT NULL DEFAULT 0, '
          'updated_at INTEGER NOT NULL DEFAULT 0, '
          'deleted_at INTEGER, '
          'PRIMARY KEY (id))',
        );
      }
      if (from < 12) {
        // v11→v12: add relationship tracker columns to sessions
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN affection_score INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN relationship_tier INTEGER NOT NULL DEFAULT 2',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN relationship_enabled INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
      }
      if (from < 13) {
        // v12→v13: Realism Mode — rename relationship_enabled → realism_enabled, add new columns
        // Rename: SQLite doesn't support RENAME COLUMN on older versions, so we add the new col
        // and copy data if the old one exists.
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN realism_enabled INTEGER NOT NULL DEFAULT 0',
          );
          // Copy existing relationship_enabled values to realism_enabled
          await customStatement(
            'UPDATE sessions SET realism_enabled = relationship_enabled',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN short_term_mood INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN mood_decay_counter INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
        try {
          await customStatement(
            "ALTER TABLE sessions ADD COLUMN character_emotion TEXT NOT NULL DEFAULT ''",
          );
        } catch (_) {}
        try {
          await customStatement(
            "ALTER TABLE sessions ADD COLUMN emotion_intensity TEXT NOT NULL DEFAULT ''",
          );
        } catch (_) {}
        try {
          await customStatement(
            "ALTER TABLE sessions ADD COLUMN time_of_day TEXT NOT NULL DEFAULT 'morning'",
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN day_count INTEGER NOT NULL DEFAULT 1',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN nsfw_cooldown_enabled INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN cooldown_turns_remaining INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
      }
      if (from < 14) {
        // v13→v14: add metadata columns to messages
        try {
          await customStatement(
            'ALTER TABLE messages ADD COLUMN metadata TEXT',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE messages ADD COLUMN swipe_metadata TEXT',
          );
        } catch (_) {}
      }
      if (from < 15) {
        // v14→v15: add arousal tracker to sessions
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN arousal_level INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
      }
      if (from < 16) {
        // v15→v16: add long term relationship tracking fields
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN long_term_score INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN long_term_tier INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN turns_since_long_term_check INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN short_term_deltas_summary INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
      }
      if (from < 17) {
        // v16→v17: add behavioral Realism Mechanics
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN trust_level INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
        try {
          await customStatement(
            "ALTER TABLE sessions ADD COLUMN active_fixation TEXT NOT NULL DEFAULT ''",
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN fixation_lifespan INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
        try {
          await customStatement(
            "ALTER TABLE sessions ADD COLUMN spatial_stance TEXT NOT NULL DEFAULT ''",
          );
        } catch (_) {}
      }
      if (from < 18) {
        // v17→v18: add trust repair window flag
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN trust_repair_pending INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
      }
      if (from < 19) {
        // v18→v19: per-session character evolution columns
        try {
          await customStatement(
            "ALTER TABLE sessions ADD COLUMN evolved_personality TEXT NOT NULL DEFAULT ''",
          );
        } catch (_) {}
        try {
          await customStatement(
            "ALTER TABLE sessions ADD COLUMN evolved_scenario TEXT NOT NULL DEFAULT ''",
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN evolution_count INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
        try {
          await customStatement(
            "ALTER TABLE sessions ADD COLUMN group_evolved_personalities TEXT NOT NULL DEFAULT '{}'",
          );
        } catch (_) {}
        try {
          await customStatement(
            "ALTER TABLE sessions ADD COLUMN group_evolved_scenarios TEXT NOT NULL DEFAULT '{}'",
          );
        } catch (_) {}
        // Data preservation: copy existing character-level evolved data into
        // all their matching (non-deleted) session rows so no user data is lost.
        try {
          final evolvedChars = await customSelect(
            "SELECT id, evolved_personality, evolved_scenario, evolution_count "
            "FROM characters "
            "WHERE (evolved_personality != '' OR evolved_scenario != '') "
            "AND deleted_at IS NULL",
          ).get();
          for (final row in evolvedChars) {
            final charId = row.read<String>('id');
            final ep = row.read<String>('evolved_personality');
            final es = row.read<String>('evolved_scenario');
            final ec = row.read<int>('evolution_count');
            await customUpdate(
              'UPDATE sessions SET evolved_personality = ?, evolved_scenario = ?, evolution_count = ? '
              'WHERE character_id = ? AND deleted_at IS NULL',
              variables: [
                Variable(ep),
                Variable(es),
                Variable(ec),
                Variable(charId),
              ],
              updates: {sessions},
            );
            debugPrint(
              '[DB] v19 migration: copied evolution data for character $charId to their sessions',
            );
          }
        } catch (e) {
          debugPrint('[DB] v19 migration: data copy failed (non-fatal): $e');
        }
      }
      if (from < 20) {
        // v19→v20: multi-objective support (primary vs secondary goals)
        try {
          // Defaulting to 1 so any previously active goal becomes the primary goal
          await customStatement(
            'ALTER TABLE objectives ADD COLUMN is_primary INTEGER NOT NULL DEFAULT 1',
          );
        } catch (_) {}
      }
      if (from < 21) {
        // v20→v21: Chaos Mode / Chance Time system
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN chaos_mode_enabled INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN chaos_pressure INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
      }
      if (from < 22) {
        // v21→v22: per-session generation parameter overrides
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN generation_settings TEXT',
          );
        } catch (_) {}
      }
      if (from < 23) {
        // v22->v23: add passage_of_time_enabled sub-toggle for realism mode
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN passage_of_time_enabled INTEGER NOT NULL DEFAULT 1',
          );
        } catch (_) {}
      }
      if (from < 24) {
        // v23->v24: add primeAvatarIndex to characters and avatar_images table
        try {
          await customStatement(
            "ALTER TABLE characters ADD COLUMN prime_avatar_index INTEGER NOT NULL DEFAULT 1",
          );
        } catch (_) {}
        await customStatement(
          'CREATE TABLE IF NOT EXISTS avatar_images ('
          'id TEXT NOT NULL, '
          'character_id TEXT NOT NULL, '
          'filename TEXT NOT NULL, '
          'label TEXT, '
          'display_order INTEGER NOT NULL DEFAULT 0, '
          'created_at INTEGER NOT NULL DEFAULT 0, '
          'PRIMARY KEY (id))',
        );
      }
      if (from < 25) {
        // v24->v25: add userPersonaId to sessions
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN user_persona_id TEXT',
          );
        } catch (_) {}
      }
      if (from < 26) {
        // v25->v26: consolidate persona fields — merge description into persona, drop description
        // For rows where persona is empty but description has content → copy description to persona
        // For rows where both have content → keep persona (it's the full text)
        try {
          await customStatement(
            "UPDATE personas SET persona = COALESCE(NULLIF(persona, ''), description) WHERE description != ''",
          );
          await customStatement('ALTER TABLE personas DROP COLUMN description');
        } catch (_) {}
      }
    },
  );

  /// Migrate all int-keyed tables to UUID text PKs.
  /// Creates new tables, copies data with generated UUIDs, drops old, renames.
  Future<void> _migrateToUuids() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // ── Folders ──────────────────────────────────────────────────
    await customStatement(
      'CREATE TABLE folders_new ('
      'id TEXT NOT NULL, name TEXT NOT NULL, parent_id TEXT, '
      'updated_at INTEGER NOT NULL DEFAULT $now, '
      'deleted_at INTEGER, PRIMARY KEY (id))',
    );
    // Build oldId→uuid map
    final oldFolders = await customSelect(
      'SELECT id, name, parent_id FROM folders',
    ).get();
    final folderIdMap = <int, String>{}; // old int → new uuid
    for (final row in oldFolders) {
      final oldId = row.read<int>('id');
      folderIdMap[oldId] = _uuid.v4();
    }
    for (final row in oldFolders) {
      final oldId = row.read<int>('id');
      final newId = folderIdMap[oldId]!;
      final oldParent = row.readNullable<int>('parent_id');
      final newParent = oldParent != null ? folderIdMap[oldParent] : null;
      await customInsert(
        'INSERT INTO folders_new (id, name, parent_id, updated_at) VALUES (?, ?, ?, ?)',
        variables: [
          Variable(newId),
          Variable(row.read<String>('name')),
          Variable(newParent),
          Variable(now),
        ],
      );
    }
    await customStatement('DROP TABLE folders');
    await customStatement('ALTER TABLE folders_new RENAME TO folders');

    // ── Characters ───────────────────────────────────────────────
    await customStatement(
      'CREATE TABLE characters_new ('
      'id TEXT NOT NULL, name TEXT NOT NULL, '
      'description TEXT NOT NULL DEFAULT \'\', personality TEXT NOT NULL DEFAULT \'\', '
      'scenario TEXT NOT NULL DEFAULT \'\', first_message TEXT NOT NULL DEFAULT \'\', '
      'mes_example TEXT NOT NULL DEFAULT \'\', system_prompt TEXT NOT NULL DEFAULT \'\', '
      'post_history_instructions TEXT NOT NULL DEFAULT \'\', '
      'alternate_greetings TEXT NOT NULL DEFAULT \'[]\', '
      'tags TEXT NOT NULL DEFAULT \'[]\', '
      'image_path TEXT, tts_voice TEXT, folder_id TEXT, '
      'lorebook TEXT, world_names TEXT NOT NULL DEFAULT \'[]\', '
      'created_at INTEGER NOT NULL DEFAULT $now, '
      'updated_at INTEGER NOT NULL DEFAULT $now, '
      'deleted_at INTEGER, PRIMARY KEY (id))',
    );
    final oldChars = await customSelect('SELECT * FROM characters').get();
    final charIdMap = <int, String>{}; // old int → new uuid
    for (final row in oldChars) {
      final oldId = row.read<int>('id');
      charIdMap[oldId] = _uuid.v4();
    }
    for (final row in oldChars) {
      final oldId = row.read<int>('id');
      final newId = charIdMap[oldId]!;
      final oldFolderId = row.readNullable<int>('folder_id');
      final newFolderId = oldFolderId != null ? folderIdMap[oldFolderId] : null;
      await customInsert(
        'INSERT INTO characters_new (id, name, description, personality, scenario, '
        'first_message, mes_example, system_prompt, post_history_instructions, '
        'alternate_greetings, tags, image_path, tts_voice, folder_id, '
        'lorebook, world_names, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        variables: [
          Variable(newId),
          Variable(row.read<String>('name')),
          Variable(row.read<String>('description')),
          Variable(row.read<String>('personality')),
          Variable(row.read<String>('scenario')),
          Variable(row.read<String>('first_message')),
          Variable(row.read<String>('mes_example')),
          Variable(row.read<String>('system_prompt')),
          Variable(row.read<String>('post_history_instructions')),
          Variable(row.read<String>('alternate_greetings')),
          Variable(row.read<String>('tags')),
          Variable(row.readNullable<String>('image_path')),
          Variable(row.readNullable<String>('tts_voice')),
          Variable(newFolderId),
          Variable(row.readNullable<String>('lorebook')),
          Variable(row.read<String>('world_names')),
          Variable(row.read<int>('created_at')),
          Variable(row.read<int>('updated_at')),
        ],
      );
    }
    await customStatement('DROP TABLE characters');
    await customStatement('ALTER TABLE characters_new RENAME TO characters');

    // ── Sessions (already text PK, just remap characterId int→text, add deletedAt) ──
    await customStatement(
      'CREATE TABLE sessions_new ('
      'id TEXT NOT NULL, character_id TEXT, group_id TEXT, '
      'name TEXT, description TEXT, '
      'author_note TEXT NOT NULL DEFAULT \'\', '
      'author_note_depth INTEGER NOT NULL DEFAULT 4, '
      'parent_session TEXT, fork_index INTEGER, '
      'created_at INTEGER NOT NULL DEFAULT $now, '
      'updated_at INTEGER NOT NULL DEFAULT $now, '
      'deleted_at INTEGER, PRIMARY KEY (id))',
    );
    final oldSessions = await customSelect('SELECT * FROM sessions').get();
    for (final row in oldSessions) {
      final oldCharId = row.readNullable<int>('character_id');
      final newCharId = oldCharId != null ? charIdMap[oldCharId] : null;
      await customInsert(
        'INSERT INTO sessions_new (id, character_id, group_id, name, description, '
        'author_note, author_note_depth, parent_session, fork_index, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        variables: [
          Variable(row.read<String>('id')),
          Variable(newCharId),
          Variable(row.readNullable<String>('group_id')),
          Variable(row.readNullable<String>('name')),
          Variable(row.readNullable<String>('description')),
          Variable(row.read<String>('author_note')),
          Variable(row.read<int>('author_note_depth')),
          Variable(row.readNullable<String>('parent_session')),
          Variable(row.readNullable<int>('fork_index')),
          Variable(row.read<int>('created_at')),
          Variable(row.read<int>('updated_at')),
        ],
      );
    }
    await customStatement('DROP TABLE sessions');
    await customStatement('ALTER TABLE sessions_new RENAME TO sessions');

    // ── Messages (int PK → text UUID, add updatedAt/deletedAt) ──
    await customStatement(
      'CREATE TABLE messages_new ('
      'id TEXT NOT NULL, session_id TEXT NOT NULL, '
      'position INTEGER NOT NULL, sender TEXT NOT NULL, '
      'is_user INTEGER NOT NULL, character_id TEXT, '
      'swipes TEXT NOT NULL DEFAULT \'[]\', '
      'swipe_index INTEGER NOT NULL DEFAULT 0, '
      'swipe_durations TEXT NOT NULL DEFAULT \'[]\', '
      'updated_at INTEGER NOT NULL DEFAULT $now, '
      'deleted_at INTEGER, PRIMARY KEY (id))',
    );
    final oldMsgs = await customSelect('SELECT * FROM messages').get();
    for (final row in oldMsgs) {
      await customInsert(
        'INSERT INTO messages_new (id, session_id, position, sender, is_user, '
        'character_id, swipes, swipe_index, swipe_durations, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        variables: [
          Variable(_uuid.v4()), // generate UUID for each message
          Variable(row.read<String>('session_id')),
          Variable(row.read<int>('position')),
          Variable(row.read<String>('sender')),
          Variable(row.read<bool>('is_user') ? 1 : 0),
          Variable(row.readNullable<String>('character_id')),
          Variable(row.read<String>('swipes')),
          Variable(row.read<int>('swipe_index')),
          Variable(row.read<String>('swipe_durations')),
          Variable(now),
        ],
      );
    }
    await customStatement('DROP TABLE messages');
    await customStatement('ALTER TABLE messages_new RENAME TO messages');

    // ── Groups (already text PK, just add updatedAt/deletedAt) ──
    await customStatement(
      'ALTER TABLE groups ADD COLUMN updated_at INTEGER NOT NULL DEFAULT $now',
    );
    await customStatement('ALTER TABLE groups ADD COLUMN deleted_at INTEGER');

    // ── Personas (already text PK, just add updatedAt/deletedAt) ──
    await customStatement(
      'ALTER TABLE personas ADD COLUMN updated_at INTEGER NOT NULL DEFAULT $now',
    );
    await customStatement('ALTER TABLE personas ADD COLUMN deleted_at INTEGER');

    // ── Worlds (int PK → text UUID, add updatedAt/deletedAt) ──
    await customStatement(
      'CREATE TABLE worlds_new ('
      'id TEXT NOT NULL, name TEXT NOT NULL UNIQUE, '
      'description TEXT NOT NULL DEFAULT \'\', '
      'lorebook TEXT, linked_character_name TEXT, '
      'updated_at INTEGER NOT NULL DEFAULT $now, '
      'deleted_at INTEGER, PRIMARY KEY (id))',
    );
    final oldWorlds = await customSelect('SELECT * FROM worlds').get();
    for (final row in oldWorlds) {
      await customInsert(
        'INSERT INTO worlds_new (id, name, description, lorebook, linked_character_name, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        variables: [
          Variable(_uuid.v4()),
          Variable(row.read<String>('name')),
          Variable(row.read<String>('description')),
          Variable(row.readNullable<String>('lorebook')),
          Variable(row.readNullable<String>('linked_character_name')),
          Variable(now),
        ],
      );
    }
    await customStatement('DROP TABLE worlds');
    await customStatement('ALTER TABLE worlds_new RENAME TO worlds');
  }

  // ── Sync Meta Queries ────────────────────────────────────────────────

  /// Get the current sync version (0 if no row exists yet).
  Future<int> getSyncVersion() async {
    try {
      final rows = await customSelect(
        'SELECT version FROM sync_meta WHERE id = 1',
      ).get();
      return rows.isNotEmpty ? rows.first.read<int>('version') : 0;
    } catch (_) {
      return 0;
    }
  }

  /// Increment the sync version counter. Call after every meaningful write.
  Future<void> bumpSyncVersion() async {
    await customUpdate(
      'UPDATE sync_meta SET version = version + 1, '
      'last_modified_at = ? WHERE id = 1',
      variables: [Variable(DateTime.now().millisecondsSinceEpoch ~/ 1000)],
      updates: {syncMeta},
    );
  }

  /// Hard-delete all soft-deleted rows from every table and VACUUM the database
  /// to reclaim disk space. Without this, deleted messages accumulate and bloat
  /// the DB (e.g. 59k deleted messages = 300+ MB of wasted space).
  Future<int> purgeDeletedRows() async {
    int total = 0;
    for (final table in [
      'messages',
      'sessions',
      'characters',
      'groups',
      'folders',
      'personas',
      'worlds',
    ]) {
      final count = await customUpdate(
        'DELETE FROM $table WHERE deleted_at IS NOT NULL',
        updates: {},
      );
      if (count > 0) {
        debugPrint('[DB] Purged $count deleted rows from $table');
        total += count;
      }
    }
    if (total > 0) {
      debugPrint('[DB] Purged $total deleted rows total — running VACUUM');
      await customStatement('VACUUM');
      debugPrint('[DB] VACUUM complete');
    }
    return total;
  }

  // ── Character Queries ───────────────────────────────────────────────

  Future<List<Character>> getAllCharacters() =>
      (select(characters)..where((c) => c.deletedAt.isNull())).get();

  Stream<List<Character>> watchAllCharacters() =>
      (select(characters)..where((c) => c.deletedAt.isNull())).watch();

  Future<Character> getCharacterById(String id) =>
      (select(characters)..where((c) => c.id.equals(id))).getSingle();

  Future<Character?> getCharacterByImagePath(String path) =>
      (select(characters)
            ..where((c) => c.imagePath.equals(path) & c.deletedAt.isNull()))
          .getSingleOrNull();

  Future<int> insertCharacter(CharactersCompanion character) async {
    // Ensure UUID is set
    if (!character.id.present) {
      character = character.copyWith(id: Value(_uuid.v4()));
    }
    final result = await into(characters).insert(character);
    await bumpSyncVersion();
    return result;
  }

  /// Insert a character and return its UUID (convenience for callers that need the ID).
  Future<String> insertCharacterReturningId(
    CharactersCompanion character,
  ) async {
    final id = character.id.present ? character.id.value : _uuid.v4();
    character = character.copyWith(id: Value(id));
    await into(characters).insert(character);
    await bumpSyncVersion();
    return id;
  }

  Future<bool> updateCharacter(CharactersCompanion character) async {
    // IMPORTANT: Use .write() not .replace() — .replace() overwrites the entire
    // row, wiping any fields not explicitly set (Value.absent → null/default).
    // .write() only updates fields where Value.present is true.
    final rows = await (update(
      characters,
    )..where((c) => c.id.equals(character.id.value))).write(character);
    await bumpSyncVersion();
    return rows > 0;
  }

  /// Update ONLY the imagePath for a character (preserves all other data).
  Future<void> updateCharacterImagePath(String id, String newPath) async {
    await (update(characters)..where((c) => c.id.equals(id))).write(
      CharactersCompanion(imagePath: Value(newPath)),
    );
    await bumpSyncVersion();
  }

  Future<int> deleteCharacterById(String id) async {
    // Hard delete: also cascade to sessions and their messages
    final charSessions = await (select(
      sessions,
    )..where((s) => s.characterId.equals(id))).get();
    for (final s in charSessions) {
      await (delete(messages)..where((m) => m.sessionId.equals(s.id))).go();
    }
    await (delete(sessions)..where((s) => s.characterId.equals(id))).go();
    final count = await (delete(
      characters,
    )..where((c) => c.id.equals(id))).go();
    await bumpSyncVersion();
    return count;
  }

  // ── Avatar Queries ──────────────────────────────────────────────────

  /// Get all avatar images for a character.
  Future<List<AvatarImage>> getAvatarImagesByCharacterId(
    String characterId,
  ) async {
    return (select(avatarImages)
          ..where((a) => a.characterId.equals(characterId))
          ..orderBy([(a) => OrderingTerm.asc(a.displayOrder)]))
        .get();
  }

  /// Get a single avatar by ID.
  Future<AvatarImage?> getAvatarById(String id) async {
    return (select(avatarImages)..where((a) => a.id.equals(id))).getSingleOrNull();
  }

  /// Count avatars for a character (to determine next display order).
  Future<int> countAvatarsForCharacter(String characterId) async {
    final result = await (select(avatarImages)
          ..where((a) => a.characterId.equals(characterId)))
        .get();
    return result.length;
  }

  /// Insert an avatar image record.
  Future<void> insertAvatar(AvatarImagesCompanion avatar) async {
    await into(avatarImages).insert(avatar);
    await bumpSyncVersion();
  }

  /// Delete an avatar image record.
  Future<int> deleteAvatar(String id) async {
    final count = await (delete(avatarImages)..where((a) => a.id.equals(id))).go();
    await bumpSyncVersion();
    return count;
  }

  /// Update the prime avatar index for a character.
  Future<void> updatePrimeAvatarIndex(String characterId, int primeIndex) async {
    await (update(characters)..where((c) => c.id.equals(characterId))).write(
      CharactersCompanion(primeAvatarIndex: Value(primeIndex)),
    );
    await bumpSyncVersion();
  }

  /// Update the label for an avatar image.
  Future<void> updateAvatarLabel(String avatarId, String label) async {
    await (update(avatarImages)..where((a) => a.id.equals(avatarId))).write(
      AvatarImagesCompanion(label: Value(label)),
    );
    await bumpSyncVersion();
  }

  // ── Session Queries ─────────────────────────────────────────────────

  /// Get total message count per character (for home screen badges).
  Future<Map<String, int>> getMessageCountsPerCharacter() async {
    final result = await customSelect(
      'SELECT s.character_id, COUNT(m.id) AS cnt '
      'FROM sessions s JOIN messages m ON m.session_id = s.id '
      'WHERE s.character_id IS NOT NULL AND s.deleted_at IS NULL AND m.deleted_at IS NULL '
      'AND m.is_user = 1 '
      'GROUP BY s.character_id',
    ).get();
    final map = <String, int>{};
    for (final row in result) {
      final charId = row.read<String>('character_id');
      final count = row.read<int>('cnt');
      map[charId] = count;
    }
    return map;
  }

  /// Get the most recent session update time per character.
  Future<Map<String, DateTime>> getLastActivityPerCharacter() async {
    final result = await customSelect(
      'SELECT character_id, MAX(created_at) AS last_at '
      'FROM sessions '
      'WHERE character_id IS NOT NULL AND deleted_at IS NULL '
      'GROUP BY character_id',
    ).get();
    final map = <String, DateTime>{};
    for (final row in result) {
      final charId = row.read<String>('character_id');
      final lastAt = row.read<DateTime>('last_at');
      map[charId] = lastAt;
    }
    return map;
  }

  Future<List<Session>> getSessionsForCharacter(String characterId) =>
      (select(sessions)
            ..where(
              (s) => s.characterId.equals(characterId) & s.deletedAt.isNull(),
            )
            ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]))
          .get();

  Future<List<Session>> getSessionsForGroup(String groupId) =>
      (select(sessions)
            ..where((s) => s.groupId.equals(groupId) & s.deletedAt.isNull())
            ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]))
          .get();

  Future<Session?> getSessionById(String id) =>
      (select(sessions)..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<int> insertSession(SessionsCompanion session) async {
    final result = await into(sessions).insert(session);
    await bumpSyncVersion();
    return result;
  }

  Future<int> upsertSession(SessionsCompanion session) async {
    final result = await into(sessions).insertOnConflictUpdate(session);
    await bumpSyncVersion();
    return result;
  }

  Future<bool> updateSession(SessionsCompanion session) async {
    final result = await update(sessions).replace(session);
    await bumpSyncVersion();
    return result;
  }

  /// Partial-update a session — only writes fields that are explicitly set
  /// (Value.present). Safe to call without providing the full row.
  Future<bool> patchSession(SessionsCompanion session) async {
    final rows = await (update(
      sessions,
    )..where((s) => s.id.equals(session.id.value))).write(session);
    await bumpSyncVersion();
    return rows > 0;
  }

  Future<int> deleteSessionById(String id) async {
    // Hard delete: also delete all messages in this session
    await (delete(messages)..where((m) => m.sessionId.equals(id))).go();
    final count = await (delete(sessions)..where((s) => s.id.equals(id))).go();
    await bumpSyncVersion();
    return count;
  }

  // ── Message Queries ─────────────────────────────────────────────────

  Future<List<Message>> getMessagesForSession(String sessionId) =>
      (select(messages)
            ..where((m) => m.sessionId.equals(sessionId) & m.deletedAt.isNull())
            ..orderBy([(m) => OrderingTerm.asc(m.position)]))
          .get();

  Stream<List<Message>> watchMessagesForSession(String sessionId) =>
      (select(messages)
            ..where((m) => m.sessionId.equals(sessionId) & m.deletedAt.isNull())
            ..orderBy([(m) => OrderingTerm.asc(m.position)]))
          .watch();

  Future<int> insertMessage(MessagesCompanion message) async {
    if (!message.id.present) {
      message = message.copyWith(id: Value(_uuid.v4()));
    }
    final result = await into(messages).insert(message);
    await bumpSyncVersion();
    return result;
  }

  Future<void> insertMessages(List<MessagesCompanion> msgs) async {
    final withIds = msgs
        .map((m) => m.id.present ? m : m.copyWith(id: Value(_uuid.v4())))
        .toList();
    await batch((b) => b.insertAll(messages, withIds));
    await bumpSyncVersion();
  }

  Future<int> deleteMessagesForSession(String sessionId) async {
    final count = await (delete(
      messages,
    )..where((m) => m.sessionId.equals(sessionId))).go();
    await bumpSyncVersion();
    return count;
  }

  Future<int> deleteMessageById(String id) async {
    final count = await (delete(messages)..where((m) => m.id.equals(id))).go();
    await bumpSyncVersion();
    return count;
  }

  Future<void> updateMessage(MessagesCompanion message) async {
    await (update(
      messages,
    )..where((m) => m.id.equals(message.id.value))).write(message);
    await bumpSyncVersion();
  }

  // ── Group Queries ───────────────────────────────────────────────────

  Future<List<Group>> getAllGroups() =>
      (select(groups)..where((g) => g.deletedAt.isNull())).get();

  Stream<List<Group>> watchAllGroups() =>
      (select(groups)..where((g) => g.deletedAt.isNull())).watch();

  Future<Group?> getGroupById(String id) =>
      (select(groups)..where((g) => g.id.equals(id))).getSingleOrNull();

  Future<int> insertGroup(GroupsCompanion group) async {
    final result = await into(groups).insert(group);
    await bumpSyncVersion();
    return result;
  }

  Future<bool> updateGroup(GroupsCompanion group) async {
    final result = await update(groups).replace(group);
    await bumpSyncVersion();
    return result;
  }

  Future<int> deleteGroupById(String id) async {
    // Hard delete: also cascade to sessions and their messages
    final groupSessions = await (select(
      sessions,
    )..where((s) => s.groupId.equals(id))).get();
    for (final s in groupSessions) {
      await (delete(messages)..where((m) => m.sessionId.equals(s.id))).go();
    }
    await (delete(sessions)..where((s) => s.groupId.equals(id))).go();
    final count = await (delete(groups)..where((g) => g.id.equals(id))).go();
    await bumpSyncVersion();
    return count;
  }

  // ── Folder Queries ──────────────────────────────────────────────────

  Future<List<Folder>> getAllFolders() =>
      (select(folders)..where((f) => f.deletedAt.isNull())).get();

  Future<String> insertFolder(FoldersCompanion folder) async {
    final id = folder.id.present ? folder.id.value : _uuid.v4();
    folder = folder.copyWith(id: Value(id));
    await into(folders).insert(folder);
    await bumpSyncVersion();
    return id;
  }

  Future<int> deleteFolderById(String id) async {
    final count = await (delete(folders)..where((f) => f.id.equals(id))).go();
    await bumpSyncVersion();
    return count;
  }

  Future<void> updateFolder(FoldersCompanion folder) async {
    await (update(
      folders,
    )..where((f) => f.id.equals(folder.id.value))).write(folder);
    await bumpSyncVersion();
  }

  // ── Persona Queries ─────────────────────────────────────────────────

  Future<List<Persona>> getAllPersonas() =>
      (select(personas)..where((p) => p.deletedAt.isNull())).get();

  Future<Persona?> getActivePersona() =>
      (select(personas)
            ..where((p) => p.isActive.equals(true) & p.deletedAt.isNull()))
          .getSingleOrNull();

  Future<int> insertPersona(PersonasCompanion persona) async {
    final result = await into(personas).insert(persona);
    await bumpSyncVersion();
    return result;
  }

  Future<bool> updatePersona(PersonasCompanion persona) async {
    final result = await update(personas).replace(persona);
    await bumpSyncVersion();
    return result;
  }

  Future<int> deletePersonaById(String id) async {
    final count = await (delete(personas)..where((p) => p.id.equals(id))).go();
    await bumpSyncVersion();
    return count;
  }

  Future<void> setActivePersona(String id) async {
    await transaction(() async {
      // Deactivate all
      await (update(
        personas,
      )).write(const PersonasCompanion(isActive: Value(false)));
      // Activate the chosen one
      await (update(personas)..where((p) => p.id.equals(id))).write(
        const PersonasCompanion(isActive: Value(true)),
      );
    });
    await bumpSyncVersion();
  }

  // ── World Queries ───────────────────────────────────────────────────

  Future<List<World>> getAllWorlds() =>
      (select(worlds)..where((w) => w.deletedAt.isNull())).get();

  Stream<List<World>> watchAllWorlds() =>
      (select(worlds)..where((w) => w.deletedAt.isNull())).watch();

  Future<String> insertWorld(WorldsCompanion world) async {
    final id = world.id.present ? world.id.value : _uuid.v4();
    world = world.copyWith(id: Value(id));
    await into(worlds).insert(world);
    await bumpSyncVersion();
    return id;
  }

  Future<bool> updateWorld(WorldsCompanion world) async {
    final result = await update(worlds).replace(world);
    await bumpSyncVersion();
    return result;
  }

  Future<int> deleteWorldById(String id) async {
    final count = await (delete(worlds)..where((w) => w.id.equals(id))).go();
    await bumpSyncVersion();
    return count;
  }

  Future<World?> getWorldByName(String name) =>
      (select(worlds)..where((w) => w.name.equals(name) & w.deletedAt.isNull()))
          .getSingleOrNull();

  // ── Embedding Queries ──────────────────────────────────────────────

  Future<void> insertEmbedding(MessageEmbeddingsCompanion embedding) async {
    if (!embedding.id.present) {
      embedding = embedding.copyWith(id: Value(_uuid.v4()));
    }
    await into(messageEmbeddings).insert(embedding);
  }

  Future<void> insertEmbeddings(
    List<MessageEmbeddingsCompanion> embeddings,
  ) async {
    final withIds = embeddings
        .map((e) => e.id.present ? e : e.copyWith(id: Value(_uuid.v4())))
        .toList();
    await batch((b) => b.insertAll(messageEmbeddings, withIds));
  }

  /// Get all embeddings for a set of character IDs (for cross-character RAG search).
  Future<List<MessageEmbedding>> getEmbeddingsForCharacters(
    List<String> characterIds,
  ) async {
    if (characterIds.isEmpty) return [];
    return (select(
      messageEmbeddings,
    )..where((e) => e.characterId.isIn(characterIds))).get();
  }

  /// Get all embeddings for a specific session.
  Future<List<MessageEmbedding>> getEmbeddingsForSession(String sessionId) =>
      (select(
        messageEmbeddings,
      )..where((e) => e.sessionId.equals(sessionId))).get();

  /// Delete all embeddings for a session (cascading cleanup).
  Future<int> deleteEmbeddingsForSession(String sessionId) => (delete(
    messageEmbeddings,
  )..where((e) => e.sessionId.equals(sessionId))).go();

  /// Delete all embeddings for a character.
  Future<int> deleteEmbeddingsForCharacter(String characterId) => (delete(
    messageEmbeddings,
  )..where((e) => e.characterId.equals(characterId))).go();

  /// Count total embeddings (for debug/settings display).
  Future<int> countEmbeddings() async {
    final result = await customSelect(
      'SELECT COUNT(*) AS cnt FROM message_embeddings',
    ).getSingle();
    return result.read<int>('cnt');
  }

  // ── Data Bank Queries ────────────────────────────────────────────────────────

  Future<void> insertDataBankEntry(DataBankEntriesCompanion entry) async {
    if (!entry.id.present) {
      entry = entry.copyWith(id: Value(_uuid.v4()));
    }
    await into(dataBankEntries).insert(entry);
  }

  Future<List<DataBankEntry>> getDataBankEntriesForCharacter(
    String characterId,
  ) => (select(
    dataBankEntries,
  )..where((e) => e.characterId.equals(characterId))).get();

  Future<void> updateDataBankEntry(DataBankEntriesCompanion entry) => (update(
    dataBankEntries,
  )..where((e) => e.id.equals(entry.id.value))).write(entry);

  Future<int> deleteDataBankEntry(String id) =>
      (delete(dataBankEntries)..where((e) => e.id.equals(id))).go();

  Future<int> deleteDataBankEntriesForCharacter(String characterId) => (delete(
    dataBankEntries,
  )..where((e) => e.characterId.equals(characterId))).go();

  // ── Objectives ─────────────────────────────────────────────────────

  Future<List<Objective>> getObjectivesForCharacter(String characterId) =>
      (select(objectives)
            ..where((o) => o.characterId.equals(characterId))
            ..orderBy([
              (o) => OrderingTerm(
                expression: o.createdAt,
                mode: OrderingMode.desc,
              ),
            ]))
          .get();

  Future<List<Objective>> getActiveObjectives(String characterId) =>
      (select(objectives)
            ..where(
              (o) => o.characterId.equals(characterId) & o.active.equals(true),
            )
            ..orderBy([
              (o) => OrderingTerm(
                expression: o.isPrimary,
                mode: OrderingMode.desc,
              ),
              (o) =>
                  OrderingTerm(expression: o.createdAt, mode: OrderingMode.asc),
            ]))
          .get();

  Future<void> insertObjective(ObjectivesCompanion entry) async {
    final id = entry.id.present ? entry.id.value : const Uuid().v4();
    await into(objectives).insert(entry.copyWith(id: Value(id)));
  }

  Future<void> updateObjective(ObjectivesCompanion entry) => (update(
    objectives,
  )..where((o) => o.id.equals(entry.id.value))).write(entry);

  Future<int> deleteObjective(String id) =>
      (delete(objectives)..where((o) => o.id.equals(id))).go();

  Future<int> deleteObjectivesForCharacter(String characterId) => (delete(
    objectives,
  )..where((o) => o.characterId.equals(characterId))).go();

  // ── Story Project Queries ────────────────────────────────────────────

  Future<List<StoryProject>> getAllStoryProjects() =>
      (select(storyProjects)
            ..where((s) => s.deletedAt.isNull())
            ..orderBy([(s) => OrderingTerm.desc(s.updatedAt)]))
          .get();

  Stream<List<StoryProject>> watchAllStoryProjects() =>
      (select(storyProjects)
            ..where((s) => s.deletedAt.isNull())
            ..orderBy([(s) => OrderingTerm.desc(s.updatedAt)]))
          .watch();

  Future<StoryProject?> getStoryProjectById(String id) =>
      (select(storyProjects)..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<String> insertStoryProject(StoryProjectsCompanion project) async {
    final id = project.id.present ? project.id.value : _uuid.v4();
    project = project.copyWith(id: Value(id));
    await into(storyProjects).insert(project);
    await bumpSyncVersion();
    return id;
  }

  Future<void> updateStoryProject(StoryProjectsCompanion project) async {
    await (update(
      storyProjects,
    )..where((s) => s.id.equals(project.id.value))).write(project);
    await bumpSyncVersion();
  }

  Future<int> deleteStoryProject(String id) async {
    final count = await (delete(
      storyProjects,
    )..where((s) => s.id.equals(id))).go();
    await bumpSyncVersion();
    return count;
  }

  // ── Soft Delete Cleanup ─────────────────────────────────────────────

  /// Permanently remove rows soft-deleted more than 30 days ago.
  Future<void> purgeSoftDeletes() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final cutoffEpoch = cutoff.millisecondsSinceEpoch ~/ 1000;
    for (final table in [
      'messages',
      'sessions',
      'characters',
      'folders',
      'groups',
      'personas',
      'worlds',
      'story_projects',
    ]) {
      await customUpdate(
        'DELETE FROM $table WHERE deleted_at IS NOT NULL AND deleted_at < ?',
        variables: [Variable(cutoffEpoch)],
      );
    }
  }
}
