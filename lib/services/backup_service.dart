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
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/backup/backup_manifest.dart';
import 'package:front_porch_ai/services/backup/full_backup_writer.dart';
import 'package:front_porch_ai/services/backup/pending_restore.dart';
import 'package:front_porch_ai/services/backup/settings_snapshot.dart';
import 'package:front_porch_ai/services/prefs_recovery.dart';

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
        await PrefsRecovery.snapshotGood();
      } catch (e) {
        debugPrint('[Backup] Auto-backup failed: $e');
      }
    });
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

    if (!await snapshotDatabaseTo(backupPath)) return null;
    await _writeSettingsSidecar(backupPath);
    debugPrint('[Backup] Created backup: $backupPath');
    return backupPath;
  }

  /// Writes a transactionally consistent copy of the live database to
  /// [target] and says whether it did.
  ///
  /// VACUUM INTO makes SQLite itself write the snapshot. A File.copy of the
  /// live DB could catch a mid-write moment (the DB runs in rollback-journal
  /// mode, so writes mutate the file in place) and produce a torn,
  /// unrestorable backup, discovered only at restore time.
  static Future<bool> snapshotDatabaseTo(String target) async {
    try {
      final db = await AppDatabase.instance();
      await db.customStatement("VACUUM INTO '${target.replaceAll("'", "''")}'");
      return true;
    } catch (e) {
      debugPrint('[Backup] VACUUM INTO failed, no backup written: $e');
      // Never fall back to a raw copy of the live file: a torn copy silently
      // poisons the safety net. Remove any partial target and report failure.
      try {
        final partial = File(target);
        if (await partial.exists()) await partial.delete();
      } catch (e) {
        debugPrint('[Backup] Could not remove partial backup: $e');
      }
      return false;
    }
  }

  /// The settings file that travels with the snapshot at [dbBackupPath].
  /// Snapshots from before settings were backed up have none.
  static String settingsPathFor(String dbBackupPath) =>
      '${path.withoutExtension(dbBackupPath)}.settings.json';

  /// The storage root the live database sits under.
  static String? get storageRoot {
    final dbPath = AppDatabase.dbFilePath;
    if (dbPath == null) return null;
    return path.dirname(path.dirname(dbPath));
  }

  /// Every setting, API keys included: an automatic snapshot never leaves
  /// this machine, which already keeps those keys in its settings file.
  /// A snapshot whose settings could not be written still keeps its
  /// database; the failure is logged and the list shows it as
  /// database only.
  static Future<void> _writeSettingsSidecar(String backupPath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final snapshot = SettingsSnapshot.capture(
        prefs,
        isNightly: isPreRelease,
        includeSecrets: true,
        root: storageRoot,
      );
      final target = settingsPathFor(backupPath);
      final tmp = File('$target.tmp');
      await tmp.writeAsString(snapshot.encode(), flush: true);
      await tmp.rename(target);
    } catch (e) {
      debugPrint('[Backup] settings were not saved with the snapshot: $e');
    }
  }

  /// Deletes a snapshot and the settings that travel with it.
  static Future<void> deleteBackup(File backup) async {
    await backup.delete();
    final settings = File(settingsPathFor(backup.path));
    if (await settings.exists()) await settings.delete();
  }

  /// The snapshots with what the list shows about each, newest first.
  static Future<List<BackupEntry>> listEntries() async {
    final out = <BackupEntry>[];
    for (final f in await listBackups()) {
      try {
        // Sync on purpose: a handful of stats, already off the build path
        // (listBackups sorts with statSync too).
        final stat = f.statSync();
        out.add(
          BackupEntry(
            f,
            stat.size,
            stat.modified.toLocal(),
            File(settingsPathFor(f.path)).existsSync(),
          ),
        );
      } catch (e) {
        debugPrint('[Backup] could not read ${f.path}: $e');
      }
    }
    return out;
  }

  /// Stages the settings saved with [entry] for the next launch.
  static Future<void> stageSnapshotSettings(BackupEntry entry) async {
    final root = storageRoot;
    if (root == null) throw StateError('Database path not initialized');
    await PendingRestore.stageSettings(
      root,
      File(settingsPathFor(entry.file.path)),
      entry.modified,
    );
  }

  /// Stages [entry] for the next launch: its database, and its settings
  /// when [withSettings] and it has them. The web app restores this way.
  static Future<void> stageSnapshotRestore(
    BackupEntry entry, {
    required bool withSettings,
  }) async {
    final root = storageRoot;
    if (root == null) throw StateError('Database path not initialized');
    await PendingRestore.stageSnapshot(
      root,
      entry.file,
      withSettings && entry.hasSettings
          ? File(settingsPathFor(entry.file.path))
          : null,
      entry.modified,
    );
  }

  /// Writes a full backup into [folder] and returns its path. Named by date
  /// so a second backup the same day does not replace the first.
  static Future<String> createFullBackup(
    String folder, {
    required bool includeSecrets,
    void Function(int done, int total)? onFile,
  }) async {
    final root = storageRoot;
    final db = AppDatabase.current ?? await AppDatabase.instance();
    if (root == null) throw StateError('Database path not initialized');
    final stamp = DateTime.now()
        .toIso8601String()
        .substring(0, 19)
        .replaceAll(':', '-')
        .replaceAll('T', '_');
    final channel = isPreRelease ? 'Rawhide-' : '';
    final out = File(
      path.join(
        folder,
        'FrontPorchAI-${channel}backup-$stamp${BackupManifest.fileExtension}',
      ),
    );
    final writer = FullBackupWriter(
      root: root,
      prefs: await SharedPreferences.getInstance(),
      nightly: isPreRelease,
      appVersion: appVersion,
      schemaVersion: db.schemaVersion,
      snapshotDatabase: snapshotDatabaseTo,
    );
    await writer.write(out, includeSecrets: includeSecrets, onFile: onFile);
    return out.path;
  }

  /// Checks [archive] and stages it for the next launch. Before it does, a
  /// fresh snapshot of the library as it is now is taken, so a restore can
  /// itself be undone. Throws [FormatException] with a message for the user.
  static Future<BackupManifest> stageFullRestore(
    File archive, {
    bool move = false,
  }) async {
    final root = storageRoot;
    final db = AppDatabase.current ?? await AppDatabase.instance();
    if (root == null) throw StateError('Database path not initialized');
    final manifest = await PendingRestore.inspect(archive);
    final refusal = manifest.refusal(currentSchema: db.schemaVersion);
    if (refusal != null) throw FormatException(refusal);
    await createBackup();
    return PendingRestore.stageFull(
      root,
      archive,
      currentSchema: db.schemaVersion,
      move: move,
    );
  }

  /// The restore waiting for the next launch, or null.
  static Future<PendingRestore?> pendingRestore() async {
    final root = storageRoot;
    return root == null ? null : PendingRestore.read(root);
  }

  /// Drops the restore waiting for the next launch.
  static Future<void> cancelPendingRestore() async {
    final root = storageRoot;
    if (root != null) await PendingRestore.cancel(root);
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
    } catch (e) {
      debugPrint('[Backup] Could not list backups: $e');
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
    for (final suffix in const ['-wal', '-shm']) {
      try {
        await File('$dbPath$suffix').delete();
      } on PathNotFoundException {
        // Nothing stale to remove.
      } catch (e) {
        debugPrint('[Backup] Could not remove stale $suffix file: $e');
      }
    }

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
        await deleteBackup(f);
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
    for (var i = 0; i < backupsNewestFirst.length && i < maxBackups; i++) {
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
}

/// One automatic snapshot as the Backups list shows it.
class BackupEntry {
  const BackupEntry(this.file, this.size, this.modified, this.hasSettings);

  final File file;
  final int size;
  final DateTime modified;

  /// Whether the snapshot carries settings. Snapshots from before settings
  /// were backed up are database only.
  final bool hasSettings;
}
