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
  }
}
