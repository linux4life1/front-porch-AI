// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The versioned onCreate/onUpgrade migration ladder (schema v1 -> v52).
// EVERY `if (from < N)` block is byte-verbatim from the original
// migration getter. Editing any block is a user-data-corruption risk.
// Steps are split across sibling parts (v2–v26, v27–v39, v40–v52).

part of 'database.dart';

/// The versioned onCreate/onUpgrade migration ladder (schema v1 → v52).
/// EVERY `if (from < N)` block is byte-verbatim from the original
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
    await _upgradeThroughV26(m, from, to);
    await _upgradeV27toV39(m, from, to);
    await _upgradeFromV40(m, from, to);
  }
}
