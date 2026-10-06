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

part of '../home_page.dart';

/// Folder, sort, grid-size and search handlers for the library grid.
extension _HomePageLibraryActions on _HomePageState {
  /// One drop handler for both draggable kinds: characters are keyed by image
  /// filename, group casts by their group id (see FolderService).
  Future<void> _handleAcceptFolderDrop(
    Object item,
    CharacterFolder folder,
  ) async {
    final folderService = Provider.of<FolderService>(context, listen: false);
    if (item is CharacterCard) {
      if (item.imagePath != null) {
        await folderService.addToFolder(folder.id, item.imagePath!);
      }
    } else if (item is GroupChat) {
      await folderService.addGroupToFolder(folder.id, item.id);
    }
  }

  void _handleFolderDialogAction(
    FolderDialogAction action, {
    CharacterFolder? folder,
    String? parentId,
  }) {
    final folderService = Provider.of<FolderService>(context, listen: false);
    switch (action) {
      case FolderDialogAction.create:
        _createFolder(context, folderService, parentId: parentId);
        break;
      case FolderDialogAction.rename:
        if (folder != null) _renameFolder(context, folder, folderService);
        break;
      case FolderDialogAction.delete:
        if (folder != null) _deleteFolder(context, folder, folderService);
        break;
    }
  }

  void _handleFolderTap(CharacterFolder folder) {
    applyState(() => _activeFolderId = folder.id);
  }

  /// Up one level. Subfolder cards only render inside their parent, so the
  /// parent chain IS the navigation history — no stack needed (and the
  /// breadcrumb trail can jump to any ancestor directly).
  void _handleFolderNavigateBack() {
    final folderService = Provider.of<FolderService>(context, listen: false);
    final current = folderService.folders
        .where((f) => f.id == _activeFolderId)
        .firstOrNull;
    applyState(() => _activeFolderId = current?.parentId);
  }

  void _handleMoveToFolder(Set<String> selectedIds) {
    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final folderService = Provider.of<FolderService>(context, listen: false);
    final chars = _selectedCharacterIds.length;
    final groups = _selectedGroupIds.length;
    // "N characters" / "N groups" when the selection is homogeneous,
    // "N items" for a mixed grab.
    final title = groups == 0
        ? 'Move $chars character${chars == 1 ? '' : 's'} to folder'
        : chars == 0
        ? 'Move $groups group${groups == 1 ? '' : 's'} to folder'
        : 'Move ${chars + groups} items to folder';
    _showMoveToFolderDialog(
      context,
      folderService,
      title: title,
      onMove: (folderId) =>
          _moveSelectedToFolder(context, folderId, repo, folderService),
    );
  }

  void _handleSortChanged(String mode) {
    applyState(() => _sortMode = mode);
    Provider.of<StorageService>(
      context,
      listen: false,
    ).uiSettings.setSortMode(mode);
  }

  void _handleGridScaleChanged(double scale) {
    applyState(() => _gridScale = scale);
  }

  void _handleGridScaleChangeEnd(double scale) {
    Provider.of<StorageService>(
      context,
      listen: false,
    ).uiSettings.setGridScale(scale);
  }

  void _handleSearchScopeChanged(SearchScope scope) {
    applyState(() => _searchScope = scope);
  }

  void _handleSearchQueryChanged(String query) {
    applyState(() => _searchQuery = query);
  }

  void _handleDeleteGroup(GroupChat group) {
    _confirmDeleteGroup(context, group);
  }
}
