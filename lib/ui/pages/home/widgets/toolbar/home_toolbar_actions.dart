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

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/character_card_grid.dart'
    show FolderDialogAction;

/// The toolbar's inline library actions: refresh, multi-select, organize,
/// new (sub)folder, and the import menu. A list so the caller spreads them
/// straight into its row.
List<Widget> homeToolbarActionButtons(
  BuildContext context, {
  required String? activeFolderId,
  required CharacterRepository repo,
  required VoidCallback? onToggleSelectMode,
  required VoidCallback? onToggleOrganizeMode,
  required void Function(
    FolderDialogAction action, {
    CharacterFolder? folder,
    String? parentId,
  })
  onFolderDialogAction,
  required void Function(String source) onImport,
}) {
  return [
    IconButton(
      tooltip:
          'Refresh character list (pick up external changes, e.g. Character Card Forge)',
      icon: const Icon(Icons.refresh),
      visualDensity: VisualDensity.compact,
      onPressed: () => repo.loadCharacters(),
    ),
    IconButton(
      tooltip: 'Multi-select characters (for organizing, moving, etc.)',
      icon: const Icon(Icons.check_box_outlined),
      visualDensity: VisualDensity.compact,
      onPressed: onToggleSelectMode,
    ),
    IconButton(
      tooltip: 'Organize into folders',
      icon: Icon(
        Icons.drive_file_move_outlined,
        color: AppColors.porchHoneyOf(context),
      ),
      visualDensity: VisualDensity.compact,
      onPressed: onToggleOrganizeMode,
    ),
    if (activeFolderId == null)
      IconButton(
        tooltip: 'New Folder',
        icon: const Icon(Icons.create_new_folder_outlined),
        visualDensity: VisualDensity.compact,
        onPressed: () => onFolderDialogAction(FolderDialogAction.create),
      ),
    if (activeFolderId != null)
      IconButton(
        tooltip: 'New Subfolder',
        icon: Icon(
          Icons.create_new_folder_outlined,
          color: AppColors.porchAmberOf(context),
        ),
        visualDensity: VisualDensity.compact,
        onPressed: () => onFolderDialogAction(
          FolderDialogAction.create,
          parentId: activeFolderId,
        ),
      ),
    PopupMenuButton<String>(
      tooltip: 'Import or discover characters',
      icon: const Icon(Icons.download),
      color: AppColors.surfaceContainerOf(context),
      onSelected: onImport,
      itemBuilder: (_) => homeToolbarImportItems(context),
    ),
  ];
}

/// The import menu's entries; each value is the source passed to onImport.
List<PopupMenuEntry<String>> homeToolbarImportItems(BuildContext context) {
  final iconColor = AppColors.iconSecondary(context);
  Widget row(IconData icon, String label) => Row(
    children: [
      Icon(icon, size: 18, color: iconColor),
      const SizedBox(width: 8),
      Text(label),
    ],
  );
  return [
    PopupMenuItem(value: 'cards', child: row(Icons.download, 'Import Cards')),
    PopupMenuItem(
      value: 'folder',
      child: row(Icons.library_add, 'Import Folder'),
    ),
    PopupMenuItem(
      value: 'byaf',
      child: row(Icons.archive_outlined, 'Import Backyard AI (.byaf)'),
    ),
    PopupMenuItem(
      value: 'porch',
      child: row(Icons.inventory_2_outlined, 'Import .porch / .porchpack'),
    ),
  ];
}

/// The narrow-window ⋮ menu holding every library action.
class HomeToolbarOverflowActions extends StatelessWidget {
  const HomeToolbarOverflowActions({
    super.key,
    required this.activeFolderId,
    required this.repo,
    required this.onToggleSelectMode,
    required this.onToggleOrganizeMode,
    required this.onFolderDialogAction,
    required this.onImport,
  });

  final String? activeFolderId;
  final CharacterRepository repo;
  final VoidCallback? onToggleSelectMode;
  final VoidCallback? onToggleOrganizeMode;
  final void Function(
    FolderDialogAction action, {
    CharacterFolder? folder,
    String? parentId,
  })
  onFolderDialogAction;
  final void Function(String source) onImport;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More library actions',
      icon: const Icon(Icons.more_vert),
      color: AppColors.surfaceContainerOf(context),
      onSelected: (value) {
        switch (value) {
          case 'refresh':
            repo.loadCharacters();
          case 'select':
            onToggleSelectMode?.call();
          case 'organize':
            onToggleOrganizeMode?.call();
          case 'new_folder':
            onFolderDialogAction(
              FolderDialogAction.create,
              parentId: activeFolderId,
            );
          case 'cards':
          case 'folder':
          case 'byaf':
          case 'porch':
            onImport(value);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'refresh', child: Text('Refresh list')),
        const PopupMenuItem(value: 'select', child: Text('Multi-select')),
        const PopupMenuItem(value: 'organize', child: Text('Organize')),
        PopupMenuItem(
          value: 'new_folder',
          child: Text(activeFolderId == null ? 'New Folder' : 'New Subfolder'),
        ),
        const PopupMenuDivider(),
        ...homeToolbarImportItems(context),
      ],
    );
  }
}
