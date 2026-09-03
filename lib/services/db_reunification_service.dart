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
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/db_reunification_insert.dart';

/// Result of diffing the old stable DB against the (now-primary) beta DB.
/// Contains lists of items that exist ONLY in the old stable DB.
class ReunificationDiff {
  final List<StableOnlyCharacter> characters;
  final List<String> groups; // group names
  final List<String> personas; // persona names
  final List<String> worlds; // world names

  bool get isEmpty =>
      characters.isEmpty &&
      groups.isEmpty &&
      personas.isEmpty &&
      worlds.isEmpty;

  int get totalItems =>
      characters.length + groups.length + personas.length + worlds.length;

  ReunificationDiff({
    required this.characters,
    required this.groups,
    required this.personas,
    required this.worlds,
  });
}

/// A character found only in the stable DB (not in beta).
class StableOnlyCharacter {
  final String id;
  final String name;
  final String? imagePath;
  final int sessionCount;

  StableOnlyCharacter({
    required this.id,
    required this.name,
    this.imagePath,
    this.sessionCount = 0,
  });
}

/// One-time service that reunifies the split beta/stable databases
/// on the first launch of 0.9.0 stable.
///
/// Strategy:
///   1. Back up both DBs
///   2. Promote beta DB → production DB (beta has correct schema + user's recent work)
///   3. Open the old stable backup, migrate it to v4 in a temp file
///   4. Diff: find items in stable that don't exist in beta (by imagePath/name)
///   5. Import selected stable-only items into the primary DB
class DbReunificationService {
  static const _prefsKey = 'reunification_complete';
  static const _backupSuffix = '.pre-0.9.0-backup';

  /// Check if the reunification has already been completed.
  static Future<bool> isComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKey) ?? false;
  }

  /// Mark the reunification as complete so it never runs again.
  static Future<void> markComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
    debugPrint('[Reunification] Marked as complete');
  }

  /// Check if both DBs exist and reunification hasn't been completed yet.
  static Future<bool> needsReunification(String dbDir) async {
    if (await isComplete()) return false;
    final stableFile = File(p.join(dbDir, 'front_porch.db'));
    final betaFile = File(p.join(dbDir, 'front_porch_beta.db'));
    return stableFile.existsSync() && betaFile.existsSync();
  }

  /// Step 1: Back up both DB files to .pre-0.9.0-backup copies.
  /// These backups are NEVER modified by subsequent steps.
  static Future<void> createBackups(String dbDir) async {
    final stableFile = File(p.join(dbDir, 'front_porch.db'));
    final betaFile = File(p.join(dbDir, 'front_porch_beta.db'));

    if (stableFile.existsSync()) {
      final backupPath = '${stableFile.path}$_backupSuffix';
      if (!File(backupPath).existsSync()) {
        await stableFile.copy(backupPath);
        debugPrint('[Reunification] Backed up stable DB → $backupPath');
      }
    }

    if (betaFile.existsSync()) {
      final backupPath = '${betaFile.path}$_backupSuffix';
      if (!File(backupPath).existsSync()) {
        await betaFile.copy(backupPath);
        debugPrint('[Reunification] Backed up beta DB → $backupPath');
      }
    }
  }

  /// Step 2: Promote beta DB → production DB.
  /// Copies front_porch_beta.db → front_porch.db (overwriting the old stable DB).
  static Future<void> promoteBetaDb(String dbDir) async {
    final betaFile = File(p.join(dbDir, 'front_porch_beta.db'));
    final stablePath = p.join(dbDir, 'front_porch.db');

    if (!betaFile.existsSync()) {
      debugPrint('[Reunification] No beta DB found — skipping promotion');
      return;
    }

    await betaFile.copy(stablePath);
    // Delete the beta DB so this can't re-trigger on subsequent launches.
    // The backup copy (front_porch_beta.db.pre-0.9.0-backup) is preserved.
    await betaFile.delete();
    debugPrint(
      '[Reunification] Promoted beta DB → front_porch.db (beta file removed)',
    );

    // Also clean up any WAL/SHM files from the old stable DB
    try {
      await File('$stablePath-wal').delete();
    } catch (_) {}
    try {
      await File('$stablePath-shm').delete();
    } catch (_) {}
  }

  /// Step 3: Diff the old stable backup against the now-primary (beta) DB.
  /// Returns a [ReunificationDiff] listing all items that exist ONLY in stable.
  ///
  /// The old stable DB backup is opened in a temp copy, migrated to v4 by Drift,
  /// then compared against the primary DB by stable identifiers (imagePath, name).
  static Future<ReunificationDiff> diffStableOnly(
    AppDatabase primaryDb,
    String dbDir, {
    bool dryRun = false,
  }) async {
    final stableBackupPath = p.join(dbDir, 'front_porch.db$_backupSuffix');
    final stableBackup = File(stableBackupPath);

    if (!stableBackup.existsSync()) {
      debugPrint('[Reunification] No stable backup found — nothing to diff');
      return ReunificationDiff(
        characters: [],
        groups: [],
        personas: [],
        worlds: [],
      );
    }

    // Copy to a temp file so Drift can migrate it without touching the backup
    final tempDir = await Directory.systemTemp.createTemp('fp_reunify_');
    final tempPath = p.join(tempDir.path, 'stable_migrated.db');
    await stableBackup.copy(tempPath);

    // Open with Drift — this will run migrations (v1→v4) on the temp copy
    // Suppress the "multiple databases" warning since we're intentionally
    // opening a separate file for diffing, not sharing a QueryExecutor.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final tempDb = AppDatabase.forReunification(File(tempPath));

    try {
      // Wait for the DB to be ready (migrations run during first query)
      await tempDb.customSelect('SELECT 1').get();

      // ── Diff Characters by imagePath ──
      final primaryChars = await primaryDb
          .customSelect('SELECT * FROM characters WHERE deleted_at IS NULL')
          .get();
      final stableChars = await tempDb
          .customSelect('SELECT * FROM characters WHERE deleted_at IS NULL')
          .get();

      final primaryImagePaths = <String>{};
      for (final row in primaryChars) {
        final ip = row.readNullable<String>('image_path');
        if (ip != null && ip.isNotEmpty) primaryImagePaths.add(ip);
      }

      final stableOnlyCharacters = <StableOnlyCharacter>[];
      for (final row in stableChars) {
        final ip = row.readNullable<String>('image_path');
        if (ip != null && ip.isNotEmpty && !primaryImagePaths.contains(ip)) {
          // Skip characters whose PNG file no longer exists on disk —
          // without an image file, the app can't display the character.
          if (!File(ip).existsSync()) {
            debugPrint(
              '[Reunification] Skipping ${row.read<String>('name')} — PNG missing: $ip',
            );
            continue;
          }

          // Count sessions for this character
          final charId = row.read<String>('id');
          final sessionRows = await tempDb
              .customSelect(
                'SELECT COUNT(*) AS cnt FROM sessions WHERE character_id = ? AND deleted_at IS NULL',
                variables: [Variable(charId)],
              )
              .get();
          final sessionCount = sessionRows.isNotEmpty
              ? sessionRows.first.read<int>('cnt')
              : 0;

          stableOnlyCharacters.add(
            StableOnlyCharacter(
              id: charId,
              name: row.read<String>('name'),
              imagePath: ip,
              sessionCount: sessionCount,
            ),
          );
        }
      }

      // ── Diff Groups by name ──
      final primaryGroups = await primaryDb
          .customSelect('SELECT name FROM groups WHERE deleted_at IS NULL')
          .get();
      final stableGroups = await tempDb
          .customSelect('SELECT name FROM groups WHERE deleted_at IS NULL')
          .get();

      final primaryGroupNames = primaryGroups
          .map((r) => r.read<String>('name'))
          .toSet();
      final stableOnlyGroups = stableGroups
          .map((r) => r.read<String>('name'))
          .where((n) => !primaryGroupNames.contains(n))
          .toList();

      // ── Diff Personas by name ──
      final primaryPersonas = await primaryDb
          .customSelect('SELECT name FROM personas WHERE deleted_at IS NULL')
          .get();
      final stablePersonas = await tempDb
          .customSelect('SELECT name FROM personas WHERE deleted_at IS NULL')
          .get();

      final primaryPersonaNames = primaryPersonas
          .map((r) => r.read<String>('name'))
          .toSet();
      final stableOnlyPersonas = stablePersonas
          .map((r) => r.read<String>('name'))
          .where((n) => !primaryPersonaNames.contains(n))
          .toList();

      // ── Diff Worlds by name ──
      final primaryWorlds = await primaryDb
          .customSelect('SELECT name FROM worlds WHERE deleted_at IS NULL')
          .get();
      final stableWorlds = await tempDb
          .customSelect('SELECT name FROM worlds WHERE deleted_at IS NULL')
          .get();

      final primaryWorldNames = primaryWorlds
          .map((r) => r.read<String>('name'))
          .toSet();
      final stableOnlyWorlds = stableWorlds
          .map((r) => r.read<String>('name'))
          .where((n) => !primaryWorldNames.contains(n))
          .toList();

      final diff = ReunificationDiff(
        characters: stableOnlyCharacters,
        groups: stableOnlyGroups,
        personas: stableOnlyPersonas,
        worlds: stableOnlyWorlds,
      );

      // Log results
      if (dryRun) {
        debugPrint('[Reunification] DRY RUN — would import:');
      } else {
        debugPrint('[Reunification] Diff results:');
      }
      debugPrint(
        '  Characters: ${stableOnlyCharacters.length} (${stableOnlyCharacters.map((c) => c.name).join(', ')})',
      );
      debugPrint(
        '  Groups: ${stableOnlyGroups.length} (${stableOnlyGroups.join(', ')})',
      );
      debugPrint(
        '  Personas: ${stableOnlyPersonas.length} (${stableOnlyPersonas.join(', ')})',
      );
      debugPrint(
        '  Worlds: ${stableOnlyWorlds.length} (${stableOnlyWorlds.join(', ')})',
      );

      return diff;
    } finally {
      await tempDb.close();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Step 4: Import stable-only items into the primary DB.
  /// For each character imported, also imports all its sessions and messages.
  static Future<void> importStableItems(
    AppDatabase primaryDb,
    String dbDir,
    ReunificationDiff diff,
  ) async {
    final stableBackupPath = p.join(dbDir, 'front_porch.db$_backupSuffix');
    final stableBackup = File(stableBackupPath);

    if (!stableBackup.existsSync()) {
      debugPrint('[Reunification] No stable backup — cannot import');
      return;
    }

    // Open the migrated stable backup in a temp copy
    final tempDir = await Directory.systemTemp.createTemp('fp_import_');
    final tempPath = p.join(tempDir.path, 'stable_migrated.db');
    await stableBackup.copy(tempPath);

    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final tempDb = AppDatabase.forReunification(File(tempPath));

    try {
      await tempDb.customSelect('SELECT 1').get();

      // ── Import Characters + their Sessions + Messages ──
      for (final charInfo in diff.characters) {
        debugPrint(
          '[Reunification] Importing character: ${charInfo.name} (${charInfo.id})',
        );

        // Read full character row from stable
        final charRows = await tempDb
            .customSelect(
              'SELECT * FROM characters WHERE id = ?',
              variables: [Variable(charInfo.id)],
            )
            .get();

        if (charRows.isEmpty) continue;
        final charRow = charRows.first;

        // Insert character into primary DB
        await insertRowFromQuery(primaryDb, 'characters', charRow);

        // Import all sessions for this character
        final sessions = await tempDb
            .customSelect(
              'SELECT * FROM sessions WHERE character_id = ? AND deleted_at IS NULL',
              variables: [Variable(charInfo.id)],
            )
            .get();

        for (final session in sessions) {
          final sessionId = session.read<String>('id');
          await insertRowFromQuery(primaryDb, 'sessions', session);

          // Import all messages for this session
          final messages = await tempDb
              .customSelect(
                'SELECT * FROM messages WHERE session_id = ? AND deleted_at IS NULL',
                variables: [Variable(sessionId)],
              )
              .get();

          for (final message in messages) {
            await insertRowFromQuery(primaryDb, 'messages', message);
          }

          debugPrint(
            '[Reunification]   Session $sessionId: ${messages.length} messages',
          );
        }

        debugPrint(
          '[Reunification]   Imported ${sessions.length} sessions for ${charInfo.name}',
        );
      }

      // ── Import Groups ──
      for (final groupName in diff.groups) {
        final rows = await tempDb
            .customSelect(
              'SELECT * FROM groups WHERE name = ? AND deleted_at IS NULL',
              variables: [Variable(groupName)],
            )
            .get();

        for (final row in rows) {
          await insertRowFromQuery(primaryDb, 'groups', row);

          final groupId = row.read<String>('id');
          final members = await tempDb
              .customSelect(
                'SELECT * FROM group_members WHERE group_id = ?',
                variables: [Variable(groupId)],
              )
              .get();
          for (final member in members) {
            await insertRowFromQuery(primaryDb, 'group_members', member);
          }

          // Import sessions for this group
          final sessions = await tempDb
              .customSelect(
                'SELECT * FROM sessions WHERE group_id = ? AND deleted_at IS NULL',
                variables: [Variable(groupId)],
              )
              .get();

          for (final session in sessions) {
            final sessionId = session.read<String>('id');
            await insertRowFromQuery(primaryDb, 'sessions', session);

            final messages = await tempDb
                .customSelect(
                  'SELECT * FROM messages WHERE session_id = ? AND deleted_at IS NULL',
                  variables: [Variable(sessionId)],
                )
                .get();

            for (final message in messages) {
              await insertRowFromQuery(primaryDb, 'messages', message);
            }
          }
        }
        debugPrint('[Reunification] Imported group: $groupName');
      }

      // ── Import Personas ──
      for (final personaName in diff.personas) {
        final rows = await tempDb
            .customSelect(
              'SELECT * FROM personas WHERE name = ? AND deleted_at IS NULL',
              variables: [Variable(personaName)],
            )
            .get();

        for (final row in rows) {
          await insertRowFromQuery(primaryDb, 'personas', row);
        }
        debugPrint('[Reunification] Imported persona: $personaName');
      }

      // ── Import Worlds ──
      for (final worldName in diff.worlds) {
        final rows = await tempDb
            .customSelect(
              'SELECT * FROM worlds WHERE name = ? AND deleted_at IS NULL',
              variables: [Variable(worldName)],
            )
            .get();

        for (final row in rows) {
          await insertRowFromQuery(primaryDb, 'worlds', row);
        }
        debugPrint('[Reunification] Imported world: $worldName');
      }

      // Bump sync version after import
      await primaryDb.bumpSyncVersion();
      debugPrint('[Reunification] Import complete');
    } finally {
      await tempDb.close();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }
}
