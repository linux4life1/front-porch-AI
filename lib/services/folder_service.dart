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

import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:front_porch_ai/database/database.dart';

class CharacterFolder {
  final String id;
  String name;
  final String? parentId; // null = top-level folder
  final List<String>
  characterPaths; // filename-only references (e.g. "Miku_123.png")
  final List<String> groupIds; // group-chat ids (groups have no image key)

  CharacterFolder({
    required this.id,
    required this.name,
    this.parentId,
    List<String>? characterPaths,
    List<String>? groupIds,
  }) : characterPaths = characterPaths ?? [],
       groupIds = groupIds ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (parentId != null) 'parentId': parentId,
    'characterPaths': characterPaths,
    'groupIds': groupIds,
  };
}

class FolderService extends ChangeNotifier {
  AppDatabase _db;
  final List<CharacterFolder> _folders = [];

  List<CharacterFolder> get folders => List.unmodifiable(_folders);

  FolderService(this._db) {
    _init();
  }

  /// Update the database reference (e.g. after cloud sync replaces the DB file).
  void updateDatabase(AppDatabase db) {
    _db = db;
  }

  /// Normalize a character path to just its filename for portable storage.
  static String _normalize(String characterPath) {
    // Use simple split to avoid importing path package
    final parts = characterPath.split(RegExp(r'[/\\]'));
    return parts.last;
  }

  Future<void> _init() async {
    await _load();
  }

  /// Reload folders from DB (e.g. after cloud sync).
  Future<void> reload() async {
    await _load();
  }

  Future<void> _load() async {
    try {
      final dbFolders = await _db.getAllFolders();
      _folders.clear();

      // Fetch every character once, then bucket their normalized filenames by
      // folderId. Previously getAllCharacters() ran once per folder, so a
      // library with N characters and M folders did N*M work on every reload.
      final chars = await _db.getAllCharacters();
      final pathsByFolder = <String, List<String>>{};
      for (final c in chars) {
        final fid = c.folderId;
        if (fid != null && c.imagePath != null) {
          (pathsByFolder[fid] ??= <String>[]).add(_normalize(c.imagePath!));
        }
      }

      // Groups live in the same folder tree, keyed by group id (groups have
      // no image-filename key). Membership is groups.folder_id (v42).
      final dbGroups = await _db.getAllGroups();
      final groupsByFolder = <String, List<String>>{};
      for (final g in dbGroups) {
        final fid = g.folderId;
        if (fid != null) {
          (groupsByFolder[fid] ??= <String>[]).add(g.id);
        }
      }

      for (final f in dbFolders) {
        _folders.add(
          CharacterFolder(
            id: f.id,
            name: f.name,
            parentId: f.parentId,
            characterPaths: pathsByFolder[f.id] ?? const <String>[],
            groupIds: groupsByFolder[f.id] ?? const <String>[],
          ),
        );
      }
      notifyListeners();
    } catch (e) {
      print('Error loading folders: $e');
    }
  }

  /// The path to the local folders JSON file (for cloud sync).
  /// Returns null since folders now live in the DB.
  String? get storagePath => null;

  Future<CharacterFolder> createFolder(String name, {String? parentId}) async {
    final newId = await _db.insertFolder(
      FoldersCompanion(name: Value(name), parentId: Value(parentId)),
    );

    final folder = CharacterFolder(id: newId, name: name, parentId: parentId);
    _folders.add(folder);
    notifyListeners();
    return folder;
  }

  Future<void> renameFolder(String folderId, String newName) async {
    final folder = _folders.firstWhere((f) => f.id == folderId);
    folder.name = newName;

    await _db.updateFolder(
      FoldersCompanion(
        id: Value(folderId),
        name: Value(newName),
        updatedAt: Value(DateTime.now()),
      ),
    );
    notifyListeners();
  }

  Future<void> deleteFolder(String folderId) async {
    // Also delete child folders recursively
    final childIds = _folders
        .where((f) => f.parentId == folderId)
        .map((f) => f.id)
        .toList();
    for (final childId in childIds) {
      await deleteFolder(childId);
    }

    // Unassign characters from this folder
    final chars = await _db.getAllCharacters();
    for (final c in chars) {
      if (c.folderId == folderId) {
        await _db.updateCharacter(
          CharactersCompanion(
            id: Value(c.id),
            name: Value(c.name),
            folderId: const Value(null),
          ),
        );
      }
    }

    // Unassign groups from this folder (same contract as characters:
    // "Delete Folder Only" returns contents to the top level).
    final groups = await _db.getAllGroups();
    for (final g in groups) {
      if (g.folderId == folderId) {
        await _db.updateGroupFolderId(g.id, null);
      }
    }

    await _db.deleteFolderById(folderId);
    _folders.removeWhere((f) => f.id == folderId);
    notifyListeners();
  }

  Future<void> addToFolder(String folderId, String characterPath) async {
    final filename = _normalize(characterPath);

    // Find the character in the DB by matching imagePath
    final chars = await _db.getAllCharacters();
    for (final c in chars) {
      if (c.imagePath != null && _normalize(c.imagePath!) == filename) {
        await _db.updateCharacter(
          CharactersCompanion(
            id: Value(c.id),
            name: Value(c.name),
            folderId: Value(folderId),
            updatedAt: Value(DateTime.now()),
          ),
        );
        break;
      }
    }

    // Update in-memory
    await _load();
  }

  /// Clear a character's folder so it lands back on the home top level.
  ///
  /// [folderId] is the folder the caller *believes* the character is in — the
  /// guard stops a stale card from yanking a character out of a folder it was
  /// since moved to. Pass `null` for "whatever folder it is in", which is what
  /// the folder picker's "Home (no folder)" entry needs: from a global search
  /// or a breadcrumb view the caller has no idea which folder holds the card.
  Future<void> removeFromFolder(String? folderId, String characterPath) async {
    final filename = _normalize(characterPath);

    // Find the character and clear its folderId
    final chars = await _db.getAllCharacters();
    for (final c in chars) {
      if (c.imagePath != null &&
          _normalize(c.imagePath!) == filename &&
          (folderId == null || c.folderId == folderId)) {
        await _db.updateCharacter(
          CharactersCompanion(
            id: Value(c.id),
            name: Value(c.name),
            folderId: const Value(null),
            updatedAt: Value(DateTime.now()),
          ),
        );
        break;
      }
    }

    await _load();
  }

  /// Move many characters and group chats at once (#347): one transaction
  /// and one reload, so one redraw. Moving them one by one re-read every
  /// character and reloaded every folder per card. [folderId] null sends
  /// them back to the top level. Returns how many exist (and so are now
  /// there); ones already there are counted but not written again.
  Future<int> moveMany({
    required String? folderId,
    Iterable<String> characterPaths = const [],
    Iterable<String> groupIds = const [],
  }) async {
    final files = {for (final p in characterPaths) _normalize(p)};
    final groups = groupIds.toSet();
    if (files.isEmpty && groups.isEmpty) return 0;
    var moved = 0;
    await _db.transaction(() async {
      if (files.isNotEmpty) {
        final now = DateTime.now();
        for (final c in await _db.getAllCharacters()) {
          final path = c.imagePath;
          // The first row per file, as addToFolder does.
          if (path == null || !files.remove(_normalize(path))) continue;
          moved++;
          if (c.folderId == folderId) continue;
          await _db.updateCharacter(
            CharactersCompanion(
              id: Value(c.id),
              name: Value(c.name),
              folderId: Value(folderId),
              updatedAt: Value(now),
            ),
          );
        }
      }
      if (groups.isNotEmpty) {
        for (final g in await _db.getAllGroups()) {
          if (!groups.contains(g.id)) continue;
          moved++;
          if (g.folderId != folderId) {
            await _db.updateGroupFolderId(g.id, folderId);
          }
        }
      }
    });
    await _load();
    return moved;
  }

  /// Put a freshly-made copy in the same folder its source lives in.
  /// Membership is keyed by image filename, so a duplicate starts life
  /// unfoldered and (before this) dropped onto the home screen's top level
  /// no matter where its source was. No-op when the source is unfoldered or
  /// either side has no image. Shared by the desktop context menu AND the
  /// web facade's duplicate endpoint — the one folder-inheritance rule.
  Future<void> inheritFolder(String? sourcePath, String? copyPath) async {
    if (sourcePath == null || copyPath == null) return;
    final folder = getFolderForCharacter(sourcePath);
    if (folder == null) return;
    await addToFolder(folder.id, copyPath);
  }

  /// Get the folder a character belongs to (if any)
  CharacterFolder? getFolderForCharacter(String characterPath) {
    final filename = _normalize(characterPath);
    for (final folder in _folders) {
      if (folder.characterPaths.contains(filename)) {
        return folder;
      }
    }
    return null;
  }

  /// Move a group chat into a folder (writes groups.folder_id).
  Future<void> addGroupToFolder(String folderId, String groupId) async {
    await _db.updateGroupFolderId(groupId, folderId);
    await _load();
  }

  /// Remove a group chat from a folder (back to the home top level).
  ///
  /// Same contract as [removeFromFolder]: a non-null [folderId] guards against
  /// a stale card, `null` means "whatever folder it is in".
  Future<void> removeGroupFromFolder(String? folderId, String groupId) async {
    final folder = getFolderForGroup(groupId);
    if (folder == null) return;
    if (folderId != null && folder.id != folderId) return;
    await _db.updateGroupFolderId(groupId, null);
    await _load();
  }

  /// Get the folder a group chat belongs to (if any)
  CharacterFolder? getFolderForGroup(String groupId) {
    for (final folder in _folders) {
      if (folder.groupIds.contains(groupId)) {
        return folder;
      }
    }
    return null;
  }

  /// Get group ids directly in a specific folder
  List<String> groupIdsInFolder(String folderId) {
    final folder = _folders.firstWhere(
      (f) => f.id == folderId,
      orElse: () => CharacterFolder(id: '', name: ''),
    );
    return folder.groupIds;
  }

  /// Get group ids in a folder AND all its subfolders recursively
  List<String> groupIdsInFolderRecursive(String folderId) {
    final ids = <String>[...groupIdsInFolder(folderId)];
    for (final child in _folders.where((f) => f.parentId == folderId)) {
      ids.addAll(groupIdsInFolderRecursive(child.id));
    }
    return ids;
  }

  /// Get character filenames in a specific folder
  List<String> getCharactersInFolder(String folderId) {
    final folder = _folders.firstWhere(
      (f) => f.id == folderId,
      orElse: () => CharacterFolder(id: '', name: ''),
    );
    return folder.characterPaths;
  }

  /// Get character filenames in a folder AND all its subfolders recursively
  List<String> getCharactersInFolderRecursive(String folderId) {
    final paths = <String>[];
    // Add direct characters
    paths.addAll(getCharactersInFolder(folderId));
    // Add characters from all child folders
    for (final child in _folders.where((f) => f.parentId == folderId)) {
      paths.addAll(getCharactersInFolderRecursive(child.id));
    }
    return paths;
  }

  /// Get subfolders of a given parent (null = top-level folders)
  List<CharacterFolder> getSubfolders(String? parentId) {
    return _folders.where((f) => f.parentId == parentId).toList();
  }

  /// Get the full path of a folder (e.g. "Parent / Child")
  String getFolderPath(String folderId) {
    final folder = _folders.firstWhere(
      (f) => f.id == folderId,
      orElse: () => CharacterFolder(id: '', name: ''),
    );
    if (folder.id.isEmpty) return 'Unknown';
    if (folder.parentId == null) return folder.name;
    return '${getFolderPath(folder.parentId!)} / ${folder.name}';
  }

  /// Get all character filenames that are in ANY folder (for filtering unfoldered)
  Set<String> getUnfolderedCharacterPaths() {
    final folderedPaths = <String>{};
    for (final folder in _folders) {
      folderedPaths.addAll(folder.characterPaths);
    }
    return folderedPaths;
  }
}
