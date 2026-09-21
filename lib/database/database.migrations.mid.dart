// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Versioned onUpgrade steps. EVERY `if (from < N)` block is byte-verbatim
// from the original migration getter. Editing any block is a
// user-data-corruption risk.

part of 'database.dart';

/// Schema v27 → v39 of the onUpgrade ladder. Blocks are byte-verbatim.
extension _AppDatabaseMigrationMid on AppDatabase {
  Future<void> _upgradeV27toV39(Migrator m, int from, int to) async {
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
        await customStatement('ALTER TABLE objectives ADD COLUMN chat_id TEXT');
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
  }
}
