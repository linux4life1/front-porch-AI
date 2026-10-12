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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:front_porch_ai/ui/pages/home/cards/cards.dart';
import 'package:front_porch_ai/ui/pages/home/library_selection.dart';
import 'package:front_porch_ai/ui/pages/home/widgets/widgets.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/character_card_grid.dart'
    show FolderDialogAction;
import 'package:front_porch_ai/ui/widgets/library_view.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Folder / group / character cells of the home library grid, plus the box
/// select and pick-click wiring when a [LibrarySelection] is present.
class CharacterLibraryGrid extends StatelessWidget {
  const CharacterLibraryGrid({
    super.key,
    required this.view,
    required this.searchQuery,
    required this.activeFolderId,
    required this.messageCountCache,
    required this.gridScale,
    required this.isSelecting,
    required this.isOrganizing,
    required this.selectedCharacterIds,
    required this.selectedGroupIds,
    required this.gridScrollController,
    required this.groupRepo,
    required this.imageCacheEpoch,
    required this.selection,
    required this.onTapCharacter,
    required this.onTapGroup,
    required this.onToggleSelect,
    required this.onToggleSelectGroup,
    required this.onContextMenuAction,
    required this.onGroupContextMenuAction,
    required this.onAcceptFolderDrop,
    required this.onFolderDialogAction,
    required this.onFolderTap,
    required this.onResolveCharImage,
  });

  final LibraryView view;
  final String searchQuery;
  final String? activeFolderId;
  final Map<String, int> messageCountCache;
  final double gridScale;
  final bool isSelecting;
  final bool isOrganizing;
  final Set<String> selectedCharacterIds;
  final Set<String> selectedGroupIds;
  final ScrollController gridScrollController;
  final GroupChatRepository groupRepo;
  final int imageCacheEpoch;
  final LibrarySelection? selection;

  final Future<void> Function(CharacterCard character) onTapCharacter;
  final Future<void> Function(GroupChat group) onTapGroup;
  final void Function(CharacterCard character) onToggleSelect;
  final void Function(GroupChat group) onToggleSelectGroup;
  final void Function(String action, CharacterCard character)
  onContextMenuAction;
  final void Function(String action, GroupChat group)? onGroupContextMenuAction;
  final void Function(Object item, CharacterFolder folder) onAcceptFolderDrop;
  final void Function(
    FolderDialogAction action, {
    CharacterFolder? folder,
    String? parentId,
  })
  onFolderDialogAction;
  final void Function(CharacterFolder folder) onFolderTap;
  final File Function(CharacterCard card) onResolveCharImage;

  @override
  Widget build(BuildContext context) {
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
    // What a held, picked card drags: every pick (library phase 3).
    final payload = sel != null && picking && !sel.isEmpty ? sel.payload : null;

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
              // Esc called the drag off: the tile stops offering to take it.
              acceptsDrops: !(sel?.dragCalledOff ?? false),
              onAcceptFolderDrop: onAcceptFolderDrop,
              onFolderTap: onFolderTap,
              onFolderDialogAction: onFolderDialogAction,
              onResolveCharImage: onResolveCharImage,
            );
          }
          final groupOffset = index - folders.length;
          if (groupOffset < groups.length) {
            final group = groups[groupOffset];
            final picked = selectedGroupIds.contains(group.id);
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
              dragSelection: picked ? payload : null,
              dimmed: picked && (sel?.dragsPicks ?? false),
              onDragStarted: sel == null
                  ? null
                  : () => _dragStarted(sel, picked ? payload : null),
              onDragEnded: sel?.endDrag,
            );
          }
          final character = displayCharacters[groupOffset - groups.length];
          final key = character.stableGroupId;
          final picked = selectedCharacterIds.contains(key);
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
            imageCacheEpoch: imageCacheEpoch,
            dragSelection: picked ? payload : null,
            dimmed: picked && (sel?.dragsPicks ?? false),
            onDragStarted: sel == null
                ? null
                : () => _dragStarted(sel, picked ? payload : null),
            onDragEnded: sel?.endDrag,
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

  void _dragStarted(LibrarySelection sel, LibraryDragPayload? picks) =>
      sel.beginDrag(picks?.count ?? 1, picks: picks != null);
}
