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
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/character_card_grid.dart'
    show FolderDialogAction;

part 'home_grid_toolbar.actions.dart';

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
  });

  final bool isSelecting;
  final bool isOrganizing;
  final String? activeFolderId;

  /// Characters + groups — groups are selectable alongside characters now.
  final int selectedCount;
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

  static const _sortItems = <(String, String)>[
    ('name', 'Name (A\u2192Z)'),
    ('recent', 'Recent Activity'),
    ('importDate', 'Import Date'),
    ('messages', 'Messages Sent'),
  ];

  /// Ancestor chain for the active folder, root-first with the current
  /// folder last (subfolder cards only render inside their parent, so the
  /// parent chain is the full navigation path).
  List<CharacterFolder> _trail() {
    final trail = <CharacterFolder>[];
    var cur = activeFolderId;
    while (cur != null) {
      final folder = folderService.folders
          .where((f) => f.id == cur)
          .firstOrNull;
      if (folder == null) break;
      trail.insert(0, folder);
      cur = folder.parentId;
    }
    return trail;
  }

  /// Clickable path — "My Characters / folder1 / folder2 / current". Every
  /// segment but the current one jumps straight there, so deep nesting never
  /// needs N back-taps to escape.
  Widget _breadcrumb(BuildContext context) {
    final trail = _trail();
    final crumbStyle = TextStyle(
      color: AppColors.textSecondary(context),
      fontSize: 15,
    );
    Widget crumb(String label, String? target) => InkWell(
      onTap: () => onFolderJump(target),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(label, style: crumbStyle),
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      // Keep the tail (the folder you're standing in) visible on long paths.
      reverse: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          crumb('My Characters', null),
          for (var i = 0; i < trail.length; i++) ...[
            Text('/', style: TextStyle(color: AppColors.textTertiary(context))),
            if (i < trail.length - 1)
              crumb(trail[i].name, trail[i].id)
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  trail[i].name,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ],
      ),
    );
  }

  List<Widget> _leadingChildren(BuildContext context, double toggleMaxWidth) {
    if (isSelecting || isOrganizing) {
      return [
        IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancel selection',
          visualDensity: VisualDensity.compact,
          onPressed: onCancelSelection,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            '$selectedCount selected',
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: isOrganizing
                  ? AppColors.porchHoneyOf(context)
                  : AppColors.porchTerracottaOf(context),
            ),
          ),
        ),
      ];
    }
    if (activeFolderId != null) {
      return [
        IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Up one level',
          visualDensity: VisualDensity.compact,
          onPressed: onFolderNavigateBack,
        ),
        const SizedBox(width: 8),
        Flexible(child: _breadcrumb(context)),
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

  Widget _sortControl(BuildContext context, {required bool labeled}) {
    if (!labeled) {
      return PopupMenuButton<String>(
        tooltip:
            'Sort: ${_sortItems.where((e) => e.$1 == sortMode).firstOrNull?.$2 ?? sortMode}',
        icon: Icon(
          Icons.sort,
          size: 18,
          color: AppColors.iconSecondary(context),
        ),
        initialValue: sortMode,
        color: AppColors.surfaceContainerOf(context),
        onSelected: onSortChanged,
        itemBuilder: (_) => [
          for (final item in _sortItems)
            PopupMenuItem(value: item.$1, child: Text(item.$2)),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
          items: [
            for (final item in _sortItems)
              DropdownMenuItem(value: item.$1, child: Text(item.$2)),
          ],
          onChanged: (value) {
            if (value != null) onSortChanged(value);
          },
        ),
      ),
    );
  }

  Widget _scaleSlider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SizedBox(
        width: 100,
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
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                  activeTrackColor: AppColors.porchHoneyOf(
                    context,
                  ).withValues(alpha: 0.7),
                  inactiveTrackColor: AppColors.borderOf(
                    context,
                  ).withValues(alpha: 0.4),
                  thumbColor: AppColors.porchHoneyOf(context),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          // Content-area widths, not window sizes. Sidebar already ate its
          // share; these decide what still fits in the remaining strip.
          final showSlider = width >= 720;
          final labeledSort = width >= 520;
          final inlineActions = width >= 440;
          final browsing = !isSelecting && !isOrganizing;
          // High-side estimates so the toggle goes compact a few px early
          // rather than the row overflowing. Not a window-size assumption.
          var reserved = 0.0;
          if (browsing) {
            reserved += 12;
            reserved += labeledSort ? 190 : 48;
            if (showSlider) reserved += 120;
            reserved += inlineActions ? 230 : 48;
          }
          final toggleMax = math.max(0.0, width - reserved);
          return Row(
            children: [
              ..._leadingChildren(context, toggleMax),
              if (browsing) ...[
                const SizedBox(width: 12),
                _sortControl(context, labeled: labeledSort),
                if (showSlider) _scaleSlider(context),
              ],
              const Spacer(),
              if (browsing && inlineActions) ..._actionButtons(context),
              if (browsing && !inlineActions) _overflowActions(context),
            ],
          );
        },
      ),
    );
  }
}
