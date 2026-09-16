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
import 'package:path/path.dart' as path;

/// Everything that hangs directly off the storage root. `groups` and
/// `custom_backgrounds` are resolved LIVE from the root at render time (group
/// member portraits store a bare filename), so leaving them behind blanks
/// every group avatar and chat background the instant the root moves.
const kRootDirsToMove = [
  'KoboldManager',
  'chats',
  'worlds',
  'tools',
  'models',
  'koboldcpp_bin',
  'groups',
  'custom_backgrounds',
];

/// The MOVE half of a storage-root change: refuse-check, copy-everything,
/// roll back on failure, delete sources last. Pure directory work — the
/// commit half (prefs key, background repointing, notify) stays in
/// StorageService.setRootPath.
///
/// ALL OR NOTHING, and it reports. Every copy runs BEFORE any source is
/// deleted. A half-move the app then points at is indistinguishable from "my
/// whole library vanished": the DB path is `root/KoboldManager/front_porch.db`,
/// so committing a root whose data never arrived opens an empty database
/// while the real one sits under a folder the app no longer names.
///
/// A destination inside (or equal to) the current root is refused before
/// anything is copied. GTK on Linux sometimes returns a subdirectory of
/// the folder the picker is already sitting in; copying the library into
/// a child of itself and then deleting the sources splits the data.
///
/// Returns null on success, or a human-readable refusal — nothing was moved
/// and the old root still stands in that case.
Future<String?> relocateRootDirectories(String? oldRoot, String newRoot) async {
  if (oldRoot != null &&
      (path.equals(oldRoot, newRoot) || path.isWithin(oldRoot, newRoot))) {
    final reason =
        'The folder you picked is the current data directory or a folder '
        'inside it. Nothing was moved — pick a folder outside the current '
        'one.';
    debugPrint('[Storage] refusing root move to $newRoot: $reason');
    return reason;
  }

  final sources = <Directory>[];
  final targets = <Directory>[];
  for (final dirName in kRootDirsToMove) {
    final oldDir = Directory(path.join(oldRoot ?? '', dirName));
    if (!await oldDir.exists()) continue;
    final newDir = Directory(path.join(newRoot, dirName));
    // An EMPTY leftover at the destination is fine (the app creates these
    // dirs on any root it has ever been pointed at). Data already sitting
    // there is another install's — merging or clobbering it are both ways to
    // lose a library, so refuse the move instead.
    if (await newDir.exists() && !await newDir.list().isEmpty) {
      final reason =
          'The folder you picked already contains data in "$dirName". '
          'Nothing was moved — pick an empty folder, or move the existing '
          '"$dirName" out of the way first.';
      debugPrint('[Storage] refusing root move to $newRoot: $reason');
      return reason;
    }
    sources.add(oldDir);
    targets.add(newDir);
  }

  for (var i = 0; i < sources.length; i++) {
    try {
      await copyDirectoryRecursive(sources[i], targets[i]);
    } catch (e) {
      final name = path.basename(sources[i].path);
      debugPrint('[Storage] copying "$name" to $newRoot failed: $e');
      // Roll the partial copy back so a retry isn't blocked by the debris we
      // just made. The sources are all untouched — nothing is deleted until
      // every copy has landed.
      for (var j = 0; j <= i; j++) {
        try {
          if (await targets[j].exists()) {
            await targets[j].delete(recursive: true);
          }
        } catch (cleanupError) {
          debugPrint(
            '[Storage] could not clean up partial copy '
            '${targets[j].path}: $cleanupError',
          );
        }
      }
      return 'Could not copy "$name" to the new folder ($e). Nothing was '
          'moved — your data is still where it was.';
    }
  }

  for (final source in sources) {
    try {
      await source.delete(recursive: true);
      debugPrint(
        'Relocated ${path.basename(source.path)} to $newRoot (old deleted)',
      );
    } catch (e) {
      // Copied fine, just couldn't remove the original (a file still open,
      // a locked folder). Harmless — the new root has everything.
      debugPrint(
        '[Storage] copied ${path.basename(source.path)} but could not '
        'delete the old copy: $e',
      );
    }
  }
  return null;
}

/// Recursively copy a directory and its contents.
Future<void> copyDirectoryRecursive(
  Directory source,
  Directory destination,
) async {
  await destination.create(recursive: true);
  await for (final entity in source.list(recursive: false)) {
    final baseName = path.basename(entity.path);
    final newPath = path.join(destination.path, baseName);
    if (entity is File) {
      await entity.copy(newPath);
    } else if (entity is Directory) {
      await copyDirectoryRecursive(entity, Directory(newPath));
    }
  }
}

/// Custom chat backgrounds store an absolute path in prefs. After the root
/// moves, repoint those that lived under [oldRoot].
Future<void> repointCustomBackgroundsAfterRootMove({
  required String oldRoot,
  required String newRoot,
  required List<Map<String, String>> backgrounds,
  required Future<void> Function(String id) remove,
  required Future<void> Function(String id, String name, String filePath) add,
}) async {
  final moved = backgrounds
      .where((bg) => path.isWithin(oldRoot, bg['filePath'] ?? ''))
      .isNotEmpty;
  if (!moved) return;
  for (final bg in backgrounds) {
    await remove(bg['id'] ?? '');
  }
  for (final bg in backgrounds) {
    final filePath = bg['filePath'] ?? '';
    await add(
      bg['id'] ?? '',
      bg['name'] ?? '',
      path.isWithin(oldRoot, filePath)
          ? path.join(newRoot, path.relative(filePath, from: oldRoot))
          : filePath,
    );
  }
}
