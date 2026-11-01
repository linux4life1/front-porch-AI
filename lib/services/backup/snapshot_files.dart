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

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/backup/backup_manifest.dart';
import 'package:front_porch_ai/services/backup/full_backup_writer.dart';

/// One user file an automatic snapshot holds.
class SnapshotFile {
  const SnapshotFile(this.path, this.sha256, this.size);

  /// `/`-separated, below the storage root.
  final String path;
  final String sha256;
  final int size;
}

/// The user's files (portraits, pictures, worlds, voices, stories) that
/// travel with each automatic snapshot, the same set a full backup carries.
///
/// Snapshots run every 30 minutes, so each file is stored once, named by
/// its SHA-256, in `KoboldManager/backups/file_store/`, and every snapshot
/// keeps a list (`<snapshot>.userfiles.json`) of the files it holds. A
/// snapshot only copies what changed since the last one. A stored file is
/// removed once no snapshot (and no waiting restore) lists it.
///
/// Like the settings sidecar, KoboldCpp presets are stored with their keys
/// blanked, since the storage folder is often cloud-synced; a restore keeps
/// this machine's own preset keys.
class SnapshotFiles {
  SnapshotFiles(this.root, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final String root;
  final DateTime Function() _now;

  static const int format = 1;
  static const String listSuffix = '.userfiles.json';

  /// A stored file this new is never removed, so one a snapshot is still
  /// writing (its list not yet saved) survives a cleanup running beside it.
  static const Duration cleanupGrace = Duration(hours: 1);

  String get backupsDir => p.join(root, 'KoboldManager', 'backups');
  String get storeDir => p.join(backupsDir, 'file_store');
  String get _indexPath => p.join(storeDir, 'index.json');

  /// The list of files that travels with the snapshot at [snapshotDb].
  static String listPathFor(String snapshotDb) =>
      '${p.withoutExtension(snapshotDb)}$listSuffix';

  /// Where the stored copy of a file with [sha] lives.
  String blobPath(String sha) => p.join(storeDir, sha.substring(0, 2), sha);

  /// Stores the user's files for the snapshot at [snapshotDb] and writes
  /// its list (none when there are no files). Returns how many it holds.
  /// Runs off the UI isolate.
  Future<int> capture(String snapshotDb) {
    final root = this.root;
    final list = listPathFor(snapshotDb);
    final stamp = _now().toUtc().toIso8601String();
    return Isolate.run(() => SnapshotFiles(root)._captureSync(list, stamp));
  }

  int _captureSync(String listPath, String stamp) {
    Directory(storeDir).createSync(recursive: true);
    final index = _readIndex();
    final nextIndex = <String, Object?>{};
    final files = <Map<String, Object?>>[];
    for (final rel in userFiles(root)) {
      final file = File(p.joinAll([root, ...p.posix.split(rel)]));
      final FileStat stat;
      try {
        stat = file.statSync();
      } catch (e) {
        debugPrint('[Backup] skipped $rel: $e');
        continue;
      }
      if (stat.type != FileSystemEntityType.file) continue;
      final mtime = stat.modified.millisecondsSinceEpoch;
      final known = index[rel];
      String? sha;
      int? size;
      if (known is List &&
          known.length == 4 &&
          known[0] == stat.size &&
          known[1] == mtime &&
          File(blobPath('${known[2]}')).existsSync()) {
        sha = '${known[2]}';
        size = known[3] as int;
      } else {
        try {
          (sha, size) = _store(file, rel);
        } catch (e) {
          debugPrint('[Backup] could not keep $rel with the snapshot: $e');
          continue;
        }
      }
      nextIndex[rel] = [stat.size, mtime, sha, size];
      files.add({'path': rel, 'sha256': sha, 'size': size});
    }
    _writeAtomic(_indexPath, jsonEncode(nextIndex));
    // No list when there is nothing to put back: the row then reads as
    // the library (and settings) alone, which is what it holds.
    if (files.isNotEmpty) {
      _writeAtomic(
        listPath,
        jsonEncode({'format': format, 'created': stamp, 'files': files}),
      );
    }
    return files.length;
  }

  /// Copies [file] into the store and returns its hash and stored size.
  /// The copy is hashed, not the original, so what is stored always
  /// matches its name even when the file changes while it is copied.
  (String, int) _store(File file, String rel) {
    final tmp = File(
      p.join(storeDir, 'incoming-${_now().microsecondsSinceEpoch}.tmp'),
    );
    try {
      file.copySync(tmp.path);
      if (rel.toLowerCase().endsWith('.kcpps')) {
        final scrubbed = FullBackupWriter.presetTextWithoutKeys(
          tmp.readAsStringSync(),
          rel,
        );
        if (scrubbed != null) tmp.writeAsStringSync(scrubbed, flush: true);
      }
      final sha = hashOf(tmp);
      final size = tmp.lengthSync();
      final blob = File(blobPath(sha));
      if (blob.existsSync()) {
        tmp.deleteSync();
      } else {
        blob.parent.createSync(recursive: true);
        tmp.renameSync(blob.path);
        // Marks it new for [cleanupGrace]; a copy can keep the source's time.
        blob.setLastModifiedSync(_now());
      }
      return (sha, size);
    } finally {
      if (tmp.existsSync()) tmp.deleteSync();
    }
  }

  Map<String, Object?> _readIndex() {
    try {
      final f = File(_indexPath);
      if (!f.existsSync()) return const {};
      final doc = jsonDecode(f.readAsStringSync());
      return doc is Map<String, Object?> ? doc : const {};
    } catch (e) {
      // Only a speed-up: every file is hashed again.
      debugPrint('[Backup] file store index unreadable, rebuilding: $e');
      return const {};
    }
  }

  static void _writeAtomic(String path, String text) {
    final tmp = File('$path.tmp');
    tmp.writeAsStringSync(text, flush: true);
    tmp.renameSync(path);
  }

  /// SHA-256 of [file], read in chunks.
  static String hashOf(File file) {
    final out = _DigestSink();
    final input = sha256.startChunkedConversion(out);
    final raf = file.openSync();
    try {
      while (true) {
        final chunk = raf.readSync(1 << 20);
        if (chunk.isEmpty) break;
        input.add(chunk);
      }
    } finally {
      raf.closeSync();
    }
    input.close();
    return out.value.toString();
  }

  /// Every file below [root] that a backup carries, `/`-separated and
  /// sorted. The same rule as a full backup ([includeInFullBackup]).
  static List<String> userFiles(String root) {
    final dir = Directory(root);
    final out = <String>[];
    if (!dir.existsSync()) return out;
    for (final e in dir.listSync(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = p.relative(e.path, from: root).replaceAll('\\', '/');
      if (includeInFullBackup(rel)) out.add(rel);
    }
    out.sort();
    return out;
  }

  /// The files the list at [listPath] holds. Throws [FormatException]
  /// when it cannot be read.
  static Future<List<SnapshotFile>> readList(String listPath) async {
    final Object? doc;
    try {
      doc = jsonDecode(await File(listPath).readAsString());
    } catch (e) {
      throw FormatException('the snapshot\'s file list is unreadable: $e');
    }
    if (doc is! Map || doc['files'] is! List) {
      throw const FormatException('the snapshot\'s file list is unreadable');
    }
    final fmt = doc['format'];
    if (fmt is int && fmt > format) {
      throw const FormatException(
        'This snapshot was made by a newer Front Porch AI. Update the app, '
        'then restore it.',
      );
    }
    return [
      for (final f in doc['files'] as List)
        if (f is Map &&
            f['path'] is String &&
            f['sha256'] is String &&
            '${f['sha256']}'.length == 64)
          SnapshotFile(
            f['path'] as String,
            f['sha256'] as String,
            f['size'] is int ? f['size'] as int : 0,
          ),
    ];
  }

  /// Removes stored files that no snapshot lists. [alsoKeep] are further
  /// lists to honour (a restore waiting for the next launch). Nothing is
  /// removed when any list cannot be read.
  Future<void> cleanUp({List<String> alsoKeep = const []}) async {
    final store = Directory(storeDir);
    if (!await store.exists()) return;
    final keep = <String>{};
    final lists = [
      await for (final e in Directory(backupsDir).list())
        if (e is File && e.path.endsWith(listSuffix)) e.path,
      for (final extra in alsoKeep)
        if (await File(extra).exists()) extra,
    ];
    for (final list in lists) {
      try {
        keep.addAll((await readList(list)).map((f) => f.sha256));
      } on FormatException catch (e) {
        debugPrint('[Backup] file store cleanup skipped, $list: $e');
        return;
      }
    }
    final cutoff = _now().subtract(cleanupGrace);
    await for (final e in store.list(recursive: true)) {
      if (e is! File || p.basename(e.path) == p.basename(_indexPath)) {
        continue;
      }
      final name = p.basename(e.path);
      if (keep.contains(name)) continue;
      try {
        if ((await e.lastModified()).isAfter(cutoff)) continue;
        await e.delete();
      } catch (err) {
        debugPrint('[Backup] could not remove stored file $name: $err');
      }
    }
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
