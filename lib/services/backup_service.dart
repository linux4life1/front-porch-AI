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

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:front_porch_ai/database/database.dart';

/// Creates timestamped backups of the SQLite database (now the primary safety
/// net, since cloud sync is deprecated). Auto-backup runs every 30 minutes and
/// is always on. Retention is two-tier rolling (see [pruneBackups]):
///   • Recent: always keep the newest [maxBackups] snapshots (~5h at this cadence).
///   • Daily:  also keep the most-recent snapshot of each of the last
///     [dailyRetentionDays] calendar days, so a backup survives a full rolling
///     week even after the recent window has scrolled past it.
class BackupService {
  /// Recent rolling tier: the newest this-many snapshots are always kept.
  static const int maxBackups = 10;

  /// Daily tier: additionally keep ONE backup per calendar day for the last
  /// this-many days (a rolling week of dailies on top of the recent snapshots).
  static const int dailyRetentionDays = 7;

  static const Duration _autoBackupInterval = Duration(minutes: 30);
  static const String _backupDir = 'backups';
  static Timer? _autoBackupTimer;

  /// Start the automatic backup timer (every 30 minutes).
  /// Safe to call multiple times — will not create duplicate timers.
  static void startAutoBackup() {
    if (_autoBackupTimer != null) return;
    debugPrint(
      '[Backup] Auto-backup started (every ${_autoBackupInterval.inMinutes} minutes)',
    );
    _autoBackupTimer = Timer.periodic(_autoBackupInterval, (_) async {
      try {
        final created = await createBackup();
        // Never prune after a failed snapshot: the daily-retention window
        // keeps sliding, so pruning during a persistent failure streak would
        // slowly delete healthy history while writing nothing new.
        if (created != null) await pruneBackups();
      } catch (e) {
        debugPrint('[Backup] Auto-backup failed: $e');
      }
    });
  }

  /// Stop the automatic backup timer.
  static void stopAutoBackup() {
    _autoBackupTimer?.cancel();
    _autoBackupTimer = null;
  }

  /// Get the backup directory path (creates it if needed).
  static Future<Directory> _getBackupDir() async {
    final dbPath = AppDatabase.dbFilePath;
    if (dbPath == null) throw StateError('Database path not initialized');
    final parentDir = path.dirname(dbPath); // .../KoboldManager/
    final backupDir = Directory(path.join(parentDir, _backupDir));
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    return backupDir;
  }

  /// Snapshot the current DB to a timestamped backup file.
  /// Returns the backup path, or null if the DB doesn't exist.
  static Future<String?> createBackup() async {
    final dbPath = AppDatabase.dbFilePath;
    if (dbPath == null) return null;

    final dbFile = File(dbPath);
    if (!await dbFile.exists()) return null;

    final backupDir = await _getBackupDir();
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final backupPath = path.join(backupDir.path, 'front_porch_$timestamp.db');

    // VACUUM INTO makes SQLite itself write a transactionally-consistent
    // snapshot. The old File.copy of the live DB could catch a mid-write
    // moment (the DB runs in rollback-journal mode, so writes mutate the
    // file in place) and produce a torn, unrestorable backup — discovered
    // only at restore time, after the primary DB has already failed.
    try {
      final db = await AppDatabase.instance();
      await db.customStatement(
        "VACUUM INTO '${backupPath.replaceAll("'", "''")}'",
      );
    } catch (e) {
      debugPrint('[Backup] VACUUM INTO failed — no backup written: $e');
      // Never fall back to a raw copy of the live file: a torn copy silently
      // poisons the safety net. Remove any partial target and report failure.
      try {
        final partial = File(backupPath);
        if (await partial.exists()) await partial.delete();
      } catch (_) {}
      return null;
    }
    debugPrint('[Backup] Created backup: $backupPath');
    return backupPath;
  }

  /// List available backups (newest first).
  static Future<List<File>> listBackups() async {
    try {
      final backupDir = await _getBackupDir();
      final files = <File>[];
      await for (final entity in backupDir.list()) {
        if (entity is File && entity.path.endsWith('.db')) {
          files.add(entity);
        }
      }
      // Sort by modified time, newest first
      files.sort((a, b) {
        final aStat = a.statSync();
        final bStat = b.statSync();
        return bStat.modified.compareTo(aStat.modified);
      });
      return files;
    } catch (_) {
      return [];
    }
  }

  /// Restore a specific backup (replaces the live DB).
  /// The caller MUST close and reopen the database after calling this.
  static Future<void> restoreBackup(String backupPath) async {
    final dbPath = AppDatabase.dbFilePath;
    if (dbPath == null) throw StateError('Database path not initialized');

    final backupFile = File(backupPath);
    if (!await backupFile.exists()) {
      throw FileSystemException('Backup file not found', backupPath);
    }

    // Close the live DB
    await AppDatabase.closeAndReset();

    // Replace with backup
    await backupFile.copy(dbPath);
    // Remove stale WAL/SHM
    try {
      await File('$dbPath-wal').delete();
    } catch (_) {}
    try {
      await File('$dbPath-shm').delete();
    } catch (_) {}

    debugPrint('[Backup] Restored backup from: $backupPath');
  }

  /// Two-tier rolling retention. A backup is kept if it satisfies EITHER rule:
  ///   • Recent: it is among the newest [maxBackups] snapshots.
  ///   • Daily:  it is the most-recent snapshot of one of the last
  ///     [dailyRetentionDays] calendar days (today counts as day 0).
  /// Everything else is deleted. This gives fine-grained recent history plus a
  /// rolling week of daily restore points without unbounded growth. The pure
  /// policy lives in [backupsToKeep] (filesystem-free, unit-tested); this method
  /// just supplies the file data and deletes the complement.
  static Future<void> pruneBackups() async {
    final backups = await listBackups(); // newest first (by mtime)
    if (backups.length <= maxBackups) return;

    final entries = [
      for (final f in backups) (path: f.path, modified: f.statSync().modified),
    ];
    final keep = backupsToKeep(entries, DateTime.now());

    for (final f in backups) {
      if (keep.contains(f.path)) continue;
      try {
        await f.delete();
        debugPrint('[Backup] Pruned old backup: ${f.path}');
      } catch (e) {
        debugPrint('[Backup] Failed to prune: $e');
      }
    }
  }

  /// Pure retention policy (no filesystem) — exposed for testing. Given backups
  /// as (path, modified) ordered NEWEST-FIRST and the current time [now], returns
  /// the set of paths to KEEP under the recent + daily rules described on
  /// [pruneBackups]. Order matters: the first entry seen for a day is treated as
  /// that day's most-recent snapshot.
  @visibleForTesting
  static Set<String> backupsToKeep(
    List<({String path, DateTime modified})> backupsNewestFirst,
    DateTime now,
  ) {
    final keep = <String>{};

    // Recent tier — the newest maxBackups snapshots.
    for (var i = 0;
        i < backupsNewestFirst.length && i < maxBackups;
        i++) {
      keep.add(backupsNewestFirst[i].path);
    }

    // Daily tier — one per calendar day for the last dailyRetentionDays days.
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final seenDays = <String>{};
    for (final b in backupsNewestFirst) {
      final mod = b.modified;
      final day = DateTime(mod.year, mod.month, mod.day);
      final ageDays = todayMidnight.difference(day).inDays;
      if (ageDays < 0 || ageDays >= dailyRetentionDays) {
        continue; // future-dated (clock skew) or older than the rolling week
      }
      if (seenDays.add('${day.year}-${day.month}-${day.day}')) {
        keep.add(b.path); // most-recent backup of this day
      }
    }

    return keep;
  }

  /// Delete ALL backups. Used during major schema upgrades (e.g. 0.9.0
  /// reunification) to prevent restoring old-schema backups that would corrupt
  /// the database.
  static Future<void> purgeAllBackups() async {
    final backups = await listBackups();
    for (final backup in backups) {
      try {
        await backup.delete();
        debugPrint('[Backup] Purged old backup: ${backup.path}');
      } catch (e) {
        debugPrint('[Backup] Failed to purge: $e');
      }
    }
    debugPrint('[Backup] Purged ${backups.length} old backups');
  }
}
