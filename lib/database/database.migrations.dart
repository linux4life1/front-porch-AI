// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The versioned onCreate/onUpgrade migration ladder (schema v1 -> v44).
// EVERY `if (from < N)` block in here is byte-verbatim from the original
// migration getter. Editing any block is a user-data-corruption risk.

part of 'database.dart';

/// The versioned onCreate/onUpgrade migration ladder (schema v1 → v44).
/// EVERY `if (from < N)` block in here is byte-verbatim from the original
/// migration getter. Editing any block is a user-data-corruption risk.
extension _AppDatabaseMigrationLadder on AppDatabase {
  Future<void> _onCreateMigration(Migrator m) async {
      await m.createAll();
      // Seed the sync_meta row on fresh installs
      await customInsert(
        'INSERT OR IGNORE INTO sync_meta (id, version, last_modified_at) '
        'VALUES (1, 0, ?)',
        variables: [Variable(DateTime.now().millisecondsSinceEpoch ~/ 1000)],
      );
  }

  Future<void> _onUpgradeMigration(Migrator m, int from, int to) async {
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
      if (from < 27) {
        // v26->v27: add per-session needs simulation (flag + vector)
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN needs_sim_enabled INTEGER NOT NULL DEFAULT 0',
          );
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN needs_vector TEXT',
          );
        } catch (_) {}
      }
      if (from < 28) {
        // v27->v28: persist narrative weekday anchor (startDayOfWeek) so Day N always maps to the same weekday across app restarts
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN start_day_of_week INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
      }
      if (from < 29) {
        // v28→v29: scope objectives to chat sessions (fix bleeding between chats)
        try {
          await customStatement(
            'ALTER TABLE objectives ADD COLUMN chat_id TEXT',
          );
        } catch (_) {}
      }
      if (from < 30) {
        // v29→v30: Proper DB-backed group realism/needs storage (clean break — no support
        // for old hidden __group_state__ checkpoint messages). Added with explicit dev
        // authorization. External direct-SQL tools will need to adapt.
        try {
          await customStatement(
            'ALTER TABLE groups ADD COLUMN default_member_realism_state TEXT NOT NULL DEFAULT "{}"',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN group_realism_state TEXT NOT NULL DEFAULT "{}"',
          );
        } catch (_) {}
      }
      if (from < 31) {
        // v30→v31: Group configuration columns for Chaos Mode toggles (including NSFW
        // variant), group-scoped lorebook + world selection/inheritance, and an immutable
        // creation-time baseline realism seed (separate from the mutable default member
        // state added in v30). Stored as clean dedicated columns (INTEGER for Bool, TEXT
        // for JSON strings) rather than inside a single JSON blob or piggy-backing on
        // character_ids / scenario etc. Follows v30 precedent of explicit columns over
        // hidden/magic storage for group concerns — improves Drift queries, self-documents
        // the schema for maintainers, and makes the contract obvious for external
        // direct-SQL writers. Purpose: enable precise group-level Chaos + lore scoping +
        // creation-seed baselines for Group Cards and new sessions. Added with explicit
        // dev authorization. External direct-SQL tools will need to adapt (provide values
        // or rely on the NOT NULL DEFAULTs documented here when writing to the groups table).
        try {
          await customStatement(
            'ALTER TABLE groups ADD COLUMN chaos_mode_enabled INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE groups ADD COLUMN chaos_nsfw_enabled INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
        try {
          await customStatement(
            "ALTER TABLE groups ADD COLUMN group_lorebook TEXT NOT NULL DEFAULT ''",
          );
        } catch (_) {}
        try {
          await customStatement(
            "ALTER TABLE groups ADD COLUMN world_ids TEXT NOT NULL DEFAULT '[]'",
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE groups ADD COLUMN inherit_character_lorebooks INTEGER NOT NULL DEFAULT 1',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE groups ADD COLUMN baseline_realism_state TEXT NOT NULL DEFAULT "{}"',
          );
        } catch (_) {}
      }

      if (from < 32) {
        // v31→v32: Final cleanup of the last "Path B" transitional JSON blob hack.
        // Per-character system prompts (group-scoped overrides) now have their own
        // first-class TEXT column instead of being merged into defaultMemberRealismState.
        // This completes the move to explicit columns for all group-level configuration
        // (following the v30 and v31 philosophy). All extraction/promotion logic that
        // previously read/wrote 'character_system_prompts' inside the realism blob has
        // been fully removed. Old data in the blob is ignored on load going forward.
        // External direct-SQL tools must now use the new column.
        try {
          await customStatement(
            'ALTER TABLE groups ADD COLUMN character_system_prompts TEXT NOT NULL DEFAULT "{}"',
          );
        } catch (_) {}
      }
      if (from < 33) {
        // v32→v33: web secure-login tables for the rewritten web server.
        // Replaces the old plaintext web-server PIN with username + Argon2id
        // password + optional TOTP, and persists per-device sessions (so they
        // survive app restart). Both are NEW tables — additive.
        await customStatement('''
          CREATE TABLE IF NOT EXISTS web_auth_credentials (
            id TEXT NOT NULL PRIMARY KEY,
            username TEXT NOT NULL,
            password_hash TEXT NOT NULL,
            totp_secret TEXT,
            totp_enabled INTEGER NOT NULL DEFAULT 0,
            recovery_codes TEXT,
            created_at INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await customStatement('''
          CREATE TABLE IF NOT EXISTS web_auth_sessions (
            id TEXT NOT NULL PRIMARY KEY,
            token_hash TEXT NOT NULL,
            user_id TEXT NOT NULL,
            created_at INTEGER NOT NULL DEFAULT 0,
            last_seen_at INTEGER NOT NULL DEFAULT 0,
            expires_at INTEGER NOT NULL DEFAULT 0,
            user_agent TEXT,
            ip TEXT,
            revoked INTEGER NOT NULL DEFAULT 0
          )
        ''');
      }
      if (from < 34) {
        // v33→v34: portable per-group stable id. Lets a shared group be UPDATED
        // in place on The Stoop (and re-associated after switching devices)
        // instead of creating a duplicate — the group analogue of a character's
        // stable id. Nullable + additive. Backfilled lazily in code
        // (null → generated on first export/share).
        try {
          await customStatement('ALTER TABLE groups ADD COLUMN stable_id TEXT');
        } catch (_) {}
      }
      if (from < 35) {
        // v34→v35: The Journal — per-chat, per-character memory cards
        // (docs/design/journal-memory.md). NEW table + index, additive only,
        // outside the Character Card Forge external-writer set, so this
        // cannot break it. Strictly session-scoped: cards never cross chats.
        await customStatement('''
          CREATE TABLE IF NOT EXISTS journal_memories (
            id TEXT NOT NULL PRIMARY KEY,
            session_id TEXT NOT NULL,
            character_id TEXT NOT NULL,
            source_message_ids TEXT,
            content TEXT NOT NULL,
            category TEXT NOT NULL DEFAULT 'moment',
            emotion_label TEXT,
            emotion_intensity TEXT,
            original_emotion_label TEXT,
            heat REAL NOT NULL DEFAULT 1.0,
            access_count INTEGER NOT NULL DEFAULT 0,
            pinned INTEGER NOT NULL DEFAULT 0,
            embedding BLOB,
            dimensions INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL DEFAULT 0,
            last_accessed_at INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL DEFAULT 0,
            metadata TEXT
          )
        ''');
        await customStatement(
          'CREATE INDEX IF NOT EXISTS journal_memories_session_character '
          'ON journal_memories (session_id, character_id)',
        );
      }
      if (from < 36) {
        // v35→v36: Growth Rings — per-chat, per-character growth entries +
        // per-session pass cursor (docs/design/growth-rings.md §5). NEW
        // tables only, additive, outside the Character Card Forge
        // external-writer set. The old Sessions evolved* columns go dormant
        // (content is distilled into rings by the first growth pass).
        await customStatement('''
          CREATE TABLE IF NOT EXISTS growth_rings (
            id TEXT NOT NULL PRIMARY KEY,
            session_id TEXT NOT NULL,
            character_id TEXT NOT NULL,
            content TEXT NOT NULL,
            category TEXT NOT NULL DEFAULT 'trait',
            strength REAL NOT NULL DEFAULT 0.3,
            pinned INTEGER NOT NULL DEFAULT 0,
            retired INTEGER NOT NULL DEFAULT 0,
            source_message_ids TEXT,
            created_at INTEGER NOT NULL DEFAULT 0,
            last_reinforced_at INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL DEFAULT 0,
            metadata TEXT
          )
        ''');
        await customStatement(
          'CREATE INDEX IF NOT EXISTS growth_rings_session_character '
          'ON growth_rings (session_id, character_id)',
        );
        await customStatement('''
          CREATE TABLE IF NOT EXISTS growth_state (
            session_id TEXT NOT NULL PRIMARY KEY,
            cursor INTEGER NOT NULL DEFAULT 0
          )
        ''');
      }
      if (from < 37) {
        // v36→v37: per-chat avatar-gallery look selection. Nullable, additive,
        // no default — the external card tool (Character Card Forge) simply
        // omits it (NULL). Guarded because drift rewrites user_version even
        // when an OLDER binary opens a newer DB (rollback / dual-run), so this
        // step can legally re-run against a DB that already has the column —
        // unguarded, that throws "duplicate column" on every launch.
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN selected_look_avatar_id TEXT',
          );
        } catch (_) {}
      }
      if (from < 38) {
        // v37→v38: the Story Calendar (docs/design/story-calendar.md).
        // Canonical minute-level clock + Day 1 anchor, both nullable additive
        // (maintainer-approved sessions change, 2026-07-20) — legacy rows stay
        // NULL and synthesize on first load; Character Card Forge's raw SQL
        // keeps working (timeOfDay/dayCount/startDayOfWeek are still written,
        // now derived from the clock). Guarded like v37 (rollback re-runs).
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN story_clock TEXT',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN story_start_date TEXT',
          );
        } catch (_) {}
      }
      if (from < 39) {
        // v38→v39: data-only heal, NO schema change. The pre-fix
        // generation-settings bleed persisted stale per-chat sampler
        // overrides into session rows the user never configured; once the
        // load path started reading them (the bleed fix itself), those rows
        // silently shadowed global sampler settings and made models loop /
        // repeat old messages. Strips all bleed-era keys, keeps only the
        // post-bleed output_sanitizer_* keys. Full rationale + key list in
        // session_gen_overrides_heal.dart.
        //
        // RE-RUN GUARD. Drift rewrites user_version even when an OLDER binary
        // opens a NEWER DB (rollback / the Windows beta+nightly pair that
        // share one data folder), so this block can legally re-enter with
        // `from = 38` on a database that was healed months ago. The heal's
        // "anything but the sanitizer keys is bleed junk" rule is only true
        // BEFORE v39 shipped: on a second pass it deletes the per-chat
        // temperature / repeat-penalty / DRY / stop-sequence overrides the
        // user has deliberately set since. There is no ALTER here to use as
        // the "this is the real upgrade" signal the way v40 does, so the
        // signal is the next version's columns: if v40's worlds columns are
        // already physically present, this database has been past v39 before
        // and the heal has already run.
        final worldsCols = await _getExistingColumnNames('worlds');
        final alreadyPastV39 =
            worldsCols.contains('inject_description') ||
            worldsCols.contains('biome_json');
        if (alreadyPastV39) {
          debugPrint(
            '[DB] v39: gen-overrides heal skipped — this database has '
            'already been upgraded past v39 (re-entry after a rollback); '
            "per-chat sampler settings are the user's and stay put",
          );
        } else {
          try {
            final healed = await healBledSessionGenOverrides(this);
            if (healed > 0) {
              debugPrint(
                '[DB] v39: cleared bled generation overrides '
                'from $healed session(s)',
              );
            }
          } catch (e) {
            // Non-fatal: stale overrides just stay active for this install.
            // Never abort the migration chain (and thereby DB open) over it.
            debugPrint('[DB] v39 gen-overrides heal failed: $e');
          }
        }
      }
      if (from < 40) {
        // v39→v40: Living Worlds (docs/design/living-worlds.md).
        // Additive only — no sessions/groups rebuild. Pre-migration file
        // backup via schema-repair path if columns missing; forced backup
        // attempted here too for the data backfill.
        await _migrateLivingWorldsV40();
      }
      if (from < 41) {
        // v40→v41: place traits (living-worlds.md §3 Rev.3). One nullable
        // JSON column; null ⇒ all-default traits (breathable, earth
        // gravity). No data migration, no CCF-written table touched.
        try {
          await customStatement('ALTER TABLE worlds ADD COLUMN place_traits TEXT');
          debugPrint('[DB] v41: added worlds.place_traits');
        } catch (_) {
          // already present (re-run / dual-version)
        }
      }
      if (from < 43) {
        // v42→v43: mark whether a chat's world attachments have been decided.
        // Existing rows default to 0 (undecided) on purpose — that is what lets
        // chats created before their character had a world finally receive it.
        // Additive with a default, so Character Card Forge's raw writes to
        // `sessions` keep working untouched.
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN worlds_initialized INTEGER NOT NULL DEFAULT 0',
          );
          debugPrint('[DB] v43: added sessions.worlds_initialized');
        } catch (_) {
          // already present (re-run / dual-version)
        }
      }
      if (from < 42) {
        // v41→v42: groups foldering (docs/design/folder-groups.md). One
        // nullable column so group cards can live in the same Home Screen
        // folder hierarchy as characters; null ⇒ top level. Additive only —
        // groups is not a Character-Card-Forge-written table.
        try {
          await customStatement('ALTER TABLE groups ADD COLUMN folder_id TEXT');
          debugPrint('[DB] v42: added groups.folder_id');
        } catch (_) {
          // already present (re-run / dual-version)
        }
      }
      if (from < 44) {
        await migrateSessionsContextBudgetV44(this);
      }
      if (from < 45) {
        // v44→v45: per-chat Objectives switch (docs/design/feature-independence.md).
        // Objectives ran unconditionally before this, so the default MUST be 1 —
        // every existing chat has to keep its quests running exactly as it did.
        // A default of 0 here would silently switch the feature off for the whole
        // installed base on upgrade. Additive with a default, so raw external
        // writers to `sessions` keep working untouched.
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN objectives_enabled INTEGER NOT NULL DEFAULT 1',
          );
          debugPrint('[DB] v45: added sessions.objectives_enabled');
        } catch (_) {
          // already present (re-run / dual-version)
        }
      }

      if (from < 46) {
        // v45→v46: which ambition an objective is a step toward
        // (docs/design/pockets-and-preferences.md Part 3).
        //
        // NULLABLE WITH NO DEFAULT, and that is the whole design: every
        // objective that already exists was proposed before ambitions steered
        // anything, so "which ambition does it serve" has no honest answer for
        // them. NULL says exactly that. Backfilling a guess here would put a
        // wrong "→ open her own bakery" chip under quests the character never
        // took for that reason.
        //
        // Additive and nullable, so a downgrade to a v45 build keeps reading
        // and writing this table normally — the column is simply ignored.
        try {
          await customStatement(
            'ALTER TABLE objectives ADD COLUMN served_ambition TEXT',
          );
          debugPrint('[DB] v46: added objectives.served_ambition');
        } catch (_) {
          // already present (re-run / dual-version)
        }
      }

      if (from < 47) {
        // v46→v47: the 1:1 speaker's Pockets record.
        //
        // Group chats already persisted theirs inside group_realism_state, so
        // this closes a parity hole rather than adding a feature: a 1:1 chat
        // had nowhere to keep the record, so reopening the chat emptied her
        // pockets. NULL for every existing row is exactly right — nothing was
        // ever saved, so there is nothing to claim otherwise, and the pass
        // simply re-seeds from the card as it does for a brand new chat.
        //
        // Additive and nullable, so a downgrade to v46 keeps reading and
        // writing `sessions` normally; the column is just ignored.
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN pockets TEXT',
          );
          debugPrint('[DB] v47: added sessions.pockets');
        } catch (_) {
          // already present (re-run / dual-version)
        }
      }

      if (from < 48) {
        // v47→v48: persist the Today side-quest row id on the session.
        // A user-typed secondary has the same shape (isPrimary false,
        // tasks [], servedAmbition null), so uniqueness-by-shape cannot
        // rebind on load. NULL for every existing row is right — those
        // chats have no Today hold to claim. Additive and nullable, so
        // a downgrade to v47 keeps reading sessions; the column is ignored.
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN today_objective_id TEXT',
          );
          debugPrint('[DB] v48: added sessions.today_objective_id');
        } catch (_) {
          // already present (re-run / dual-version)
        }
      }
  }
}
