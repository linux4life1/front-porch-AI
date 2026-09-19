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

part of 'data_migration_service.dart';

/// Delete legacy JSON files that are no longer needed after migration.
/// Safe to call multiple times — skips files that don't exist.
/// Preserves character PNGs (still needed for images).
///
/// Files in [preserve], plus anything a previous run recorded under
/// [_unimportedPrefsKey], are NEVER deleted: those never reached the
/// database, so the file on disk is the only copy of that conversation.
Future<void> _cleanupLegacyFilesImpl({
  Set<String> preserve = const <String>{},
}) async {
  final prefs = await SharedPreferences.getInstance();
  final rootPath = prefs.getString('root_path');
  final docsDir = await getApplicationDocumentsDirectory();
  final basePath = rootPath ?? docsDir.path;

  final keep = <String>{
    ...preserve,
    ...?prefs.getStringList(DataMigrationService._unimportedPrefsKey),
  };

  int deleted = 0;
  int kept = 0;

  // One place decides whether a legacy file dies, so the skip list cannot be
  // honoured in three of the four sweeps and forgotten in the fourth.
  Future<void> deleteUnlessKept(File file) async {
    if (keep.contains(file.path)) {
      kept++;
      return;
    }
    try {
      await file.delete();
      deleted++;
    } catch (e) {
      debugPrint('Cleanup: failed to delete ${file.path}: $e');
    }
  }

  // 1. Delete chat session JSONs: {root}/chats/{charId}/*.json
  final chatsDir = Directory('$basePath/chats');
  if (await chatsDir.exists()) {
    await for (final charDir in chatsDir.list()) {
      if (charDir is! Directory) continue;
      // Skip the 'groups' subdirectory — handled below
      if (charDir.path.endsWith('groups')) continue;
      await for (final entity in charDir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          await deleteUnlessKept(entity);
        }
      }
      // Remove the character chat directory if now empty. A preserved file
      // keeps its directory alive, which is what we want.
      try {
        if (await charDir.list().isEmpty) {
          await charDir.delete();
        }
      } catch (_) {}
    }
  }

  // 2. Delete group chat JSONs: {root}/chats/groups/*.json
  final groupsDir = Directory('$basePath/chats/groups');
  if (await groupsDir.exists()) {
    await for (final entity in groupsDir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        await deleteUnlessKept(entity);
      }
    }
    // Remove groups dir if now empty
    try {
      if (await groupsDir.list().isEmpty) {
        await groupsDir.delete();
      }
    } catch (_) {}
  }

  // 3. Delete world JSONs: {root}/worlds/*.json
  final worldsDir = Directory('$basePath/worlds');
  if (await worldsDir.exists()) {
    await for (final entity in worldsDir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        await deleteUnlessKept(entity);
      }
    }
  }

  // 4. Delete character_folders.json
  final foldersFile = File('$basePath/KoboldManager/character_folders.json');
  if (await foldersFile.exists()) {
    await deleteUnlessKept(foldersFile);
  }

  if (deleted > 0) {
    debugPrint('Cleanup: deleted $deleted legacy JSON file(s)');
  }
  if (kept > 0) {
    debugPrint(
      'Cleanup: kept $kept legacy file(s) that never imported — they are '
      'the only copy of that data left',
    );
  }
}
