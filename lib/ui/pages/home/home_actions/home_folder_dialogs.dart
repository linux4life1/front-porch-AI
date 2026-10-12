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
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/home/home_actions/home_delete_actions.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

// Create / rename / delete folder dialogs. [onLeaveFolder] steps the grid
// out of a deleted folder when the user is standing inside it.

void showHomeCreateFolderDialog(
  BuildContext context,
  FolderService folderService, {
  String? parentId,
}) {
  final controller = TextEditingController();
  showWarmDialog(
    context,
    title: parentId != null ? 'New Subfolder' : 'New Folder',
    icon: Icons.create_new_folder,
    accent: AppColors.porchAmberOf(context),
    content: TextField(
      controller: controller,
      autofocus: true,
      style: TextStyle(color: AppColors.textPrimary(context)),
      decoration: InputDecoration(
        hintText: 'Folder name...',
        hintStyle: TextStyle(color: AppColors.textTertiary(context)),
      ),
      onSubmitted: (value) {
        if (value.trim().isNotEmpty) {
          folderService.createFolder(value.trim(), parentId: parentId);
          Navigator.pop(context);
        }
      },
    ),
    actions: [
      warmDialogCancel(context),
      warmDialogConfirm(
        context,
        label: 'Create',
        onPressed: () {
          if (controller.text.trim().isNotEmpty) {
            folderService.createFolder(
              controller.text.trim(),
              parentId: parentId,
            );
            Navigator.pop(context);
          }
        },
      ),
    ],
  );
}

void showHomeRenameFolderDialog(
  BuildContext context,
  CharacterFolder folder,
  FolderService folderService,
) {
  final controller = TextEditingController(text: folder.name);
  showWarmDialog(
    context,
    title: 'Rename Folder',
    icon: Icons.drive_file_rename_outline,
    accent: AppColors.porchAmberOf(context),
    content: TextField(
      controller: controller,
      autofocus: true,
      style: TextStyle(color: AppColors.textPrimary(context)),
      onSubmitted: (value) {
        if (value.trim().isNotEmpty) {
          folderService.renameFolder(folder.id, value.trim());
          Navigator.pop(context);
        }
      },
    ),
    actions: [
      warmDialogCancel(context),
      warmDialogConfirm(
        context,
        label: 'Rename',
        onPressed: () {
          if (controller.text.trim().isNotEmpty) {
            folderService.renameFolder(folder.id, controller.text.trim());
            Navigator.pop(context);
          }
        },
      ),
    ],
  );
}

void showHomeDeleteFolderDialog(
  BuildContext context,
  CharacterFolder folder,
  FolderService folderService, {
  required void Function(CharacterFolder folder) onLeaveFolder,
}) {
  final charCount = folderService
      .getCharactersInFolderRecursive(folder.id)
      .length;
  final groupCount = folderService.groupIdsInFolderRecursive(folder.id).length;
  showWarmDialog(
    context,
    title: 'Delete Folder',
    destructive: true,
    content: WarmDialogText(
      'Delete "${folder.name}"?\n\n'
      '• Delete Folder Only: the $charCount character'
      '${charCount == 1 ? '' : 's'}'
      '${groupCount > 0 ? ' and $groupCount group${groupCount == 1 ? '' : 's'}' : ''}'
      ' inside return to the top level.\n'
      '• Delete Folder + Characters: PERMANENTLY deletes the folder AND '
      'every character inside it (including subfolders)'
      '${groupCount > 0 ? '; groups are kept and return to the top level' : ''}.',
    ),
    actions: [
      warmDialogCancel(context),
      warmDialogConfirm(
        context,
        label: 'Delete Folder Only',
        onPressed: () {
          folderService.deleteFolder(folder.id);
          Navigator.pop(context);
          onLeaveFolder(folder);
        },
      ),
      if (charCount > 0)
        warmDialogConfirm(
          context,
          label: 'Delete Folder + Characters…',
          destructive: true,
          onPressed: () {
            Navigator.pop(context);
            _deleteFolderWithCharacters(
              context,
              folder,
              folderService,
              onLeaveFolder: onLeaveFolder,
            );
          },
        ),
    ],
  );
}

/// The nuclear option: PERMANENTLY delete a folder, its subfolders, and
/// every character inside them — gated by the typed-DELETE dialog and run
/// through the same shared purge pipeline as mass select-delete.
Future<void> _deleteFolderWithCharacters(
  BuildContext context,
  CharacterFolder folder,
  FolderService folderService, {
  required void Function(CharacterFolder folder) onLeaveFolder,
}) async {
  final repo = Provider.of<CharacterRepository>(context, listen: false);
  // Folder membership is stored as image basenames (with extension).
  final filenames = folderService
      .getCharactersInFolderRecursive(folder.id)
      .toSet();
  final cards = repo.characters
      .where(
        (c) =>
            c.imagePath != null &&
            filenames.contains(path.basename(c.imagePath!)),
      )
      .toList();
  final subfolders = folderService.getSubfolders(folder.id).length;

  await runHomeMassDelete(
    context,
    cards,
    title: 'Delete "${folder.name}" & ${cards.length} Characters?',
    message:
        'This will PERMANENTLY delete the folder "${folder.name}"'
        '${subfolders > 0 ? ', its subfolders,' : ''} and ALL '
        '${cards.length} character${cards.length == 1 ? '' : 's'} inside — '
        'their cards, image files, chat histories, and any linked worlds. '
        'There is no undo and no recycle bin.',
    afterDelete: () async {
      await folderService.deleteFolder(folder.id);
      onLeaveFolder(folder);
    },
  );
}

/// The grid's folder create / rename / delete requests.
void runHomeFolderDialogAction(
  BuildContext context,
  FolderDialogAction action, {
  CharacterFolder? folder,
  String? parentId,
  required void Function(CharacterFolder folder) onLeaveFolder,
}) {
  final folderService = Provider.of<FolderService>(context, listen: false);
  switch (action) {
    case FolderDialogAction.create:
      showHomeCreateFolderDialog(context, folderService, parentId: parentId);
      break;
    case FolderDialogAction.rename:
      if (folder != null) {
        showHomeRenameFolderDialog(context, folder, folderService);
      }
      break;
    case FolderDialogAction.delete:
      if (folder != null) {
        showHomeDeleteFolderDialog(
          context,
          folder,
          folderService,
          onLeaveFolder: onLeaveFolder,
        );
      }
      break;
  }
}
