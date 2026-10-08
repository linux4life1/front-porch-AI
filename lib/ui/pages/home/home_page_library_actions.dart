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
  Future<void> _handleAcceptFolderDrop(Object item, CharacterFolder folder) =>
      _handleDropOnLevel(item, folder.id);

  /// A drop on a folder tile or on a level of the path (null: the top
  /// level). A dragged selection moves in one go and says so; a single
  /// card moves quietly, as it always has.
  Future<void> _handleDropOnLevel(Object item, String? folderId) async {
    final moved = await _selection.drop(
      item,
      folderId,
      folders: Provider.of<FolderService>(context, listen: false),
      library: Provider.of<CharacterRepository>(context, listen: false)
          .characters,
    );
    if (moved != null && item is LibraryDragPayload && mounted) {
      _snackMoved(context, moved, folderId);
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

  /// The selection counted the way the grid counts it: picks that still
  /// exist, and how many of them the current search or folder hides.
  SelectionTally _selectionTally() {
    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final groupRepo = Provider.of<GroupChatRepository>(context, listen: false);
    final view = libraryViewOf(
      characters: repo.characters,
      groups: groupRepo.groups,
      folders: Provider.of<FolderService>(context, listen: false),
      activeFolderId: _activeFolderId,
      query: _searchQuery,
      scope: _searchScope,
      sortMode: _sortMode,
    );
    return tallySelection(
      view,
      characterIds: _selection.characterIds,
      groupIds: _selection.groupIds,
      library: repo.characters,
      groupLibrary: groupRepo.groups,
    );
  }

  void _handleMoveToFolder(Set<String> selectedIds) {
    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final folderService = Provider.of<FolderService>(context, listen: false);
    final picks = _selectionTally();
    final chars = picks.characters;
    final groups = picks.groups;
    // "N characters" / "N groups" when the selection is homogeneous,
    // "N items" for a mixed grab. The full number, hidden picks included.
    final what = groups == 0
        ? '$chars character${chars == 1 ? '' : 's'}'
        : chars == 0
        ? '$groups group${groups == 1 ? '' : 's'}'
        : '${chars + groups} items';
    final hidden = picks.hidden > 0 ? ' (${picks.hidden} hidden)' : '';
    final title = 'Move $what to folder$hidden';
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

  /// Remembered per level, like the sort: the top level offers Everywhere
  /// and Top level only, a folder its three choices.
  void _handleSearchScopeChanged(SearchScope scope) {
    final prefs = Provider.of<StorageService>(
      context,
      listen: false,
    ).uiSettings;
    if (_activeFolderId == null) {
      applyState(() => _topSearchScope = scope);
      prefs.setTopSearchScope(scope.name);
    } else {
      applyState(() => _folderSearchScope = scope);
      prefs.setFolderSearchScope(scope.name);
    }
  }

  void _handleSearchQueryChanged(String query) {
    applyState(() => _searchQuery = query);
  }

  void _handleDeleteGroup(GroupChat group) {
    _confirmDeleteGroup(context, group);
  }
}
