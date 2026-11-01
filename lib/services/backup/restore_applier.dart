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
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/backup/backup_db_scrub.dart';
import 'package:front_porch_ai/services/backup/backup_manifest.dart';
import 'package:front_porch_ai/services/backup/full_backup_writer.dart';
import 'package:front_porch_ai/services/backup/settings_snapshot.dart';
import 'package:front_porch_ai/services/backup/snapshot_files.dart';
import 'package:front_porch_ai/services/prefs_recovery.dart';

/// Puts a staged restore back at launch, before the database is open.
///
/// Every apply starts with a safety copy of what it is about to replace,
/// taken now rather than when the restore was staged, so nothing done in
/// between is lost. The copy is an ordinary snapshot in the Backups list
/// (database plus settings), and every file the restore overwrites is moved
/// into a `<snapshot>.files` folder beside it. If the safety copy cannot be
/// made, nothing is restored.
///
/// A full restore is all or nothing: the whole archive is unpacked into a
/// staging folder and checked first, then moved into place; a failure while
/// moving puts back what was already moved. A restored database keeps this
/// machine's web login and signs every device out.
class RestoreApplier {
  RestoreApplier({
    required this.root,
    required this.dbFile,
    required this.prefs,
    required this.nightly,
    this.currentSchema,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final String root;
  final String dbFile;
  final SharedPreferences prefs;
  final bool nightly;
  final int? currentSchema;
  final DateTime Function() _now;

  /// Marks a safety copy's file name. Safety copies are kept apart from
  /// the automatic snapshots' retention (see BackupService.pruneBackups),
  /// so the undo for a restore is not pruned a few hours later.
  static const String safetySuffix = '_before_restore';

  static bool isSafetyCopy(String path) =>
      p.basenameWithoutExtension(path).endsWith(safetySuffix);

  /// Where snapshots live; the safety copy goes there too.
  String get backupsDir => p.join(root, 'KoboldManager', 'backups');

  /// The safety snapshot this apply took, once it has.
  String? safetyDb;

  String get _safetyFiles => '${p.withoutExtension(safetyDb!)}.files';

  /// Takes the safety copy. Throws when it cannot be made.
  Future<void> takeSafetyCopy() async {
    await Directory(backupsDir).create(recursive: true);
    final stamp = _now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final target = p.join(backupsDir, 'front_porch_$stamp$safetySuffix.db');
    final live = File(dbFile);
    if (await live.exists()) {
      // The database is not open yet, so a plain copy is consistent, as
      // long as a journal an earlier crash left beside it comes too: the
      // copy is opened once so SQLite folds it in.
      final tmp = File('$target.tmp');
      await live.copy(tmp.path);
      var journals = false;
      for (final suffix in const ['-wal', '-journal']) {
        final j = File('$dbFile$suffix');
        if (await j.exists()) {
          await j.copy('${tmp.path}$suffix');
          journals = true;
        }
      }
      if (journals) await BackupDbScrub.settle(tmp.path);
      await tmp.rename(target);
    }
    safetyDb = target;
    final settings = SettingsSnapshot.capture(
      prefs,
      isNightly: nightly,
      includeSecrets: false,
      root: root,
    );
    final sidecar = File('${p.withoutExtension(target)}.settings.json');
    final tmp = File('${sidecar.path}.tmp');
    await tmp.writeAsString(settings.encode(), flush: true);
    await tmp.rename(sidecar.path);
  }

  /// Puts back the database at [source], keeping this machine's login.
  Future<void> applyDatabase(File source) async {
    final tmp = File('$dbFile.restore.tmp');
    await tmp.parent.create(recursive: true);
    try {
      await source.copy(tmp.path);
      await _swapDatabase(tmp);
    } finally {
      if (await tmp.exists()) await tmp.delete();
    }
  }

  Future<void> _swapDatabase(File staged) async {
    if (!await looksLikeSqlite(staged)) {
      throw const FormatException('the backup database is damaged');
    }
    await BackupDbScrub.keepMachineLogin(staged.path, dbFile);
    await staged.rename(dbFile);
    for (final suffix in const ['-wal', '-shm', '-journal']) {
      final stale = File('$dbFile$suffix');
      if (await stale.exists()) await stale.delete();
    }
  }

  /// Puts back [snapshot]'s settings and refreshes the good copy, so a
  /// torn settings file after this heals to the restored settings.
  Future<void> applySettings(SettingsSnapshot snapshot) async {
    await snapshot.restoreInto(prefs, isNightly: nightly, newRoot: root);
    await PrefsRecovery.snapshotGood();
  }

  /// Applies a full backup. [targetFor] maps an archive path below
  /// `files/` to where it lands, or null to skip it.
  Future<void> applyFull(
    File archive,
    Directory staging,
    String? Function(String rel) targetFor,
  ) async {
    if (await staging.exists()) await staging.delete(recursive: true);
    final input = InputFileStream(archive.path);
    final placed = <({String target, String? saved})>[];
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
      final schema = currentSchema;
      final refusal = schema == null
          ? null
          : manifest.refusal(currentSchema: schema);
      if (refusal != null) throw FormatException(refusal);
      final settingsEntry = zip.findFile(BackupManifest.settingsEntry);
      final settings = settingsEntry == null
          ? null
          : SettingsSnapshot.decode(utf8.decode(settingsEntry.readBytes()!));

      // Unpack everything first. Until the moves below, the live tree is
      // untouched.
      final stagedDb = File(p.join(staging.path, 'database.db'));
      await _extract(dbEntry, stagedDb.path);
      if (!await looksLikeSqlite(stagedDb)) {
        throw const FormatException('the backup database is damaged');
      }
      final moves = <({String from, String to, String rel})>[];
      final seen = <String>{};
      for (final entry in zip.files) {
        if (!entry.isFile ||
            !entry.name.startsWith(BackupManifest.filesPrefix)) {
          continue;
        }
        final rel = entry.name.substring(BackupManifest.filesPrefix.length);
        final target = targetFor(rel);
        if (target == null || !seen.add(p.normalize(target))) {
          debugPrint('[Restore] skipped ${entry.name}');
          continue;
        }
        final from = p.join(staging.path, 'files', '${moves.length}');
        await _extract(entry, from);
        if (!manifest.hasSecrets) await _keepPresetKeys(from, target);
        moves.add((
          from: from,
          to: target,
          rel: p.relative(target, from: root),
        ));
      }
      await BackupDbScrub.keepMachineLogin(stagedDb.path, dbFile);
      await _place(moves, placed, stagedDb);
      if (settings != null) await applySettings(settings);
    } finally {
      await input.close();
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  /// Puts back the user's [files] an automatic snapshot holds, from
  /// [store], and [database] with them when given. All or nothing, like
  /// [applyFull]: every file is copied out of the store and checked against
  /// its hash before anything in the live tree moves.
  Future<void> applySnapshotFiles(
    List<SnapshotFile> files,
    SnapshotFiles store,
    Directory staging,
    String? Function(String rel) targetFor, {
    File? database,
  }) async {
    if (await staging.exists()) await staging.delete(recursive: true);
    final placed = <({String target, String? saved})>[];
    try {
      File? stagedDb;
      if (database != null) {
        stagedDb = File(p.join(staging.path, 'database.db'));
        await stagedDb.parent.create(recursive: true);
        await database.copy(stagedDb.path);
        if (!await looksLikeSqlite(stagedDb)) {
          throw const FormatException('the backup database is damaged');
        }
      }
      final moves = <({String from, String to, String rel})>[];
      final seen = <String>{};
      for (final f in files) {
        final target = targetFor(f.path);
        if (target == null || !seen.add(p.normalize(target))) {
          debugPrint('[Restore] skipped ${f.path}');
          continue;
        }
        if (await _sameAs(target, f)) continue;
        final blob = File(store.blobPath(f.sha256));
        if (!await blob.exists()) {
          throw FormatException('${f.path} is missing from that snapshot');
        }
        final from = p.join(staging.path, 'files', '${moves.length}');
        await Directory(p.dirname(from)).create(recursive: true);
        await blob.copy(from);
        if (await Isolate.run(() => SnapshotFiles.hashOf(File(from))) !=
            f.sha256) {
          throw FormatException('${f.path} is damaged in that snapshot');
        }
        await _keepPresetKeys(from, target);
        moves.add((
          from: from,
          to: target,
          rel: p.relative(target, from: root),
        ));
      }
      if (stagedDb != null) {
        await BackupDbScrub.keepMachineLogin(stagedDb.path, dbFile);
      }
      await _place(moves, placed, stagedDb);
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  /// Whether the live file at [target] already is [f], so the restore
  /// leaves it alone instead of setting the same bytes aside.
  static Future<bool> _sameAs(String target, SnapshotFile f) async {
    final live = File(target);
    if (!await live.exists() || await live.length() != f.size) return false;
    return await Isolate.run(() => SnapshotFiles.hashOf(File(target))) ==
        f.sha256;
  }

  /// Moves every staged file into place, saving what each replaces beside
  /// the safety copy, then swaps in [stagedDb] when given. A failure puts
  /// back what was already moved.
  Future<void> _place(
    List<({String from, String to, String rel})> moves,
    List<({String target, String? saved})> placed,
    File? stagedDb,
  ) async {
    try {
      for (final m in moves) {
        String? saved;
        if (await File(m.to).exists()) {
          saved = p.join(_safetyFiles, m.rel);
          await Directory(p.dirname(saved)).create(recursive: true);
          await File(m.to).rename(saved);
        }
        placed.add((target: m.to, saved: saved));
        await Directory(p.dirname(m.to)).create(recursive: true);
        await File(m.from).rename(m.to);
      }
      if (stagedDb != null) await _swapDatabase(stagedDb);
    } catch (e) {
      await _undo(placed);
      rethrow;
    }
  }

  /// A backup made without keys carries KoboldCpp presets with their keys
  /// blanked; the preset being replaced keeps its own.
  static Future<void> _keepPresetKeys(String staged, String target) async {
    if (!target.toLowerCase().endsWith('.kcpps')) return;
    final current = File(target);
    if (!await current.exists()) return;
    try {
      final mine = jsonDecode(await current.readAsString());
      final incoming = jsonDecode(await File(staged).readAsString());
      if (mine is! Map || incoming is! Map) return;
      var changed = false;
      for (final key in FullBackupWriter.presetSecretKeys) {
        final v = mine[key];
        if (v != null && v != '' && v != false) {
          incoming[key] = v;
          changed = true;
        }
      }
      if (changed) await File(staged).writeAsString(jsonEncode(incoming));
    } on FormatException catch (e) {
      debugPrint('[Restore] $target is not a readable preset: $e');
    }
  }

  Future<void> _undo(List<({String target, String? saved})> placed) async {
    for (final done in placed.reversed) {
      try {
        final target = File(done.target);
        if (await target.exists()) await target.delete();
        final saved = done.saved;
        if (saved != null) await File(saved).rename(done.target);
      } catch (e) {
        debugPrint('[Restore] could not put back ${done.target}: $e');
      }
    }
  }

  static Future<void> _extract(ArchiveFile entry, String target) async {
    await Directory(p.dirname(target)).create(recursive: true);
    final out = OutputFileStream(target);
    try {
      entry.writeContent(out);
    } finally {
      await out.close();
    }
  }

  static Future<bool> looksLikeSqlite(File f) async {
    final raf = await f.open();
    try {
      final head = await raf.read(16);
      return utf8.decode(head, allowMalformed: true) == 'SQLite format 3\u0000';
    } finally {
      await raf.close();
    }
  }
}
