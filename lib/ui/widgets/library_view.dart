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

import 'package:path/path.dart' as path;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';

enum SearchScope { currentFolder, folderRecursive, allCharacters }

/// What the home library grid shows, in display order: folder tiles, then
/// group chats, then characters. The grid draws exactly this, so anything
/// else that needs "what is on screen" must ask [libraryViewOf] too rather
/// than filter the library a second way.
class LibraryView {
  const LibraryView({
    required this.folders,
    required this.groups,
    required this.characters,
  });

  final List<CharacterFolder> folders;
  final List<GroupChat> groups;
  final List<CharacterCard> characters;

  bool get isEmpty => folders.isEmpty && groups.isEmpty && characters.isEmpty;
}

/// The one place the home grid's folder, search and sort rules live.
///
/// Browsing shows a folder's direct members (its subfolders are their own
/// tiles; listing their cards too made phantom duplicates). Searching hides
/// the folder tiles and looks inside subfolders, unless [scope] is
/// [SearchScope.allCharacters], which ignores folders. At the top level,
/// browsing shows only what is in no folder.
LibraryView libraryViewOf({
  required List<CharacterCard> characters,
  required List<GroupChat> groups,
  required FolderService folders,
  required String? activeFolderId,
  required String query,
  required SearchScope scope,
  required String sortMode,
  Map<String, DateTime> lastActivity = const {},
  Map<String, int> messageCount = const {},
}) {
  final searching = query.isNotEmpty;
  final mode = CharacterSortMode.fromKey(sortMode);
  var cards = characters;
  var casts = groups;

  final folderId = activeFolderId;
  if (folderId != null && !(searching && scope == SearchScope.allCharacters)) {
    final names =
        (searching
                ? folders.getCharactersInFolderRecursive(folderId)
                : folders.getCharactersInFolder(folderId))
            .toSet();
    cards = [
      for (final c in cards)
        if (c.imagePath != null && names.contains(path.basename(c.imagePath!)))
          c,
    ];
    final ids =
        (searching
                ? folders.groupIdsInFolderRecursive(folderId)
                : folders.groupIdsInFolder(folderId))
            .toSet();
    casts = [
      for (final g in casts)
        if (ids.contains(g.id)) g,
    ];
  } else if (folderId == null && !searching) {
    final foldered = folders.getUnfolderedCharacterPaths();
    cards = [
      for (final c in cards)
        if (c.imagePath == null ||
            !foldered.contains(path.basename(c.imagePath!)))
          c,
    ];
    final folderedGroups = {for (final f in folders.folders) ...f.groupIds};
    casts = [
      for (final g in casts)
        if (!folderedGroups.contains(g.id)) g,
    ];
  }

  if (searching) {
    final q = query.toLowerCase();
    cards = [
      for (final c in cards)
        if (c.name.toLowerCase().contains(q) ||
            c.tags.any((t) => t.toLowerCase().contains(q)))
          c,
    ];
    casts = [
      for (final g in casts)
        if (g.name.toLowerCase().contains(q)) g,
    ];
  }

  return LibraryView(
    folders: searching
        ? const []
        : _sortedFolders(
            folders,
            folders.getSubfolders(activeFolderId),
            characters,
            mode,
            lastActivity,
            messageCount,
          ),
    groups: sortGroups(casts),
    characters: sortCharacters(
      cards,
      mode,
      lastActivity: lastActivity,
      messageCount: messageCount,
    ),
  );
}

/// Folder tiles in [mode]'s order, each valued by the characters anywhere
/// inside it (subfolders included).
List<CharacterFolder> _sortedFolders(
  FolderService service,
  List<CharacterFolder> tiles,
  List<CharacterCard> characters,
  CharacterSortMode mode,
  Map<String, DateTime> lastActivity,
  Map<String, int> messageCount,
) {
  if (tiles.length < 2) return tiles;
  final byFile = <String, CharacterCard>{};
  if (mode != CharacterSortMode.name) {
    for (final c in characters) {
      final p = c.imagePath;
      if (p != null) byFile.putIfAbsent(path.basename(p), () => c);
    }
  }
  return sortFolders<CharacterFolder>(
    tiles,
    mode,
    nameOf: (f) => f.name,
    cardsIn: (f) => [
      for (final file in service.getCharactersInFolderRecursive(f.id))
        ?byFile[path.basename(file)],
    ],
    lastActivity: lastActivity,
    messageCount: messageCount,
  );
}
