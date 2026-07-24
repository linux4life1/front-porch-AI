// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/pages/home/cards/character_grid_card.dart';
import 'package:front_porch_ai/ui/pages/home/cards/folder_grid_card.dart';
import 'package:front_porch_ai/ui/pages/home/cards/group_grid_card.dart';
import 'package:front_porch_ai/ui/pages/home/widgets/home_grid_search_bar.dart';
import 'package:front_porch_ai/ui/pages/home/widgets/home_grid_toolbar.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';

enum SearchScope { currentFolder, folderRecursive, allCharacters }

enum FolderDialogAction { create, rename, delete }

class CharacterCardGrid extends StatelessWidget {
  const CharacterCardGrid({
    super.key,
    required this.searchQuery,
    required this.searchScope,
    required this.activeFolderId,
    required this.sortMode,
    required this.lastActivityCache,
    required this.messageCountCache,
    required this.gridScale,
    required this.isSelecting,
    required this.isOrganizing,
    required this.selectedCharacterIds,
    required this.searchController,
    required this.gridScrollController,
    required this.repo,
    required this.folderService,
    required this.groupRepo,
    required this.modeToggle,
    required this.onTapCharacter,
    required this.onTapGroup,
    required this.onToggleSelect,
    this.onToggleSelectMode,
    this.onToggleOrganizeMode,
    required this.onContextMenuAction,
    required this.onImport,
    required this.onAcceptFolderDrop,
    required this.onFolderDialogAction,
    required this.onFolderTap,
    required this.onFolderNavigateBack,
    required this.onCancelSelection,
    required this.onDeleteSelected,
    required this.onMoveToFolder,
    required this.onSortChanged,
    required this.onGridScaleChanged,
    this.onGridScaleChangeEnd,
    required this.onSearchScopeChanged,
    required this.onSearchQueryChanged,
    required this.onResolveCharImage,
    required this.onDeleteGroup,
    required this.onAfterNavigateBack,
    this.onGroupContextMenuAction,
  });

  final String searchQuery;
  final SearchScope searchScope;
  final String? activeFolderId;
  final String sortMode;
  final Map<String, DateTime> lastActivityCache;
  final Map<String, int> messageCountCache;
  final double gridScale;
  final bool isSelecting;
  final bool isOrganizing;
  final Set<String> selectedCharacterIds;
  final TextEditingController searchController;
  final ScrollController gridScrollController;
  final CharacterRepository repo;
  final FolderService folderService;
  final GroupChatRepository groupRepo;
  final Widget modeToggle;

  final Future<void> Function(CharacterCard character) onTapCharacter;
  final Future<void> Function(GroupChat group) onTapGroup;
  final void Function(CharacterCard character) onToggleSelect;
  final VoidCallback? onToggleSelectMode;
  final VoidCallback? onToggleOrganizeMode;
  final void Function(String action, CharacterCard character)
  onContextMenuAction;
  final void Function(String source) onImport;
  final void Function(CharacterCard character, CharacterFolder folder)
  onAcceptFolderDrop;
  final void Function(
    FolderDialogAction action, {
    CharacterFolder? folder,
    String? parentId,
  })
  onFolderDialogAction;
  final void Function(CharacterFolder folder) onFolderTap;
  final VoidCallback onFolderNavigateBack;
  final VoidCallback onCancelSelection;
  // onCreateGroup removed — group creation is now exclusively via the sidebar "Create Group Chat" button.
  /// Mass delete of the selected characters (severe typed-DELETE confirm
  /// lives with the handler — this just hands over the selection).
  final void Function(Set<String> selectedIds) onDeleteSelected;
  final void Function(Set<String> selectedIds) onMoveToFolder;
  final void Function(String mode) onSortChanged;
  final void Function(double scale) onGridScaleChanged;
  final void Function(double scale)? onGridScaleChangeEnd;
  final void Function(SearchScope scope) onSearchScopeChanged;
  final void Function(String query) onSearchQueryChanged;
  final File Function(CharacterCard card) onResolveCharImage;
  final void Function(GroupChat group) onDeleteGroup;
  final VoidCallback onAfterNavigateBack;

  /// Called when the user right-clicks (secondary tap) a group card on the home grid.
  /// Mirrors the existing `onContextMenuAction` pattern used for CharacterCard.
  final void Function(String action, GroupChat group)? onGroupContextMenuAction;


  List<CharacterCard> _getFilteredCharacters() {
    List<CharacterCard> characters;

    final skipFolderFilter =
        searchScope == SearchScope.allCharacters && searchQuery.isNotEmpty;
    if (activeFolderId != null && !skipFolderFilter) {
      List<String> folderFilenames;
      if (searchQuery.isEmpty) {
        // Normal browsing: subfolder cards are rendered for navigation
        // (see _buildGrid -> getSubfolders), so only list characters that
        // live DIRECTLY in this folder. Using the recursive list here
        // flattened every subfolder's characters back into the parent view,
        // producing a phantom "duplicate" card for any character that had
        // been moved into a subfolder. Because that phantom card and the
        // real one share a single CharacterCard/DB row, deleting the
        // phantom also deleted the original.
        folderFilenames = folderService.getCharactersInFolder(activeFolderId!);
      } else {
        // Searching: subfolder cards are hidden (_buildGrid only shows
        // folders when the query is empty), so search recursively so
        // characters nested in subfolders remain findable.
        folderFilenames = folderService.getCharactersInFolderRecursive(
          activeFolderId!,
        );
      }
      characters = repo.characters
          .where(
            (c) =>
                c.imagePath != null &&
                folderFilenames.contains(path.basename(c.imagePath!)),
          )
          .toList();
    } else {
      characters = repo.characters.toList();
    }

    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      characters = characters.where((c) {
        if (c.name.toLowerCase().contains(query)) return true;
        if (c.tags.any((t) => t.toLowerCase().contains(query))) return true;
        return false;
      }).toList();
    }

    return sortCharacters(
      characters,
      CharacterSortMode.fromKey(sortMode),
      lastActivity: lastActivityCache,
      messageCount: messageCountCache,
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredCharacters = _getFilteredCharacters();

    return Stack(
      children: [
        Column(
          children: [
            HomeGridToolbar(
              isSelecting: isSelecting,
              isOrganizing: isOrganizing,
              activeFolderId: activeFolderId,
              selectedCharacterIds: selectedCharacterIds,
              sortMode: sortMode,
              gridScale: gridScale,
              modeToggle: modeToggle,
              repo: repo,
              folderService: folderService,
              onCancelSelection: onCancelSelection,
              onFolderNavigateBack: onFolderNavigateBack,
              onSortChanged: onSortChanged,
              onGridScaleChanged: onGridScaleChanged,
              onGridScaleChangeEnd: onGridScaleChangeEnd,
              onToggleSelectMode: onToggleSelectMode,
              onToggleOrganizeMode: onToggleOrganizeMode,
              onFolderDialogAction: onFolderDialogAction,
              onImport: onImport,
            ),
            HomeGridSearchBar(
              searchController: searchController,
              searchQuery: searchQuery,
              searchScope: searchScope,
              activeFolderId: activeFolderId,
              onSearchScopeChanged: onSearchScopeChanged,
              onSearchQueryChanged: onSearchQueryChanged,
            ),
            const SizedBox(height: 12),
            Expanded(child: _buildGrid(context, filteredCharacters)),
          ],
        ),
        if (isSelecting && selectedCharacterIds.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerOf(context),
                border: Border(
                  top: BorderSide(color: AppColors.borderOf(context)),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.resolve(
                      context,
                      Colors.black.withValues(alpha: 0.3),
                      Colors.black.withValues(alpha: 0.1),
                    ),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.checklist,
                    color: AppColors.porchHoneyOf(context).withValues(
                      alpha: 0.8,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${selectedCharacterIds.length} selected',
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: onCancelSelection,
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: AppColors.textSecondary(context)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => onDeleteSelected(selectedCharacterIds),
                    icon: const Icon(Icons.delete_forever, size: 18),
                    label: Text(
                      'Delete ${selectedCharacterIds.length} Selected',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.negativeAccentOf(context),
                      foregroundColor: AppColors.userText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (isOrganizing && selectedCharacterIds.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerOf(context),
                border: Border(
                  top: BorderSide(color: AppColors.borderOf(context)),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.resolve(
                      context,
                      Colors.black.withValues(alpha: 0.3),
                      Colors.black.withValues(alpha: 0.1),
                    ),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.drive_file_move,
                    color: AppColors.formMasterAccent.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${selectedCharacterIds.length} selected',
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: onCancelSelection,
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: AppColors.textSecondary(context)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: selectedCharacterIds.isNotEmpty
                        ? () => onMoveToFolder(selectedCharacterIds)
                        : null,
                    icon: const Icon(Icons.drive_file_move, size: 18),
                    label: const Text('Move to Folder'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.formMasterAccent,
                      foregroundColor: AppColors.onChaosAccent,
                      disabledBackgroundColor: AppColors.resolve(
                        context,
                        Colors.white10,
                        Colors.black12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGrid(
    BuildContext context,
    List<CharacterCard> filteredCharacters,
  ) {
    final showFolders = searchQuery.isEmpty;
    final folders = showFolders
        ? folderService.getSubfolders(activeFolderId)
        : <CharacterFolder>[];

    final groups =
        (activeFolderId == null &&
            searchQuery.isEmpty &&
            !isSelecting &&
            !isOrganizing)
        ? groupRepo.groups
        : <GroupChat>[];

    List<CharacterCard> displayCharacters;
    if (showFolders && activeFolderId == null) {
      final folderedFilenames = folderService.getUnfolderedCharacterPaths();
      displayCharacters = filteredCharacters
          .where(
            (c) =>
                c.imagePath == null ||
                !folderedFilenames.contains(path.basename(c.imagePath!)),
          )
          .toList();
    } else {
      displayCharacters = filteredCharacters;
    }

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
              isSelecting: isSelecting,
              isOrganizing: isOrganizing,
              onTapGroup: onTapGroup,
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
          );
        },
      ),
    );
  }
}
