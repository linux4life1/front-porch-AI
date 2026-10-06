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

part of 'home_grid_toolbar.dart';

/// The toolbar's inline library actions and the narrow-window overflow menu.
extension _HomeGridToolbarActions on HomeGridToolbar {
  List<Widget> _actionButtons(BuildContext context) {
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
        itemBuilder: (_) => _importItems(context),
      ),
    ];
  }

  List<PopupMenuEntry<String>> _importItems(BuildContext context) {
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
    ];
  }

  Widget _overflowActions(BuildContext context) {
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
        ..._importItems(context),
      ],
    );
  }
}
