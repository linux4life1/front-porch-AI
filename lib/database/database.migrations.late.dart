// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Versioned onUpgrade steps. EVERY `if (from < N)` block is byte-verbatim
// from the original migration getter. Editing any block is a
// user-data-corruption risk.

part of 'database.dart';

/// Schema v40 → v55 of the onUpgrade ladder. Blocks are byte-verbatim.
extension _AppDatabaseMigrationLate on AppDatabase {
  Future<void> _upgradeFromV40(Migrator m, int from, int to) async {
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
        await customStatement(
          'ALTER TABLE worlds ADD COLUMN place_traits TEXT',
        );
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
      // wrong "→ open their own bakery" chip under quests the character never
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
      // had nowhere to keep the record, so reopening the chat emptied their
      // pockets. NULL for every existing row is exactly right — nothing was
      // ever saved, so there is nothing to claim otherwise, and the pass
      // simply re-seeds from the card as it does for a brand new chat.
      //
      // Additive and nullable, so a downgrade to v46 keeps reading and
      // writing `sessions` normally; the column is just ignored.
      try {
        await customStatement('ALTER TABLE sessions ADD COLUMN pockets TEXT');
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

    if (from < 49) {
      // v48→v49: 1:1 With you / Away judge. NULL for every existing
      // row is right — those chats have never been judged, so the
      // glance keeps the keyword fallback. Additive and nullable.
      try {
        await customStatement(
          'ALTER TABLE sessions ADD COLUMN with_user INTEGER',
        );
        debugPrint('[DB] v49: added sessions.with_user');
      } catch (_) {
        // already present (re-run / dual-version)
      }
    }

    if (from < 50) {
      // v49→v50: persona calendar birthday. NULL for every existing
      // row is right — nobody had a stored birthday. Additive and
      // nullable, so a downgrade to v49 keeps reading personas.
      try {
        await customStatement('ALTER TABLE personas ADD COLUMN birthday TEXT');
        debugPrint('[DB] v50: added personas.birthday');
      } catch (_) {
        // already present (re-run / dual-version)
      }
    }

    if (from < 51) {
      // v50→v51: per-world climate plug. DEFAULT 1 is load-bearing —
      // every existing world already had climate/weather. A 0 would
      // silently unplug the weather machine for the installed library.
      try {
        await customStatement(
          'ALTER TABLE worlds ADD COLUMN climate_enabled INTEGER NOT NULL DEFAULT 1',
        );
        debugPrint('[DB] v51: added worlds.climate_enabled');
      } catch (_) {
        // already present (re-run / dual-version)
      }
    }
    if (from < 52) {
      // v51→v52: per-chat Setting (Primary) vs Lore role on attachments.
      // DEFAULT 0 (lore). Backfill: for each chat, first attached world
      // (by sort_order) whose worlds.climate_enabled=1 becomes primary;
      // if none are climate-enabled, Primary stays empty (all lore).
      //
      // RE-RUN GUARD. Same dual-version class as v39/v40: an older binary
      // stamps user_version down, this block re-enters, ALTER no-ops, and
      // an unguarded UPDATE would revive a Setting the user moved to lore.
      // A successful ALTER is the only honest "this is the real upgrade"
      // signal. Repair that *adds* the column must call the same backfill.
      final addedNow = await _tryAddChatWorldsIsPrimary();
      if (addedNow) {
        await _backfillChatWorldsIsPrimary();
      } else {
        debugPrint(
          '[DB] v52: is_primary already present — skipping backfill '
          '(re-entry after a rollback)',
        );
      }
    }
    if (from < 53) {
      // v52→v53: one-shot flag so leftover per-chat Passage of Time
      // (old card-AND / auto-seed false) can be re-derived once. DEFAULT 0
      // — every existing row is unmigrated. Additive with a default, so
      // raw external writers to `sessions` keep working.
      try {
        await customStatement(
          'ALTER TABLE sessions ADD COLUMN '
          'passage_of_time_gate_migrated INTEGER NOT NULL DEFAULT 0',
        );
        debugPrint('[DB] v53: added sessions.passage_of_time_gate_migrated');
      } catch (_) {
        // already present (re-run / dual-version)
      }
    }
    if (from < 54) {
      // v53→v54: growth_rings came from the raw v36 DDL with
      // `created_at/last_reinforced_at/updated_at ... DEFAULT 0`, and addRing
      // never wrote them, so every upgraded ring reads 1970. Backfill once
      // from the best evidence: the first receipt's message time, else the
      // first reinforce, else the chat's creation, else now.
      // messages.updated_at is the last edit, and whole chats get
      // bulk-touched, so that guess can land after the ring's own stamps.
      // created_at is the earliest of the guess, last_reinforced_at, and
      // updated_at (a missing stamp does not pull the min down). A bad
      // source_message_ids value must not throw — that fails the open.
      // Only rows still at 0 are touched, so a re-run is a no-op.
      await customStatement('''
        UPDATE growth_rings SET created_at = MIN(
          COALESCE(
            NULLIF((SELECT MIN(m.updated_at) FROM messages m
                    WHERE m.session_id = growth_rings.session_id
                      AND m.position = CAST(
                        CASE WHEN json_valid(growth_rings.source_message_ids)
                          THEN json_extract(
                            growth_rings.source_message_ids, '\$[0]')
                        END AS INTEGER)
                      AND m.updated_at > 0), 0),
            NULLIF(growth_rings.last_reinforced_at, 0),
            NULLIF((SELECT s.created_at FROM sessions s
                    WHERE s.id = growth_rings.session_id), 0),
            CAST(strftime('%s', 'now') AS INTEGER)
          ),
          COALESCE(NULLIF(growth_rings.last_reinforced_at, 0), 9223372036854775807),
          COALESCE(NULLIF(growth_rings.updated_at, 0), 9223372036854775807)
        )
        WHERE created_at = 0
      ''');
      await customStatement(
        'UPDATE growth_rings SET last_reinforced_at = created_at '
        'WHERE last_reinforced_at = 0',
      );
      await customStatement(
        'UPDATE growth_rings SET updated_at = MAX(created_at, last_reinforced_at) '
        'WHERE updated_at = 0',
      );
      debugPrint('[DB] v54: backfilled growth_rings timestamps');
    }
    if (from < 55) {
      // v54→v55: the refractory counts story minutes. NULL for every
      // existing row is right — no minutes were ever saved, so the load
      // reads the row's cooldown_turns_* once as turns × 15. Additive and
      // nullable, so a downgrade to v54 keeps reading sessions; the columns
      // are ignored.
      for (final ddl in const [
        'ALTER TABLE sessions ADD COLUMN refractory_minutes_remaining INTEGER',
        'ALTER TABLE sessions ADD COLUMN refractory_minutes_total INTEGER',
        'ALTER TABLE sessions ADD COLUMN refractory_opened INTEGER',
      ]) {
        try {
          await customStatement(ddl);
          debugPrint('[DB] v55: $ddl');
        } catch (_) {
          // already present (re-run / dual-version)
        }
      }
    }
  }

  /// True only when this pass actually created `chat_worlds.is_primary`.
  Future<bool> _tryAddChatWorldsIsPrimary() async {
    try {
      await customStatement(
        'ALTER TABLE chat_worlds ADD COLUMN is_primary '
        'INTEGER NOT NULL DEFAULT 0',
      );
      debugPrint('[DB] v52: added chat_worlds.is_primary');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _backfillChatWorldsIsPrimary() async {
    try {
      await customStatement(
        'UPDATE chat_worlds '
        'SET is_primary = 1 '
        'WHERE id IN ('
        '  SELECT cw.id '
        '  FROM chat_worlds cw '
        '  INNER JOIN worlds w ON w.id = cw.world_id '
        '  WHERE w.climate_enabled = 1 '
        '    AND cw.id = ('
        '      SELECT cw2.id '
        '      FROM chat_worlds cw2 '
        '      INNER JOIN worlds w2 ON w2.id = cw2.world_id '
        '      WHERE cw2.chat_id = cw.chat_id '
        '        AND w2.climate_enabled = 1 '
        '      ORDER BY cw2.sort_order ASC, cw2.id ASC '
        '      LIMIT 1'
        '    )'
        ')',
      );
      debugPrint('[DB] v52: backfilled chat_worlds.is_primary');
    } catch (e) {
      debugPrint('[DB] v52: is_primary backfill skipped: $e');
    }
  }
}
