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

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/backup/backup_manifest.dart';
import 'package:front_porch_ai/services/backup/settings_snapshot.dart';

/// What a restore waiting for the next launch will put back.
enum PendingRestoreKind { full, snapshot, settings }

/// A restore staged for the next launch.
///
/// A restore that brings back settings or files cannot run under a live
/// app: every settings class, engine and open picture already holds the
/// old values and would write them straight back. So the backup is staged
/// in `<root>/KoboldManager/restore/` and [applyAtStartup] puts it back on
/// the next launch, after the settings store is healed and before the
/// database or any setting is read.
class PendingRestore {
  const PendingRestore(this.kind, this.staged, this.created);

  final PendingRestoreKind kind;

  /// When it was staged.
  final DateTime staged;

  /// When the backup itself was made.
  final DateTime created;

  static const String _marker = 'pending.json';
  static const String _archiveName = 'pending.fpbackup';
  static const String _settingsName = 'settings.json';
  static const String _snapshotName = 'snapshot.db';

  /// The result of the restore applied at this launch, for the notice
  /// after the first frame. Null when nothing was pending.
  static RestoreOutcome? lastOutcome;

  static Directory dirFor(String root) =>
      Directory(p.join(root, 'KoboldManager', 'restore'));

  /// Where the storage root and database file are before anything has
  /// opened them. Mirrors `AppDatabase.instance()`, which owns the rule.
  static Future<({String root, String dbFile})> startupLayout(
    SharedPreferences prefs, {
    required bool nightly,
  }) async {
    final saved = prefs.getString(nightly ? 'root_path_beta' : 'root_path');
    final root =
        saved ??
        p.join(
          (await getApplicationDocumentsDirectory()).path,
          nightly ? 'FrontPorchAI-Beta' : 'FrontPorchAI',
        );
    final dbName = nightly ? 'front_porch_beta.db' : 'front_porch.db';
    return (root: root, dbFile: p.join(root, 'KoboldManager', dbName));
  }

  /// The restore waiting under [root], or null.
  static Future<PendingRestore?> read(String root) async {
    final marker = File(p.join(dirFor(root).path, _marker));
    try {
      if (!await marker.exists()) return null;
      final doc = jsonDecode(await marker.readAsString()) as Map;
      return PendingRestore(
        PendingRestoreKind.values.firstWhere(
          (k) => k.name == doc['kind'],
          orElse: () => PendingRestoreKind.settings,
        ),
        DateTime.parse('${doc['staged']}').toLocal(),
        DateTime.parse('${doc['created']}').toLocal(),
      );
    } catch (e) {
      debugPrint('[Restore] pending restore marker unreadable: $e');
      return null;
    }
  }

  /// Drops the waiting restore, if any.
  static Future<void> cancel(String root) async {
    final dir = dirFor(root);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  static Future<void> _writeMarker(
    Directory dir,
    PendingRestoreKind kind,
    DateTime created,
  ) async {
    final tmp = File(p.join(dir.path, '$_marker.tmp'));
    await tmp.writeAsString(
      jsonEncode({
        'kind': kind.name,
        'staged': DateTime.now().toUtc().toIso8601String(),
        'created': created.toUtc().toIso8601String(),
      }),
      flush: true,
    );
    await tmp.rename(p.join(dir.path, _marker));
  }

  static Future<Directory> _freshDir(String root) async {
    await cancel(root);
    return dirFor(root).create(recursive: true);
  }

  /// Stages a snapshot's settings file for the next launch. Throws
  /// [FormatException] when it cannot be read.
  static Future<void> stageSettings(
    String root,
    File settings,
    DateTime created,
  ) async {
    SettingsSnapshot.decode(await settings.readAsString());
    final dir = await _freshDir(root);
    await settings.copy(p.join(dir.path, _settingsName));
    await _writeMarker(dir, PendingRestoreKind.settings, created);
  }

  /// Stages an automatic snapshot (its database, and its settings when it
  /// has them) for the next launch. The web app restores snapshots this way,
  /// since it cannot reload the desktop's open database in place.
  static Future<void> stageSnapshot(
    String root,
    File database,
    File? settings,
    DateTime created,
  ) async {
    if (settings != null) {
      SettingsSnapshot.decode(await settings.readAsString());
    }
    final dir = await _freshDir(root);
    await database.copy(p.join(dir.path, _snapshotName));
    if (settings != null) {
      await settings.copy(p.join(dir.path, _settingsName));
    }
    await _writeMarker(dir, PendingRestoreKind.snapshot, created);
  }

  /// Checks [archive] and stages it for the next launch. When [move] is
  /// true the file is moved (an upload already in the restore folder's
  /// disk) instead of copied. Throws [FormatException] with a message for
  /// the user when it cannot be restored.
  static Future<BackupManifest> stageFull(
    String root,
    File archive, {
    required int currentSchema,
    bool move = false,
  }) async {
    final manifest = await inspect(archive);
    final refusal = manifest.refusal(currentSchema: currentSchema);
    if (refusal != null) throw FormatException(refusal);
    final dir = await _freshDir(root);
    final target = p.join(dir.path, _archiveName);
    if (move) {
      await archive.rename(target);
    } else {
      await archive.copy(target);
    }
    await _writeMarker(dir, PendingRestoreKind.full, manifest.created);
    return manifest;
  }

  /// Reads the manifest of a `.fpbackup` file and checks it holds a
  /// database. Throws [FormatException] for anything else.
  static Future<BackupManifest> inspect(File archive) async {
    final input = InputFileStream(archive.path);
    try {
      final zip = ZipDecoder().decodeStream(input);
      final manifestEntry = zip.findFile(BackupManifest.entryName);
      if (manifestEntry == null ||
          zip.findFile(BackupManifest.databaseEntry) == null) {
        throw const FormatException('That file is not a Front Porch backup.');
      }
      return BackupManifest.decode(utf8.decode(manifestEntry.readBytes()!));
    } on FormatException {
      rethrow;
    } catch (e) {
      debugPrint('[Restore] could not read backup: $e');
      throw const FormatException('That file is not a Front Porch backup.');
    } finally {
      await input.close();
    }
  }

  /// Applies the restore waiting under [root], if any, and records the
  /// result in [lastOutcome]. Never throws: a restore that fails is
  /// dropped (its file kept for another try) so it cannot fail every launch.
  static Future<void> applyAtStartup({
    required String root,
    required String dbFile,
    required SharedPreferences prefs,
    required bool nightly,
    int? currentSchema,
  }) async {
    final pending = await read(root);
    if (pending == null) return;
    final dir = dirFor(root);
    try {
      final settingsFile = File(p.join(dir.path, _settingsName));
      if (pending.kind == PendingRestoreKind.snapshot) {
        await _replaceDatabase(File(p.join(dir.path, _snapshotName)), dbFile);
      }
      if (pending.kind != PendingRestoreKind.full) {
        if (await settingsFile.exists()) {
          await SettingsSnapshot.decode(
            await settingsFile.readAsString(),
          ).restoreInto(prefs, isNightly: nightly, newRoot: root);
        }
      } else {
        await _applyFull(
          File(p.join(dir.path, _archiveName)),
          root: root,
          dbFile: dbFile,
          prefs: prefs,
          nightly: nightly,
          currentSchema: currentSchema,
        );
      }
      await cancel(root);
      lastOutcome = RestoreOutcome(pending.kind, pending.created, null);
      debugPrint('[Restore] applied ${pending.kind.name} restore');
    } catch (e) {
      debugPrint('[Restore] restore failed: $e');
      lastOutcome = RestoreOutcome(pending.kind, pending.created, '$e');
      try {
        await File(p.join(dir.path, _marker)).delete();
      } catch (markerError) {
        debugPrint('[Restore] could not drop the restore marker: $markerError');
      }
    }
  }

  static Future<void> _applyFull(
    File archive, {
    required String root,
    required String dbFile,
    required SharedPreferences prefs,
    required bool nightly,
    int? currentSchema,
  }) async {
    final input = InputFileStream(archive.path);
    final dbTmp = File('$dbFile.restore.tmp');
    try {
      final zip = ZipDecoder().decodeStream(input);
      final manifestEntry = zip.findFile(BackupManifest.entryName);
      final dbEntry = zip.findFile(BackupManifest.databaseEntry);
      if (manifestEntry == null || dbEntry == null) {
        throw const FormatException('not a Front Porch backup');
      }
      final manifest = BackupManifest.decode(
        utf8.decode(manifestEntry.readBytes()!),
      );
      final refusal = currentSchema == null
          ? null
          : manifest.refusal(currentSchema: currentSchema);
      if (refusal != null) throw FormatException(refusal);
      final settingsEntry = zip.findFile(BackupManifest.settingsEntry);
      final settings = settingsEntry == null
          ? null
          : SettingsSnapshot.decode(utf8.decode(settingsEntry.readBytes()!));

      // Everything is checked before anything is replaced.
      await dbTmp.parent.create(recursive: true);
      await _extract(dbEntry, dbTmp.path);
      if (!await _looksLikeSqlite(dbTmp)) {
        throw const FormatException('the backup database is damaged');
      }

      for (final entry in zip.files) {
        if (!entry.isFile ||
            !entry.name.startsWith(BackupManifest.filesPrefix)) {
          continue;
        }
        final rel = entry.name.substring(BackupManifest.filesPrefix.length);
        final target = safeTarget(root, rel);
        if (target == null) {
          debugPrint('[Restore] skipped unsafe path ${entry.name}');
          continue;
        }
        await _extract(entry, target);
      }

      await dbTmp.rename(dbFile);
      await _dropJournals(dbFile);
      await settings?.restoreInto(prefs, isNightly: nightly, newRoot: root);
    } finally {
      await input.close();
      if (await dbTmp.exists()) await dbTmp.delete();
    }
  }

  static Future<void> _dropJournals(String dbFile) async {
    for (final suffix in const ['-wal', '-shm', '-journal']) {
      final stale = File('$dbFile$suffix');
      if (await stale.exists()) await stale.delete();
    }
  }

  static Future<void> _replaceDatabase(File source, String dbFile) async {
    if (!await _looksLikeSqlite(source)) {
      throw const FormatException('the snapshot database is damaged');
    }
    final tmp = File('$dbFile.restore.tmp');
    await tmp.parent.create(recursive: true);
    await source.copy(tmp.path);
    await tmp.rename(dbFile);
    await _dropJournals(dbFile);
  }

  /// Where [relative] lands below [root], or null for a path that would
  /// escape it or that a backup never carries.
  @visibleForTesting
  static String? safeTarget(String root, String relative) {
    final rel = relative.replaceAll('\\', '/');
    if (rel.isEmpty || rel.startsWith('/') || rel.contains(':')) return null;
    if (!includeInFullBackup(rel)) return null;
    final target = p.normalize(p.joinAll([root, ...p.posix.split(rel)]));
    return p.isWithin(root, target) ? target : null;
  }

  static Future<void> _extract(ArchiveFile entry, String target) async {
    await Directory(p.dirname(target)).create(recursive: true);
    final tmp = '$target.restore-part';
    final out = OutputFileStream(tmp);
    try {
      entry.writeContent(out);
    } finally {
      await out.close();
    }
    await File(tmp).rename(target);
  }

  static Future<bool> _looksLikeSqlite(File f) async {
    final raf = await f.open();
    try {
      final head = await raf.read(16);
      return utf8.decode(head, allowMalformed: true) == 'SQLite format 3\u0000';
    } finally {
      await raf.close();
    }
  }
}

/// How the restore applied at this launch went.
class RestoreOutcome {
  const RestoreOutcome(this.kind, this.backupCreated, this.error);

  final PendingRestoreKind kind;
  final DateTime backupCreated;

  /// Null when it worked.
  final String? error;
}
