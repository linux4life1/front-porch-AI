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

/// Where a library search looks (#346). Inside a folder: that folder's own
/// cards, the folder and everything below it, or everywhere. At the top
/// level [currentFolder] is "Top level only" (cards in no folder), and
/// [folderRecursive] finds the same as [allCharacters] (everything).
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

  /// Selection keys of the characters on screen: the stableGroupId the
  /// select toggle writes.
  Set<String> get characterIds => {for (final c in characters) c.stableGroupId};

  /// Selection keys of the group chats on screen: their group ids.
  Set<String> get groupIds => {for (final g in groups) g.id};

  /// Every pickable card's selection key in grid order (group chats, then
  /// characters): what a Shift-click range runs along.
  List<String> get selectionOrder => [
    for (final g in groups) g.id,
    for (final c in characters) c.stableGroupId,
  ];
}

/// How many picks there are and how many of them are out of sight (#347).
/// Picks stay selected when a later search or folder change hides them,
/// so the counts must say so.
class SelectionTally {
  const SelectionTally({
    required this.characters,
    required this.groups,
    required this.hidden,
  });

  /// Selected characters that still exist in the library.
  final int characters;

  /// Selected group chats that still exist.
  final int groups;

  /// How many of those the current view does not show.
  final int hidden;

  int get total => characters + groups;

  /// "3 selected", or "3 selected (1 hidden)".
  String get label =>
      hidden > 0 ? '$total selected ($hidden hidden)' : '$total selected';
}

/// Counts [characterIds] and [groupIds] against the whole library and
/// [view]. A pick whose card was deleted elsewhere counts nowhere.
SelectionTally tallySelection(
  LibraryView view, {
  required Set<String> characterIds,
  required Set<String> groupIds,
  required List<CharacterCard> library,
  required List<GroupChat> groupLibrary,
}) {
  final shownChars = view.characterIds;
  final shownGroups = view.groupIds;
  var characters = 0;
  var groups = 0;
  var hidden = 0;
  for (final id in {for (final c in library) c.stableGroupId}) {
    if (!characterIds.contains(id)) continue;
    characters++;
    if (!shownChars.contains(id)) hidden++;
  }
  for (final g in groupLibrary) {
    if (!groupIds.contains(g.id)) continue;
    groups++;
    if (!shownGroups.contains(g.id)) hidden++;
  }
  return SelectionTally(characters: characters, groups: groups, hidden: hidden);
}

/// The one place the home grid's folder, search and sort rules live.
///
/// Browsing shows a folder's direct members, and at the top level only what
/// is in no folder: subfolders are their own tiles, and listing their cards
/// as well made phantom duplicates. Searching hides the folder tiles and
/// follows [scope] (see [SearchScope]) at every level.
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
  final everywhere = searching && scope == SearchScope.allCharacters;
  // Subfolders count only for a search that asks for them.
  final recursive = searching && scope == SearchScope.folderRecursive;
  if (folderId != null && !everywhere) {
    final names =
        (recursive
                ? folders.getCharactersInFolderRecursive(folderId)
                : folders.getCharactersInFolder(folderId))
            .toSet();
    cards = [
      for (final c in cards)
        if (c.imagePath != null && names.contains(path.basename(c.imagePath!)))
          c,
    ];
    final ids =
        (recursive
                ? folders.groupIdsInFolderRecursive(folderId)
                : folders.groupIdsInFolder(folderId))
            .toSet();
    casts = [
      for (final g in casts)
        if (ids.contains(g.id)) g,
    ];
  } else if (folderId == null && !everywhere && !recursive) {
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
