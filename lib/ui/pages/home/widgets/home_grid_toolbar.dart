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
// along with Front Porch AI. If not, see https://www.gnu.org/licenses/.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/home/widgets/toolbar/toolbar.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/character_card_grid.dart'
    show FolderDialogAction;

export 'package:front_porch_ai/ui/pages/home/widgets/toolbar/library_selection_actions.dart';

/// The home grid's top toolbar: selection/organize header or folder breadcrumb
/// or the Characters/Stories mode toggle, plus the sort dropdown, grid-size
/// slider, and the refresh / multi-select / organize / new-folder / import
/// actions.
///
/// There is no fixed window size. [LayoutBuilder] sheds the slider, then the
/// sort labels, then the inline actions, so a resized window never overflows.
class HomeGridToolbar extends StatelessWidget {
  const HomeGridToolbar({
    super.key,
    required this.isSelecting,
    required this.isOrganizing,
    required this.activeFolderId,
    required this.selectedCount,
    required this.sortMode,
    required this.gridScale,
    required this.modeToggle,
    required this.repo,
    required this.folderService,
    required this.onCancelSelection,
    required this.onFolderNavigateBack,
    required this.onFolderJump,
    required this.onSortChanged,
    required this.onGridScaleChanged,
    required this.onGridScaleChangeEnd,
    required this.onToggleSelectMode,
    required this.onToggleOrganizeMode,
    required this.onFolderDialogAction,
    required this.onImport,
    this.hiddenSelectedCount = 0,
    this.selectionActions,
    this.liveDrag = false,
    this.onDropOnLevel,
  });

  final bool isSelecting;
  final bool isOrganizing;
  final String? activeFolderId;

  /// Characters + groups — groups are selectable alongside characters now.
  final int selectedCount;

  /// How many of [selectedCount] the current search or folder hides.
  final int hiddenSelectedCount;

  /// Select all / Select none in the selection header; none without it.
  final LibrarySelectionActions? selectionActions;

  /// A card or the picks are being dragged: the path becomes drop targets.
  final bool liveDrag;

  /// A drop on a level of the path; null folder id is the top level.
  final void Function(Object item, String? folderId)? onDropOnLevel;
  final String sortMode;
  final double gridScale;
  final Widget modeToggle;
  final CharacterRepository repo;
  final FolderService folderService;
  final VoidCallback onCancelSelection;
  final VoidCallback onFolderNavigateBack;

  /// Breadcrumb jump — null = the library top level, else an ancestor folder.
  final void Function(String? folderId) onFolderJump;
  final void Function(String mode) onSortChanged;
  final void Function(double scale) onGridScaleChanged;
  final void Function(double scale)? onGridScaleChangeEnd;
  final VoidCallback? onToggleSelectMode;
  final VoidCallback? onToggleOrganizeMode;
  final void Function(
    FolderDialogAction action, {
    CharacterFolder? folder,
    String? parentId,
  })
  onFolderDialogAction;
  final void Function(String source) onImport;

  List<Widget> _leadingChildren(BuildContext context, double toggleMaxWidth) {
    if (activeFolderId != null) {
      return [
        IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Up one level',
          visualDensity: VisualDensity.compact,
          onPressed: onFolderNavigateBack,
        ),
        const SizedBox(width: 8),
        Flexible(child: _breadcrumb()),
      ];
    }
    // ConstrainedBox (not Flexible) so the toggle keeps its natural width
    // when it fits — a Flexible here would steal space from the sort
    // control and shove it toward the actions.
    return [
      ConstrainedBox(
        constraints: BoxConstraints(maxWidth: toggleMaxWidth),
        child: modeToggle,
      ),
    ];
  }

  Widget _breadcrumb({bool dropTargets = false}) => HomeToolbarBreadcrumb(
    activeFolderId: activeFolderId,
    folders: folderService.folders,
    onFolderJump: onFolderJump,
    dropTargets: dropTargets,
    onDropOnLevel: onDropOnLevel,
  );

  Widget _sortControl({required bool labeled}) => HomeToolbarSortControl(
    sortMode: sortMode,
    labeled: labeled,
    onSortChanged: onSortChanged,
  );

  Widget _scaleSlider() => HomeToolbarScaleSlider(
    gridScale: gridScale,
    onChanged: onGridScaleChanged,
    onChangeEnd: onGridScaleChangeEnd,
  );

  List<Widget> _actionButtons(BuildContext context) => homeToolbarActionButtons(
    context,
    activeFolderId: activeFolderId,
    repo: repo,
    onToggleSelectMode: onToggleSelectMode,
    onToggleOrganizeMode: onToggleOrganizeMode,
    onFolderDialogAction: onFolderDialogAction,
    onImport: onImport,
  );

  Widget _overflowActions() => HomeToolbarOverflowActions(
    activeFolderId: activeFolderId,
    repo: repo,
    onToggleSelectMode: onToggleSelectMode,
    onToggleOrganizeMode: onToggleOrganizeMode,
    onFolderDialogAction: onFolderDialogAction,
    onImport: onImport,
  );

  /// The toolbar while a card or the picks are being dragged (library
  /// phase 3), as in the approved sketch: the path, each level of it a drop
  /// target, and a hint; sort, refresh and New Folder stay on the right.
  Widget _dragRow(BuildContext context, double width) {
    final inFolder = activeFolderId != null;
    final room = width - 560;
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              if (inFolder) ...[
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Up one level',
                  visualDensity: VisualDensity.compact,
                  onPressed: onFolderNavigateBack,
                ),
                const SizedBox(width: 8),
                Flexible(child: _breadcrumb(dropTargets: true)),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  inFolder
                      ? 'Drop on a folder, or on a level of the path'
                      : 'Drop on a folder',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (room >= 96) ...[
          const SizedBox(width: 12),
          _sortControl(labeled: room >= 240),
          IconButton(
            tooltip: 'Refresh character list',
            icon: const Icon(Icons.refresh),
            visualDensity: VisualDensity.compact,
            onPressed: () => repo.loadCharacters(),
          ),
          IconButton(
            tooltip: inFolder ? 'New Subfolder' : 'New Folder',
            icon: Icon(
              Icons.create_new_folder_outlined,
              color: inFolder ? AppColors.porchAmberOf(context) : null,
            ),
            visualDensity: VisualDensity.compact,
            onPressed: () => onFolderDialogAction(
              FolderDialogAction.create,
              parentId: activeFolderId,
            ),
          ),
        ],
      ],
    );
  }

  /// While picking: the header keeps its room on the left and the sort, card
  /// size and library actions sit on the right, as in the approved sketch.
  /// As the window narrows the slider goes first, then the sort label, then
  /// the inline actions (into the ⋮ menu); a squeezed window keeps only the
  /// header. Widths are high-side estimates, like the browsing row's.
  Widget _pickingRow(BuildContext context, double width) {
    final room = width - 480;
    final inlineActions = room >= 278;
    return Row(
      children: [
        Expanded(
          child: Row(
            children: homeToolbarSelectionChildren(
              context,
              selectedCount: selectedCount,
              hiddenSelectedCount: hiddenSelectedCount,
              isOrganizing: isOrganizing,
              actions: selectionActions,
              onCancelSelection: onCancelSelection,
            ),
          ),
        ),
        if (room >= 96) ...[
          const SizedBox(width: 12),
          _sortControl(labeled: room >= 420),
          if (room >= 540) _scaleSlider(),
          if (inlineActions) ..._actionButtons(context),
          if (!inlineActions) _overflowActions(),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          if (liveDrag) return _dragRow(context, width);
          if (isSelecting || isOrganizing) return _pickingRow(context, width);
          // Content-area widths, not window sizes. Sidebar already ate its
          // share; these decide what still fits in the remaining strip.
          final showSlider = width >= 720;
          final labeledSort = width >= 520;
          final inlineActions = width >= 440;
          // High-side estimates so the toggle goes compact a few px early
          // rather than the row overflowing. Not a window-size assumption.
          var reserved = 12.0;
          reserved += labeledSort ? 190 : 48;
          if (showSlider) reserved += 120;
          reserved += inlineActions ? 230 : 48;
          final toggleMax = math.max(0.0, width - reserved);
          return Row(
            children: [
              ..._leadingChildren(context, toggleMax),
              const SizedBox(width: 12),
              _sortControl(labeled: labeledSort),
              if (showSlider) _scaleSlider(),
              const Spacer(),
              if (inlineActions) ..._actionButtons(context),
              if (!inlineActions) _overflowActions(),
            ],
          );
        },
      ),
    );
  }
}
