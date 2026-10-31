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

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/backup/backup_manifest.dart';
import 'package:front_porch_ai/services/backup/settings_snapshot.dart';

/// Writes a `.fpbackup` archive: the manifest, a consistent snapshot of the
/// database, every setting, and the user's own files below the storage root
/// (characters, pictures, worlds, voices, stories). Models, engines and
/// caches are left out; see [kBackupSkippedDirs].
class FullBackupWriter {
  FullBackupWriter({
    required this.root,
    required this.prefs,
    required this.nightly,
    required this.appVersion,
    required this.schemaVersion,
    required this.snapshotDatabase,
  });

  final String root;
  final SharedPreferences prefs;
  final bool nightly;
  final String appVersion;
  final int schemaVersion;

  /// Writes a transactionally consistent copy of the live database to the
  /// given path and says whether it did.
  final Future<bool> Function(String path) snapshotDatabase;

  /// Writes the archive to [out]. It is built as `<out>.part` and renamed
  /// only once complete, so a failure never leaves a file that looks like a
  /// backup. [onFile] reports progress as files are added.
  Future<BackupManifest> write(
    File out, {
    required bool includeSecrets,
    void Function(int done, int total)? onFile,
  }) async {
    final files = await listUserFiles(exclude: out.path);
    final part = File('${out.path}.part');
    final dbTmp = File(
      p.join(
        Directory.systemTemp.path,
        'fpai_backup_${DateTime.now().microsecondsSinceEpoch}.db',
      ),
    );
    final manifest = BackupManifest(
      format: BackupManifest.currentFormat,
      appVersion: appVersion,
      schemaVersion: schemaVersion,
      nightly: nightly,
      created: DateTime.now(),
      hasSecrets: includeSecrets,
      fileCount: files.length,
    );
    final zip = ZipFileEncoder();
    var open = false;
    try {
      if (!await snapshotDatabase(dbTmp.path)) {
        throw const FileSystemException('the database could not be copied');
      }
      await part.parent.create(recursive: true);
      zip.create(part.path);
      open = true;
      zip.addArchiveFile(
        ArchiveFile.string(BackupManifest.entryName, manifest.encode()),
      );
      await zip.addFile(dbTmp, BackupManifest.databaseEntry);
      final settings = SettingsSnapshot.capture(
        prefs,
        isNightly: nightly,
        includeSecrets: includeSecrets,
        root: root,
      );
      zip.addArchiveFile(
        ArchiveFile.string(BackupManifest.settingsEntry, settings.encode()),
      );
      for (var i = 0; i < files.length; i++) {
        final rel = files[i];
        await zip.addFile(
          File(p.joinAll([root, ...p.posix.split(rel)])),
          '${BackupManifest.filesPrefix}$rel',
        );
        onFile?.call(i + 1, files.length);
      }
      await zip.close();
      open = false;
      await part.rename(out.path);
      return manifest;
    } catch (e) {
      debugPrint('[Backup] full backup failed: $e');
      if (open) {
        try {
          await zip.close();
        } catch (closeError) {
          debugPrint(
            '[Backup] could not close the partial archive: $closeError',
          );
        }
      }
      if (await part.exists()) await part.delete();
      rethrow;
    } finally {
      if (await dbTmp.exists()) await dbTmp.delete();
    }
  }

  /// Every file below [root] that belongs in a full backup, as
  /// `/`-separated paths relative to it, sorted.
  Future<List<String>> listUserFiles({String? exclude}) async {
    final dir = Directory(root);
    final out = <String>[];
    if (!await dir.exists()) return out;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (exclude != null && p.equals(entity.path, exclude)) continue;
      final rel = p.relative(entity.path, from: root).replaceAll('\\', '/');
      if (includeInFullBackup(rel)) out.add(rel);
    }
    out.sort();
    return out;
  }
}
