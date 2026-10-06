// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/pages/home/cards/character_grid_card.dart';
import 'package:front_porch_ai/ui/pages/home/cards/folder_grid_card.dart';
import 'package:front_porch_ai/ui/pages/home/cards/group_grid_card.dart';
import 'package:front_porch_ai/ui/pages/home/widgets/home_grid_search_bar.dart';
import 'package:front_porch_ai/ui/pages/home/widgets/home_grid_toolbar.dart';
import 'package:front_porch_ai/ui/pages/home/widgets/library_grid_keys.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/library_view.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

export 'package:front_porch_ai/ui/widgets/library_view.dart' show SearchScope;

part 'character_card_grid.grid.dart';

enum FolderDialogAction { create, rename, delete }

/// How long a press must be held before a home-grid card starts dragging to a
/// folder. HALF Flutter's `kLongPressTimeout` (500 ms) — the stock delay made
/// organising a library feel unresponsive, as if the drag hadn't registered.
/// Shared by every draggable card (characters AND group casts) so the two
/// can't drift apart.
const Duration kFolderDragHoldDelay = Duration(milliseconds: 250);

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
    required this.selectedGroupIds,
    required this.searchController,
    required this.gridScrollController,
    required this.repo,
    required this.folderService,
    required this.groupRepo,
    required this.modeToggle,
    required this.onTapCharacter,
    required this.onTapGroup,
    required this.onToggleSelect,
    required this.onToggleSelectGroup,
    this.onToggleSelectMode,
    this.onToggleOrganizeMode,
    required this.onContextMenuAction,
    required this.onImport,
    required this.onAcceptFolderDrop,
    required this.onFolderDialogAction,
    required this.onFolderTap,
    required this.onFolderNavigateBack,
    required this.onFolderJump,
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
    this.onSelectAll,
    this.onSelectNone,
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
  final Set<String> selectedGroupIds;
  final TextEditingController searchController;
  final ScrollController gridScrollController;
  final CharacterRepository repo;
  final FolderService folderService;
  final GroupChatRepository groupRepo;
  final Widget modeToggle;

  final Future<void> Function(CharacterCard character) onTapCharacter;
  final Future<void> Function(GroupChat group) onTapGroup;
  final void Function(CharacterCard character) onToggleSelect;
  final void Function(GroupChat group) onToggleSelectGroup;
  final VoidCallback? onToggleSelectMode;
  final VoidCallback? onToggleOrganizeMode;
  final void Function(String action, CharacterCard character)
  onContextMenuAction;
  final void Function(String source) onImport;

  /// A card was dropped on a folder — [item] is a [CharacterCard] or a
  /// [GroupChat] (both drag into folders).
  final void Function(Object item, CharacterFolder folder) onAcceptFolderDrop;
  final void Function(
    FolderDialogAction action, {
    CharacterFolder? folder,
    String? parentId,
  })
  onFolderDialogAction;
  final void Function(CharacterFolder folder) onFolderTap;
  final VoidCallback onFolderNavigateBack;

  /// Breadcrumb jump to an ancestor folder (null = the library top level).
  final void Function(String? folderId) onFolderJump;
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

  /// Select all (#347): hands over the selection keys of every character
  /// and group chat on screen, so a search or "Top level only" limits it.
  /// Also Ctrl/Cmd+A on the grid. Null hides Select all / Select none.
  final void Function(Set<String> characterIds, Set<String> groupIds)?
  onSelectAll;

  /// Select none: clears every pick, hidden ones too.
  final VoidCallback? onSelectNone;

  LibraryView _view() => libraryViewOf(
    characters: repo.characters,
    groups: groupRepo.groups,
    folders: folderService,
    activeFolderId: activeFolderId,
    query: searchQuery,
    scope: searchScope,
    sortMode: sortMode,
    lastActivity: lastActivityCache,
    messageCount: messageCountCache,
  );

  @override
  Widget build(BuildContext context) {
    final view = _view();
    // Picks stay selected when a search or folder change hides them (#347).
    final picks = tallySelection(
      view,
      characterIds: selectedCharacterIds,
      groupIds: selectedGroupIds,
      library: repo.characters,
      groupLibrary: groupRepo.groups,
    );
    final selectedCount = picks.total;
    final picking = isSelecting || isOrganizing;
    final selectAll = onSelectAll;
    final addShown = selectAll == null
        ? null
        : () => selectAll(view.characterIds, view.groupIds);
    final moreToAdd =
        !selectedCharacterIds.containsAll(view.characterIds) ||
        !selectedGroupIds.containsAll(view.groupIds);

    return Stack(
      children: [
        Column(
          children: [
            HomeGridToolbar(
              isSelecting: isSelecting,
              isOrganizing: isOrganizing,
              activeFolderId: activeFolderId,
              selectedCount: selectedCount,
              hiddenSelectedCount: picks.hidden,
              selectionActions: addShown == null && onSelectNone == null
                  ? null
                  : LibrarySelectionActions(
                      selectAll: moreToAdd ? addShown : null,
                      selectNone: selectedCount > 0 ? onSelectNone : null,
                    ),
              sortMode: sortMode,
              gridScale: gridScale,
              modeToggle: modeToggle,
              repo: repo,
              folderService: folderService,
              onCancelSelection: onCancelSelection,
              onFolderNavigateBack: onFolderNavigateBack,
              onFolderJump: onFolderJump,
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
            Expanded(
              child: LibraryGridKeys(
                selecting: picking,
                onSelectAll: addShown,
                onEscape: picking ? onCancelSelection : null,
                child: _buildGrid(context, view),
              ),
            ),
          ],
        ),
        if (isSelecting && selectedCount > 0)
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
                    color: AppColors.porchHoneyOf(
                      context,
                    ).withValues(alpha: 0.8),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    picks.label,
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
                  // Multi-select is one gesture — moving lives beside
                  // deleting (users kept finding only the delete toolbar and
                  // never the separate organize mode, which remains for the
                  // folder-first workflow).
                  ElevatedButton.icon(
                    onPressed: () => onMoveToFolder(selectedCharacterIds),
                    icon: const Icon(Icons.drive_file_move, size: 18),
                    label: const Text('Move to Folder'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.porchAmberOf(context),
                      foregroundColor: AppColors.onChaosAccent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => onDeleteSelected(selectedCharacterIds),
                    icon: const Icon(Icons.delete_forever, size: 18),
                    label: Text('Delete $selectedCount Selected'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.negativeAccentOf(context),
                      foregroundColor: AppColors.userText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (isOrganizing && selectedCount > 0)
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
                    picks.label,
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
                    onPressed: selectedCount > 0
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
}
