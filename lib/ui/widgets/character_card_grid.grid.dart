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

part of 'character_card_grid.dart';

/// Folder / group / character cells. Toolbar chrome stays on [CharacterCardGrid].
extension CharacterCardGridBuild on CharacterCardGrid {
  Widget _buildGrid(BuildContext context, LibraryView view) {
    final folders = view.folders;
    final groups = view.groups;
    final displayCharacters = view.characters;
    final totalItems =
        folders.length + groups.length + displayCharacters.length;
    if (totalItems == 0) {
      return Center(
        child: Text(
          searchQuery.isNotEmpty
              ? 'No characters match "$searchQuery"'
              : 'This folder is empty',
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 16,
          ),
        ),
      );
    }

    final picking = isSelecting || isOrganizing;
    final padding = EdgeInsets.fromLTRB(24, 24, 24, picking ? 80 : 24);
    final delegate = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: gridScale,
      childAspectRatio: 0.7,
      crossAxisSpacing: 24,
      mainAxisSpacing: 24,
    );
    final sel = selection;

    final grid = Scrollbar(
      controller: gridScrollController,
      thumbVisibility: true,
      child: GridView.builder(
        controller: gridScrollController,
        padding: padding,
        gridDelegate: delegate,
        itemCount: totalItems,
        itemBuilder: (context, index) {
          if (index < folders.length) {
            return FolderGridCard(
              folder: folders[index],
              onAcceptFolderDrop: onAcceptFolderDrop,
              onFolderTap: onFolderTap,
              onFolderDialogAction: onFolderDialogAction,
              onResolveCharImage: onResolveCharImage,
            );
          }
          final groupOffset = index - folders.length;
          if (groupOffset < groups.length) {
            final group = groups[groupOffset];
            return GroupGridCard(
              group: group,
              groupRepo: groupRepo,
              activeFolderId: activeFolderId,
              isSelecting: isSelecting,
              isOrganizing: isOrganizing,
              selectedGroupIds: selectedGroupIds,
              onTapGroup: sel == null
                  ? onTapGroup
                  : (g) async {
                      if (_pickModifier) {
                        _pick(sel, view, g.id, group: true);
                        return;
                      }
                      await onTapGroup(g);
                    },
              onToggleSelectGroup: sel == null
                  ? onToggleSelectGroup
                  : (g) => _pick(sel, view, g.id, group: true),
              onGroupContextMenuAction: onGroupContextMenuAction,
            );
          }
          final character = displayCharacters[groupOffset - groups.length];
          final key = character.stableGroupId;
          return CharacterGridCard(
            character: character,
            activeFolderId: activeFolderId,
            messageCountCache: messageCountCache,
            isSelecting: isSelecting,
            isOrganizing: isOrganizing,
            selectedCharacterIds: selectedCharacterIds,
            onTapCharacter: sel == null
                ? onTapCharacter
                : (c) async {
                    if (_pickModifier) {
                      _pick(sel, view, key, group: false);
                      return;
                    }
                    await onTapCharacter(c);
                  },
            onToggleSelect: sel == null
                ? onToggleSelect
                : (_) => _pick(sel, view, key, group: false),
            onContextMenuAction: onContextMenuAction,
            onResolveCharImage: onResolveCharImage,
            imageCacheEpoch: repo.coverEpoch,
          );
        },
      ),
    );
    if (sel == null) return grid;
    // A quick mouse drag draws a box over the grid (library phase 2).
    return LibraryBoxSelect(
      scrollController: gridScrollController,
      geometry: LibraryGridGeometry(delegate: delegate, padding: padding),
      keys: [for (final _ in folders) null, ...view.selectionOrder],
      groupKeys: view.groupIds,
      pickedCharacters: selectedCharacterIds,
      pickedGroups: selectedGroupIds,
      onBox: sel.replace,
      child: grid,
    );
  }

  /// Shift or Ctrl/Cmd held: a click picks instead of opening the card.
  bool get _pickModifier {
    final keys = HardwareKeyboard.instance;
    return keys.isShiftPressed || keys.isControlPressed || keys.isMetaPressed;
  }

  /// A pick click (library phase 2): Shift ranges from the last clicked
  /// card, anything else toggles this one.
  void _pick(
    LibrarySelection sel,
    LibraryView view,
    String key, {
    required bool group,
  }) {
    if (HardwareKeyboard.instance.isShiftPressed) {
      sel.addRange(
        key,
        group: group,
        order: view.selectionOrder,
        groupKeys: view.groupIds,
      );
    } else {
      sel.toggle(key, group: group);
    }
  }
}
