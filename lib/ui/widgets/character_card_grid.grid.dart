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

    return Scrollbar(
      controller: gridScrollController,
      thumbVisibility: true,
      child: GridView.builder(
        controller: gridScrollController,
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          (isSelecting || isOrganizing) ? 80 : 24,
        ),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: gridScale,
          childAspectRatio: 0.7,
          crossAxisSpacing: 24,
          mainAxisSpacing: 24,
        ),
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
            return GroupGridCard(
              group: groups[groupOffset],
              groupRepo: groupRepo,
              activeFolderId: activeFolderId,
              isSelecting: isSelecting,
              isOrganizing: isOrganizing,
              selectedGroupIds: selectedGroupIds,
              onTapGroup: onTapGroup,
              onToggleSelectGroup: onToggleSelectGroup,
              onGroupContextMenuAction: onGroupContextMenuAction,
            );
          }
          final character = displayCharacters[groupOffset - groups.length];
          return CharacterGridCard(
            character: character,
            activeFolderId: activeFolderId,
            messageCountCache: messageCountCache,
            isSelecting: isSelecting,
            isOrganizing: isOrganizing,
            selectedCharacterIds: selectedCharacterIds,
            onTapCharacter: onTapCharacter,
            onToggleSelect: onToggleSelect,
            onContextMenuAction: onContextMenuAction,
            onResolveCharImage: onResolveCharImage,
            imageCacheEpoch: repo.coverEpoch,
          );
        },
      ),
    );
  }
}
