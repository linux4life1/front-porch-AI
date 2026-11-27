// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The versioned onCreate/onUpgrade migration ladder (schema v1 -> v54).
// EVERY `if (from < N)` block is byte-verbatim from the original
// migration getter. Editing any block is a user-data-corruption risk.
// Steps are split across sibling parts (v2–v26, v27–v39, v40–v54).

part of 'database.dart';

/// The versioned onCreate/onUpgrade migration ladder (schema v1 → v54).
/// EVERY `if (from < N)` block is byte-verbatim from the original
/// migration getter. Editing any block is a user-data-corruption risk.
extension _AppDatabaseMigrationLadder on AppDatabase {
  Future<void> _onCreateMigration(Migrator m) async {
    await m.createAll();
    await _ensureMessageSessionIndex();
    // Seed the sync_meta row on fresh installs
    await customInsert(
      'INSERT OR IGNORE INTO sync_meta (id, version, last_modified_at) '
      'VALUES (1, 0, ?)',
      variables: [Variable(DateTime.now().millisecondsSinceEpoch ~/ 1000)],
    );
  }

  Future<void> _onUpgradeMigration(Migrator m, int from, int to) async {
    await _upgradeThroughV26(m, from, to);
    await _upgradeV27toV39(m, from, to);
    await _upgradeFromV40(m, from, to);
    // v66→v67: each group's stored member start moves onto the member's copy.
    if (from < 67) await migrateGroupSeedsToMemberCopies(this);
    if (from < 69) {
      // v68→v69: Boons & Bogies kit seeding — one INTEGER per session
      // row saying whether the card kit has been settled (docs/design/
      // boons-and-bogies.md §4). Additive; 0 reads "never touched".
      try {
        await customStatement(
          'ALTER TABLE growth_state ADD COLUMN kit_seed_state INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {
        // already present (re-run / dual-version)
      }
    }
    if (from < 70) {
      // v69→v70: Boons & Bogies participation switch on the chat row
      // (docs/design/boons-and-bogies.md ruling 18, 2026-11-21). Additive;
      // 1 means "participates when the global allows", which is exactly how
      // every existing chat behaved, so an upgrade changes nothing.
      try {
        await customStatement(
          'ALTER TABLE sessions ADD COLUMN bb_enabled INTEGER NOT NULL DEFAULT 1',
        );
      } catch (_) {
        // already present (re-run / dual-version)
      }
    }
    if (from < 68) {
      // v67→v68: Boons & Bogies — the roll/advance columns on growth_rings
      // and the growth_moments queue (docs/design/boons-and-bogies.md §3.3,
      // §7). Additive; every default reads "nothing has happened yet", so an
      // upgraded chat behaves exactly as before until the feature is turned
      // on. The same column list feeds the always-on schema repair.
      for (final c in kGrowthBogeyColumnsV68) {
        try {
          await customStatement('ALTER TABLE growth_rings ADD COLUMN $c');
        } catch (_) {
          // already present (re-run / dual-version)
        }
      }
      try {
        await customStatement(
          'CREATE TABLE IF NOT EXISTS growth_moments ('
          'id TEXT NOT NULL PRIMARY KEY, '
          'session_id TEXT NOT NULL, '
          'character_id TEXT NOT NULL, '
          'ring_id TEXT, '
          'kind TEXT NOT NULL, '
          'tier TEXT, '
          "created_at INTEGER NOT NULL DEFAULT (CAST(strftime('%s','now') AS INTEGER)), "
          'seen INTEGER NOT NULL DEFAULT 0'
          ')',
        );
        debugPrint('[DB] v68: growth_moments table ready');
      } catch (e) {
        debugPrint('[DB] v68: growth_moments create skipped: $e');
      }
    }
    if (from < 71) {
      // v70→v71: phase-5 milestones on growth_moments — decision state, the
      // proposal, and when it popped (docs/design/boons-and-bogies.md §7).
      // After the v68 block, which creates the table on an older upgrade.
      // Additive; no moment row existed before phase 5.
      for (final c in kGrowthMomentColumnsV71) {
        try {
          await customStatement('ALTER TABLE growth_moments ADD COLUMN $c');
        } catch (_) {
          // already present (re-run / dual-version)
        }
      }
    }
    if (from < 72) {
      // v71→v72: the kit entries each chat has taken (growth_state, created
      // in the v36 rung), so a kit entry added mid-chat lands on refresh and
      // one removed from a chat stays removed. Additive and nullable.
      try {
        await customStatement(
          'ALTER TABLE growth_state ADD COLUMN kit_seen TEXT',
        );
      } catch (e) {
        debugPrint('[DB] v72 kit_seen: $e (the repair pass re-checks)');
      }
    }
    if (from < 73) {
      // v72→v73: the chat's Author's Note switch (issue #743). Additive; 1
      // is how every existing chat behaved, so an upgrade changes nothing.
      try {
        await customStatement(
          'ALTER TABLE sessions ADD COLUMN author_note_enabled '
          'INTEGER NOT NULL DEFAULT 1',
        );
      } catch (e) {
        debugPrint('[DB] v73 author_note_enabled: $e (repair re-checks)');
      }
    }
    if (from < 74) {
      // v73→v74: Heat, closeness to release (docs/design/heat-meter.md).
      // Additive; 0 is where every existing chat's Heat starts.
      try {
        await customStatement(
          'ALTER TABLE sessions ADD COLUMN heat_level '
          'INTEGER NOT NULL DEFAULT 0',
        );
      } catch (e) {
        debugPrint('[DB] v74 heat_level: $e (repair re-checks)');
      }
    }
  }
}
