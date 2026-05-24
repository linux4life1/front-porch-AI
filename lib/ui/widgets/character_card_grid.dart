// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/folder_service.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';

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
    required this.onOpenBrowser,
    required this.onAcceptFolderDrop,
    required this.onFolderDialogAction,
    required this.onFolderTap,
    required this.onFolderNavigateBack,
    required this.onCancelSelection,
    required this.onCreateGroup,
    required this.onMoveToFolder,
    required this.onSortChanged,
    required this.onGridScaleChanged,
    this.onGridScaleChangeEnd,
    required this.onSearchScopeChanged,
    required this.onSearchQueryChanged,
    required this.onResolveCharImage,
    required this.onDeleteGroup,
    required this.onAfterNavigateBack,
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
  final void Function(String action, CharacterCard character) onContextMenuAction;
  final void Function(String source) onImport;
  final void Function(String site) onOpenBrowser;
  final void Function(CharacterCard character, CharacterFolder folder) onAcceptFolderDrop;
  final void Function(FolderDialogAction action, {CharacterFolder? folder, String? parentId}) onFolderDialogAction;
  final void Function(CharacterFolder folder) onFolderTap;
  final VoidCallback onFolderNavigateBack;
  final VoidCallback onCancelSelection;
  final void Function(Set<String> selectedIds) onCreateGroup;
  final void Function(Set<String> selectedIds) onMoveToFolder;
  final void Function(String mode) onSortChanged;
  final void Function(double scale) onGridScaleChanged;
  final void Function(double scale)? onGridScaleChangeEnd;
  final void Function(SearchScope scope) onSearchScopeChanged;
  final void Function(String query) onSearchQueryChanged;
  final File Function(String imagePath) onResolveCharImage;
  final void Function(GroupChat group) onDeleteGroup;
  final VoidCallback onAfterNavigateBack;

  String _getCharacterIdFromCard(CharacterCard card) {
    if (card.imagePath != null) {
      return path.basenameWithoutExtension(card.imagePath!);
    }
    return card.name.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_');
  }

  int _extractImportEpoch(CharacterCard card) {
    if (card.imagePath == null) return 0;
    final basename = path.basenameWithoutExtension(card.imagePath!);
    final lastUnderscore = basename.lastIndexOf('_');
    if (lastUnderscore == -1) return 0;
    return int.tryParse(basename.substring(lastUnderscore + 1)) ?? 0;
  }

  String _getActiveFolderName() {
    if (activeFolderId == null) return 'My Characters';
    final folder = folderService.folders
        .where((f) => f.id == activeFolderId)
        .firstOrNull;
    return folder?.name ?? 'Folder';
  }

  List<CharacterCard> _getFilteredCharacters() {
    List<CharacterCard> characters;

    final skipFolderFilter = searchScope == SearchScope.allCharacters && searchQuery.isNotEmpty;
    if (activeFolderId != null && !skipFolderFilter) {
      List<String> folderFilenames;
      if (searchQuery.isNotEmpty && searchScope == SearchScope.currentFolder) {
        folderFilenames = folderService.getCharactersInFolder(activeFolderId!);
      } else {
        folderFilenames = folderService.getCharactersInFolderRecursive(activeFolderId!);
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

    switch (sortMode) {
      case 'name':
        characters.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        break;
      case 'recent':
        characters.sort((a, b) {
          final aId = a.dbId ?? _getCharacterIdFromCard(a);
          final bId = b.dbId ?? _getCharacterIdFromCard(b);
          final aTime = lastActivityCache[aId] ?? DateTime(1970);
          final bTime = lastActivityCache[bId] ?? DateTime(1970);
          return bTime.compareTo(aTime);
        });
        break;
      case 'importDate':
        characters.sort((a, b) {
          final aEpoch = _extractImportEpoch(a);
          final bEpoch = _extractImportEpoch(b);
          return bEpoch.compareTo(aEpoch);
        });
        break;
    }
    if (sortMode == 'messages') {
      characters.sort((a, b) {
        final aId = a.dbId ?? _getCharacterIdFromCard(a);
        final bId = b.dbId ?? _getCharacterIdFromCard(b);
        final aCount = messageCountCache[aId] ?? 0;
        final bCount = messageCountCache[bId] ?? 0;
        return bCount.compareTo(aCount);
      });
    }

    return characters;
  }

  @override
  Widget build(BuildContext context) {
    final filteredCharacters = _getFilteredCharacters();

    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 16.0,
              ),
              child: Row(
                children: [
                  if (isSelecting || isOrganizing) ...[
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Cancel selection',
                      onPressed: onCancelSelection,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${selectedCharacterIds.length} selected',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isOrganizing
                                ? Colors.blueAccent
                                : Colors.purpleAccent,
                          ),
                    ),
                  ] else if (activeFolderId != null) ...[
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Back to all characters',
                      onPressed: onFolderNavigateBack,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _getActiveFolderName(),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ] else
                    modeToggle,
                  const SizedBox(width: 16),
                  if (!isSelecting && !isOrganizing)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerOf(context),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.borderOf(context)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: sortMode,
                          icon: Icon(
                            Icons.sort,
                            size: 18,
                            color: AppColors.iconSecondary(context),
                          ),
                          dropdownColor: AppColors.surfaceContainerOf(context),
                          style: TextStyle(
                            color: AppColors.textSecondary(context),
                            fontSize: 13,
                          ),
                          isDense: true,
                          items: const [
                            DropdownMenuItem(
                              value: 'name',
                              child: Text('Name (A\u2192Z)'),
                            ),
                            DropdownMenuItem(
                              value: 'recent',
                              child: Text('Recent Activity'),
                            ),
                            DropdownMenuItem(
                              value: 'importDate',
                              child: Text('Import Date'),
                            ),
                            DropdownMenuItem(
                              value: 'messages',
                              child: Text('Messages Sent'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) onSortChanged(value);
                          },
                        ),
                      ),
                    ),
                  if (!isSelecting && !isOrganizing)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: SizedBox(
                        width: 120,
                        child: Row(
                        children: [
                          Icon(
                            Icons.grid_view,
                            size: 16,
                            color: AppColors.iconSecondary(context),
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6,
                                ),
                                overlayShape:
                                    const RoundSliderOverlayShape(
                                      overlayRadius: 12,
                                    ),
                                activeTrackColor: Colors.blueAccent
                                    .withValues(alpha: 0.7),
                                inactiveTrackColor: AppColors.resolve(
                                  context,
                                  Colors.white.withValues(alpha: 0.12),
                                  Colors.black.withValues(alpha: 0.12),
                                ),
                                thumbColor: Colors.blueAccent,
                              ),
                              child: Slider(
                                value: gridScale,
                                min: 150,
                                max: 450,
                                onChanged: (v) => onGridScaleChanged(v),
                                onChangeEnd: (v) => onGridScaleChangeEnd?.call(v),
                              ),
                            ),
                          ),
                          Icon(
                            Icons.view_module,
                            size: 16,
                            color: AppColors.iconSecondary(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (!isSelecting && !isOrganizing) ...[
                    IconButton(
                      tooltip: 'Select characters for group chat',
                      icon: const Icon(
                        Icons.group_add,
                        color: Colors.purpleAccent,
                      ),
                      onPressed: onToggleSelectMode,
                    ),
                    IconButton(
                      tooltip: 'Organize into folders',
                      icon: const Icon(
                        Icons.drive_file_move_outlined,
                        color: Colors.blueAccent,
                      ),
                      onPressed: onToggleOrganizeMode,
                    ),
                    if (activeFolderId == null)
                      IconButton(
                        tooltip: 'New Folder',
                        icon: const Icon(
                          Icons.create_new_folder_outlined,
                        ),
                        onPressed: () => onFolderDialogAction(
                          FolderDialogAction.create,
                        ),
                      ),
                    if (activeFolderId != null)
                      IconButton(
                        tooltip: 'New Subfolder',
                        icon: const Icon(
                          Icons.create_new_folder_outlined,
                          color: Colors.amberAccent,
                        ),
                        onPressed: () => onFolderDialogAction(
                          FolderDialogAction.create,
                          parentId: activeFolderId,
                        ),
                      ),
                    PopupMenuButton<String>(
                      tooltip: 'Import Characters',
                      icon: const Icon(Icons.download),
                      onSelected: onImport,
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'cards',
                          child: ListTile(
                            leading: Icon(Icons.download),
                            title: Text('Import Cards'),
                            dense: true,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'folder',
                          child: ListTile(
                            leading: Icon(Icons.library_add),
                            title: Text('Import Folder'),
                            dense: true,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'byaf',
                          child: ListTile(
                            leading: Icon(Icons.archive_outlined),
                            title: Text('Import Backyard AI (.byaf)'),
                            dense: true,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      tooltip: 'Browse AI Character Cards',
                      icon: const Icon(
                        Icons.public,
                        color: Colors.blueAccent,
                      ),
                      onPressed: () => onOpenBrowser('aicc'),
                    ),
                    IconButton(
                      tooltip: 'Chub.ai (Caution)',
                      icon: const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.redAccent,
                      ),
                      onPressed: () => onOpenBrowser('chub'),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: TextField(
                controller: searchController,
                style: TextStyle(color: AppColors.textPrimary(context)),
                decoration: InputDecoration(
                  hintText: activeFolderId != null && searchScope != SearchScope.allCharacters
                      ? 'Search this folder...'
                      : 'Search by name or tag...',
                  hintStyle: TextStyle(color: AppColors.textTertiary(context)),
                  prefixIcon: activeFolderId != null
                      ? PopupMenuButton<SearchScope>(
                          icon: Icon(
                            searchScope == SearchScope.allCharacters ? Icons.search : Icons.folder_open,
                            color: searchScope == SearchScope.allCharacters
                                ? Colors.blueAccent
                                : Colors.amberAccent,
                            size: 20,
                          ),
                          tooltip: 'Search scope',
                          color: AppColors.surfaceContainerOf(context),
                          onSelected: onSearchScopeChanged,
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: SearchScope.currentFolder,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.folder,
                                    size: 18,
                                    color: searchScope == SearchScope.currentFolder
                                        ? Colors.amberAccent
                                        : AppColors.iconSecondary(context),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'This Folder Only',
                                    style: TextStyle(
                                      color: searchScope == SearchScope.currentFolder
                                          ? Colors.amberAccent
                                          : AppColors.textSecondary(context),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: SearchScope.folderRecursive,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.snippet_folder,
                                    size: 18,
                                    color: searchScope == SearchScope.folderRecursive
                                        ? Colors.amberAccent
                                        : AppColors.iconSecondary(context),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Folder & Subfolders',
                                    style: TextStyle(
                                      color: searchScope == SearchScope.folderRecursive
                                          ? Colors.amberAccent
                                          : AppColors.textSecondary(context),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: SearchScope.allCharacters,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.search,
                                    size: 18,
                                    color: searchScope == SearchScope.allCharacters
                                        ? Colors.blueAccent
                                        : AppColors.iconSecondary(context),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'All Characters',
                                    style: TextStyle(
                                      color: searchScope == SearchScope.allCharacters
                                          ? Colors.blueAccent
                                          : AppColors.textSecondary(context),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : Icon(Icons.search, color: AppColors.iconSecondary(context)),
                  suffixIcon: searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.clear,
                            color: AppColors.iconSecondary(context),
                          ),
                          onPressed: () {
                            searchController.clear();
                            onSearchQueryChanged('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: AppColors.surfaceContainerOf(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 12,
                  ),
                ),
                onChanged: onSearchQueryChanged,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _buildGrid(context, filteredCharacters),
            ),
          ],
        ),
        if (isSelecting && selectedCharacterIds.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
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
                    Icons.group,
                    color: Colors.purpleAccent.withValues(alpha: 0.7),
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
                    onPressed: selectedCharacterIds.length >= 2
                        ? () => onCreateGroup(selectedCharacterIds)
                        : null,
                    icon: const Icon(Icons.group_add),
                    label: const Text('Create Group'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purpleAccent,
                      foregroundColor: Colors.white,
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
        if (isOrganizing && selectedCharacterIds.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
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
                    color: Colors.blueAccent.withValues(alpha: 0.7),
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
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
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
          style: TextStyle(color: AppColors.textTertiary(context), fontSize: 16),
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
            return _buildFolderCard(context, folders[index]);
          }
          final groupOffset = index - folders.length;
          if (groupOffset < groups.length) {
            return _buildGroupCard(context, groups[groupOffset]);
          }
          final character = displayCharacters[groupOffset - groups.length];
          return _buildCharacterCard(context, character);
        },
      ),
    );
  }

  Widget _buildFolderCard(BuildContext context, CharacterFolder folder) {
    final charCount = folder.characterPaths.length;

    return DragTarget<CharacterCard>(
      onAcceptWithDetails: (details) {
        onAcceptFolderDrop(details.data, folder);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return Card(
          color: isHovering
              ? AppColors.resolve(
                  context,
                  Colors.amber.shade900.withValues(alpha: 0.4),
                  Colors.amber.withValues(alpha: 0.1),
                )
              : AppColors.cardOf(context),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isHovering
                  ? Colors.amber
                  : AppColors.borderOf(context),
              width: isHovering ? 2 : 1,
            ),
          ),
          child: InkWell(
            onTap: () => onFolderTap(folder),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isSmall = constraints.maxHeight < 200;
                final isTiny = constraints.maxHeight < 140;
                final iconSize = isTiny ? 32.0 : (isSmall ? 48.0 : 72.0);
                final fontSize = isTiny ? 11.0 : (isSmall ? 13.0 : 16.0);

                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.folder,
                      size: iconSize,
                      color: isHovering ? Colors.amber : AppColors.iconSecondary(context),
                    ),
                    SizedBox(height: isTiny ? 4 : (isSmall ? 8 : 16)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        folder.name,
                        style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontWeight: FontWeight.bold,
                          fontSize: fontSize,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: isTiny ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!isTiny) ...[
                      SizedBox(height: isSmall ? 4 : 8),
                      Text(
                        '$charCount character${charCount == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: isSmall ? 11 : 13,
                        ),
                      ),
                    ],
                    if (!isSmall) ...[
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.edit,
                              color: AppColors.iconSecondary(context),
                              size: 18,
                            ),
                            tooltip: 'Rename',
                            onPressed: () =>
                                onFolderDialogAction(FolderDialogAction.rename, folder: folder),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete,
                              color: Colors.redAccent,
                              size: 18,
                            ),
                            tooltip: 'Delete folder',
                            onPressed: () =>
                                onFolderDialogAction(FolderDialogAction.delete, folder: folder),
                          ),
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildCharacterCard(
    BuildContext context,
    CharacterCard character,
  ) {
    return LongPressDraggable<CharacterCard>(
      data: character,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 150,
          height: 200,
          child: Card(
            color: AppColors.cardOf(context),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: character.imagePath != null
                ? Image.file(
                    onResolveCharImage(character.imagePath!),
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    errorBuilder: (_, _, _) => Container(
                      color: AppColors.resolve(context, Colors.black26, Colors.black12),
                      child: Icon(Icons.person, color: AppColors.resolve(context, Colors.white24, Colors.black45), size: 48),
                    ),
                  )
                : Icon(Icons.person, size: 64, color: AppColors.resolve(context, Colors.white24, Colors.black45)),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildCharacterCardInner(context, character),
      ),
      child: _buildCharacterCardInner(context, character),
    );
  }

  Widget _buildCharacterCardInner(
    BuildContext context,
    CharacterCard character,
  ) {
    final charId = character.dbId ?? _getCharacterIdFromCard(character);
    final msgCount = messageCountCache[charId] ?? 0;

    final stringId = _getCharacterIdFromCard(character);
    final isSelectedCard = selectedCharacterIds.contains(stringId);

    return Card(
      color: AppColors.cardOf(context),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelectedCard
              ? Colors.purpleAccent
              : AppColors.borderOf(context).withValues(alpha: 0.3),
          width: isSelectedCard ? 2.5 : 1,
        ),
      ),
      child: Stack(
        children: [
          InkWell(
            onTap: () async {
              if (isSelecting || isOrganizing) {
                onToggleSelect(character);
                return;
              }
              await onTapCharacter(character);
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 200;
                final isTiny = constraints.maxWidth < 160;

                if (isTiny) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      character.imagePath != null
                          ? Image.file(
                              onResolveCharImage(character.imagePath!),
                              fit: BoxFit.cover,
                              alignment: Alignment.topCenter,
                              errorBuilder: (_, _, _) => Container(
                                color: AppColors.resolve(context, Colors.grey.shade800, Colors.grey.shade200),
                                child: Icon(
                                  Icons.person,
                                  size: 32,
                                  color: AppColors.resolve(context, Colors.white24, Colors.black45),
                                ),
                              ),
                            )
                          : Container(
                              color: AppColors.resolve(context, Colors.grey.shade800, Colors.grey.shade200),
                              child: Icon(
                                Icons.person,
                                size: 32,
                                color: AppColors.resolve(context, Colors.white24, Colors.black45),
                              ),
                            ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                AppColors.resolve(context, Colors.black87, Colors.black54),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          child: Text(
                            character.name,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: isCompact ? 4 : 3,
                      child: character.imagePath != null
                          ? Image.file(
                              onResolveCharImage(character.imagePath!),
                              fit: BoxFit.cover,
                              alignment: Alignment.topCenter,
                              errorBuilder: (_, _, _) => Container(
                                color: AppColors.resolve(context, Colors.grey.shade800, Colors.grey.shade200),
                                child: Icon(
                                  Icons.person,
                                  size: isCompact ? 32 : 64,
                                  color: AppColors.resolve(context, Colors.white24, Colors.black45),
                                ),
                              ),
                            )
                          : Container(
                              color: AppColors.resolve(context, Colors.grey.shade800, Colors.grey.shade200),
                              child: Icon(
                                Icons.person,
                                size: isCompact ? 32 : 64,
                                color: AppColors.resolve(context, Colors.white24, Colors.black45),
                              ),
                            ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Padding(
                        padding: EdgeInsets.all(isCompact ? 6.0 : 12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    character.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          fontSize: isCompact ? 12 : null,
                                        ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (msgCount > 0)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.chat_bubble_outline,
                                        size: 11,
                                        color: AppColors.iconSecondary(context),
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        '$msgCount',
                                        style: TextStyle(
                                          color: AppColors.textTertiary(context),
                                          fontSize: isCompact ? 10 : 11,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                            if (!isCompact) ...[
                              const SizedBox(height: 4),
                              if (character.tags.isNotEmpty)
                                Flexible(
                                  child: Wrap(
                                    spacing: 4,
                                    runSpacing: 2,
                                    children: character.tags
                                        .take(3)
                                        .map(
                                          (tag) => Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.resolve(
                                                context,
                                                Colors.amber.withValues(alpha: 0.22),
                                                const Color(0xFFFFF8E1),
                                              ),
                                              border: Border.all(
                                                color: AppColors.resolve(
                                                  context,
                                                  Colors.amber.withValues(alpha: 0.45),
                                                  Colors.amber.shade600.withValues(alpha: 0.35),
                                                ),
                                              ),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              tag,
                                              style: TextStyle(
                                                color: AppColors.resolve(
                                                  context,
                                                  Colors.amber.shade200,
                                                  Colors.amber.shade800,
                                                ),
                                                fontSize: 10,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                )
                              else
                                Flexible(
                                  child: Text(
                                    character.formattedDescription,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (isSelecting || isOrganizing)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isSelectedCard
                      ? (isOrganizing
                            ? Colors.blueAccent
                            : Colors.purpleAccent)
                      : AppColors.resolve(context, Colors.black54, Colors.black12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelectedCard
                        ? (isOrganizing
                              ? Colors.blueAccent
                              : Colors.purpleAccent)
                        : AppColors.resolve(context, Colors.white38, Colors.black38),
                    width: 2,
                  ),
                ),
                child: isSelectedCard
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
            ),
          if (!isSelecting && !isOrganizing)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onSecondaryTapUp: (details) {
                  final position = details.globalPosition;
                  showMenu<String>(
                    context: context,
                    position: RelativeRect.fromLTRB(
                      position.dx,
                      position.dy,
                      position.dx,
                      position.dy,
                    ),
                    color: AppColors.surfaceContainerOf(context),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    items: [
                      PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          leading: Icon(
                            Icons.edit,
                            color: AppColors.iconSecondary(context),
                            size: 20,
                          ),
                          title: Text(
                            'Edit Character',
                            style: TextStyle(color: AppColors.textPrimary(context)),
                          ),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'duplicate',
                        child: ListTile(
                          leading: Icon(
                            Icons.copy,
                            color: AppColors.iconSecondary(context),
                            size: 20,
                          ),
                          title: Text(
                            'Duplicate Character',
                            style: TextStyle(color: AppColors.textPrimary(context)),
                          ),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'export',
                        child: ListTile(
                          leading: Icon(
                            Icons.upload,
                            color: AppColors.iconSecondary(context),
                            size: 20,
                          ),
                          title: Text(
                            'Export PNG',
                            style: TextStyle(color: AppColors.textPrimary(context)),
                          ),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      if (activeFolderId != null)
                        const PopupMenuItem(
                          value: 'remove_folder',
                          child: ListTile(
                            leading: Icon(
                              Icons.folder_off,
                              color: Colors.amber,
                              size: 20,
                            ),
                            title: Text(
                              'Remove from Folder',
                              style: TextStyle(color: Colors.amber),
                            ),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(
                            Icons.delete,
                            color: Colors.redAccent,
                            size: 20,
                          ),
                          title: Text(
                            'Delete',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ).then((value) {
                    if (value == null) return;
                    onContextMenuAction(value, character);
                  });
                },
                child: const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGroupCard(
    BuildContext context,
    GroupChat group,
  ) {
    final characters = <CharacterCard>[];
    for (final id in group.characterIds) {
      final match = repo.characters
          .where((c) => _getCharacterIdFromCard(c) == id)
          .firstOrNull;
      if (match != null) characters.add(match);
    }

    return Card(
      color: AppColors.cardOf(context),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.purpleAccent.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        onTap: () async {
          await onTapGroup(group);
        },
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final h = constraints.maxHeight;
                final isCompactGroup = h < 220;
                final avatarSize = isCompactGroup ? 40.0 : 56.0;
                final avatarAreaH = isCompactGroup ? 50.0 : 80.0;
                final overlapStep = isCompactGroup ? 22.0 : 30.0;
                final nameFontSize = isCompactGroup ? 12.0 : 16.0;
                final subFontSize = isCompactGroup ? 10.0 : 13.0;
                final badgeFontSize = isCompactGroup ? 9.0 : 11.0;
                final iconSize = isCompactGroup ? 16.0 : 20.0;

                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(height: isCompactGroup ? 8 : 16),
                    SizedBox(
                      height: avatarAreaH,
                      width: double.infinity,
                      child: Center(
                        child: SizedBox(
                          width:
                              avatarSize +
                              (characters.take(4).length - 1) * overlapStep,
                          height: avatarAreaH,
                          child: Stack(
                            children: [
                              for (
                                int i = 0;
                                i < characters.take(4).length;
                                i++
                              )
                                Positioned(
                                  left: i * overlapStep,
                                  child: Container(
                                    width: avatarSize,
                                    height: avatarSize,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.purpleAccent,
                                        width: 2,
                                      ),
                                    ),
                                    child: characters[i].imagePath != null
                                        ? ClipOval(
                                            child: Image.file(
                                              onResolveCharImage(
                                                characters[i].imagePath!,
                                              ),
                                              fit: BoxFit.cover,
                                              alignment: Alignment.topCenter,
                                              errorBuilder: (_, _, _) => Container(
                                                color: AppColors.resolve(context, Colors.grey.shade700, Colors.grey.shade200),
                                                child: Icon(
                                                  Icons.person,
                                                  color: AppColors.resolve(context, Colors.white24, Colors.black45),
                                                ),
                                              ),
                                            ),
                                          )
                                        : Container(
                                            color: AppColors.resolve(context, Colors.grey.shade700, Colors.grey.shade200),
                                            child: Icon(
                                              Icons.person,
                                              color: AppColors.resolve(context, Colors.white24, Colors.black45),
                                              size: avatarSize * 0.5,
                                            ),
                                          ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: isCompactGroup ? 4 : 16),
                    Icon(
                      Icons.group,
                      color: Colors.purpleAccent,
                      size: iconSize,
                    ),
                    SizedBox(height: isCompactGroup ? 2 : 8),
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          group.name,
                          style: TextStyle(
                            color: AppColors.textPrimary(context),
                            fontWeight: FontWeight.bold,
                            fontSize: nameFontSize,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: isCompactGroup ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (!isCompactGroup) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${characters.length} character${characters.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: subFontSize,
                        ),
                      ),
                    ],
                    SizedBox(height: isCompactGroup ? 2 : 4),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isCompactGroup ? 4 : 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.purpleAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        group.turnOrder == TurnOrder.roundRobin
                            ? 'Round Robin'
                            : 'Random',
                        style: TextStyle(
                          color: Colors.purpleAccent.withValues(alpha: 0.8),
                          fontSize: badgeFontSize,
                        ),
                      ),
                    ),
                    SizedBox(height: isCompactGroup ? 4 : 0),
                  ],
                );
              },
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: AppColors.resolve(context, Colors.black54, Colors.black12),
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => onDeleteGroup(group),
                  child: const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Icon(
                      Icons.delete,
                      color: Colors.redAccent,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
