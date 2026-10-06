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

/// The move-to-folder picker and the bulk move behind it.
extension _HomePageMove on _HomePageState {
  /// The ONE warm folder-picker dialog. Callers supply the [title] and what
  /// actually moves via [onMove] — the multi-select toolbar moves the whole
  /// selection (characters + groups) while a group card's context menu moves
  /// just that group. Generalized instead of duplicated per surface.
  ///
  /// [onMove] receives `null` when the user picks "Home (no folder)". That
  /// entry is the only always-reachable way *out* of a folder: the card menu's
  /// "Remove from Folder" only appears while you are browsing inside the
  /// folder, so a card found via global search had no exit before. Because
  /// every folder is listed by its full path, picking an ancestor is also how
  /// you move a card up one level when nested.
  void _showMoveToFolderDialog(
    BuildContext context,
    FolderService folderService, {
    required String title,
    required Future<void> Function(String? folderId) onMove,
  }) {
    final folders = folderService.folders.toList()
      ..sort((a, b) {
        final pathA = folderService.getFolderPath(a.id).toLowerCase();
        final pathB = folderService.getFolderPath(b.id).toLowerCase();
        return pathA.compareTo(pathB);
      });

    showWarmDialog(
      context,
      title: title,
      icon: Icons.drive_file_move,
      accent: AppColors.porchHoneyOf(context),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                Icons.home_outlined,
                color: AppColors.porchHoneyOf(context),
              ),
              title: Text(
                'Home (no folder)',
                style: TextStyle(color: AppColors.textPrimary(context)),
              ),
              subtitle: Text(
                'Move back out to the library top level',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 12,
                ),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              onTap: () async {
                Navigator.pop(context);
                await onMove(null);
              },
            ),
            Divider(color: AppColors.borderOf(context).withValues(alpha: 0.5)),
            if (folders.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No folders yet. Create one below.',
                  style: TextStyle(color: AppColors.textTertiary(context)),
                ),
              ),
            ...folders.map((folder) {
              final folderPath = folderService.getFolderPath(folder.id);
              final isSubfolder = folder.parentId != null;
              final memberCount =
                  folder.characterPaths.length + folder.groupIds.length;
              return ListTile(
                leading: Icon(
                  isSubfolder ? Icons.subdirectory_arrow_right : Icons.folder,
                  color: AppColors.porchAmberOf(context),
                ),
                title: Text(
                  folderPath,
                  style: TextStyle(color: AppColors.textPrimary(context)),
                ),
                subtitle: Text(
                  '$memberCount item${memberCount == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 12,
                  ),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await onMove(folder.id);
                },
              );
            }),
            Divider(color: AppColors.borderOf(context).withValues(alpha: 0.5)),
            ListTile(
              leading: Icon(
                Icons.create_new_folder,
                color: AppColors.porchHoneyOf(context),
              ),
              title: Text(
                'New Folder',
                style: TextStyle(color: AppColors.porchHoneyOf(context)),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              onTap: () async {
                Navigator.pop(context);
                final name = await _promptFolderName(context);
                if (name != null && name.isNotEmpty && context.mounted) {
                  final folder = await folderService.createFolder(name);
                  await onMove(folder.id);
                }
              },
            ),
          ],
        ),
      ),
      actions: [warmDialogCancel(context)],
    );
  }

  Future<String?> _promptFolderName(BuildContext context) async {
    final controller = TextEditingController();
    return showWarmDialog<String>(
      context,
      title: 'New Folder',
      icon: Icons.create_new_folder,
      accent: AppColors.porchAmberOf(context),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: TextStyle(color: AppColors.textPrimary(context)),
        decoration: const InputDecoration(hintText: 'Folder name'),
        onSubmitted: (val) => Navigator.pop(context, val),
      ),
      actions: [
        warmDialogCancel(context),
        warmDialogConfirm(
          context,
          label: 'Create',
          onPressed: () => Navigator.pop(context, controller.text),
        ),
      ],
    );
  }

  /// [folderId] is `null` for "Home (no folder)" — the whole selection moves
  /// back out to the library top level instead of into a folder.
  Future<void> _moveSelectedToFolder(
    BuildContext context,
    String? folderId,
    CharacterRepository repo,
    FolderService folderService,
  ) async {
    // Resolve selected IDs back to imagePaths. Groups ride the same move:
    // their selection ids ARE their group ids. One moveMany for the lot —
    // Select all can hand over hundreds of cards (#347).
    final byId = <String, CharacterCard>{};
    for (final c in repo.characters) {
      byId.putIfAbsent(_getCharacterIdFromCard(c), () => c);
    }
    final moved = await folderService.moveMany(
      folderId: folderId,
      characterPaths: [
        for (final id in _selectedCharacterIds) ?byId[id]?.imagePath,
      ],
      groupIds: _selectedGroupIds,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            folderId == null
                ? 'Moved $moved item${moved == 1 ? '' : 's'} out of the folder'
                : 'Moved $moved item${moved == 1 ? '' : 's'} to folder',
          ),
        ),
      );
    }
    _cancelSelection();
  }
}
