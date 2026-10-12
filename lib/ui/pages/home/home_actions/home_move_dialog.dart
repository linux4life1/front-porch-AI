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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/home/library_selection.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

// The move-to-folder picker and the bulk move behind it.

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
void showHomeMoveToFolderDialog(
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
Future<void> moveHomeSelectionToFolder(
  BuildContext context,
  String? folderId,
  CharacterRepository repo,
  FolderService folderService,
  LibrarySelection selection,
) async {
  // One moveMany for the whole selection (characters and groups), then
  // the selection ends — LibrarySelection.moveTo, shared with the drag.
  final moved = await selection.moveTo(
    folderId,
    folders: folderService,
    library: repo.characters,
  );
  if (context.mounted) snackHomeMoved(context, moved, folderId);
}

void snackHomeMoved(BuildContext context, int moved, String? folderId) {
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

/// The multi-select toolbar's Move: the title counts [picks] the way the grid
/// counts them, and the whole [selection] moves in one go.
void showHomeMoveSelectionDialog(
  BuildContext context, {
  required SelectionTally picks,
  required LibrarySelection selection,
}) {
  final repo = Provider.of<CharacterRepository>(context, listen: false);
  final folderService = Provider.of<FolderService>(context, listen: false);
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
  showHomeMoveToFolderDialog(
    context,
    folderService,
    title: title,
    onMove: (folderId) => moveHomeSelectionToFolder(
      context,
      folderId,
      repo,
      folderService,
      selection,
    ),
  );
}
