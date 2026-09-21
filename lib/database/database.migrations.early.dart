// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Versioned onUpgrade steps. EVERY `if (from < N)` block is byte-verbatim
// from the original migration getter. Editing any block is a
// user-data-corruption risk.

part of 'database.dart';

/// Schema v2 → v26 of the onUpgrade ladder. Blocks are byte-verbatim.
extension _AppDatabaseMigrationEarly on AppDatabase {
  Future<void> _upgradeThroughV26(Migrator m, int from, int to) async {
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
        await customStatement('ALTER TABLE messages ADD COLUMN metadata TEXT');
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
  }
}
