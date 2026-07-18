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

/// Tap, context-menu, folder-navigation and toolbar-callback handlers.
///
/// Split out of the _HomePageState god file as a private extension
/// (part of the same library, so it keeps full access to page state).
extension _HomePageHandlers on _HomePageState {

  void _confirmDeleteGroup(BuildContext context, GroupChat group) {
    showWarmDialog(
      context,
      title: 'Delete Group',
      destructive: true,
      content: WarmDialogText(
        'Delete group "${group.name}"?\n\nThe characters themselves will NOT '
        'be deleted.',
      ),
      actions: [
        warmDialogCancel(context),
        warmDialogConfirm(
          context,
          label: 'Delete',
          destructive: true,
          onPressed: () async {
            Navigator.of(context).pop();
            final groupRepo = Provider.of<GroupChatRepository>(
              context,
              listen: false,
            );
            await groupRepo.delete(group.id);
            // No post-delete snackbar for groups (character delete shows one via the outer context)
          },
        ),
      ],
    );
  }

  // ─── Group Creation Dialog ──────────────────────────────────────

  void _showMoveToFolderDialog(
    BuildContext context,
    CharacterRepository repo,
    FolderService folderService,
  ) {
    final folders = folderService.folders.toList()
      ..sort((a, b) {
        final pathA = folderService.getFolderPath(a.id).toLowerCase();
        final pathB = folderService.getFolderPath(b.id).toLowerCase();
        return pathA.compareTo(pathB);
      });

    showWarmDialog(
      context,
      title:
          'Move ${_selectedCharacterIds.length} character${_selectedCharacterIds.length == 1 ? '' : 's'} to folder',
      icon: Icons.drive_file_move,
      accent: AppColors.porchHoneyOf(context),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                  '${folder.characterPaths.length} characters',
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
                  await _moveSelectedToFolder(
                    context,
                    folder.id,
                    repo,
                    folderService,
                  );
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
                  await _moveSelectedToFolder(
                    context,
                    folder.id,
                    repo,
                    folderService,
                  );
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

  Future<void> _moveSelectedToFolder(
    BuildContext context,
    String folderId,
    CharacterRepository repo,
    FolderService folderService,
  ) async {
    // Resolve selected IDs back to imagePaths
    for (final id in _selectedCharacterIds) {
      final card = repo.characters
          .where((c) => _getCharacterIdFromCard(c) == id)
          .firstOrNull;
      if (card?.imagePath != null) {
        await folderService.addToFolder(folderId, card!.imagePath!);
      }
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Moved ${_selectedCharacterIds.length} character${_selectedCharacterIds.length == 1 ? '' : 's'} to folder',
          ),
        ),
      );
    }
    _cancelSelection();
  }

  // (old group creator dialog variables and body fully removed — 2026 overhaul)

  // ─── Folder Actions ─────────────────────────────────────────────

  void _createFolder(
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

  void _renameFolder(
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

  void _deleteFolder(
    BuildContext context,
    CharacterFolder folder,
    FolderService folderService,
  ) {
    final charCount = folderService
        .getCharactersInFolderRecursive(folder.id)
        .length;
    showWarmDialog(
      context,
      title: 'Delete Folder',
      destructive: true,
      content: WarmDialogText(
        'Delete "${folder.name}"?\n\n'
        '• Delete Folder Only: the $charCount character'
        '${charCount == 1 ? '' : 's'} inside return to the top level.\n'
        '• Delete Folder + Characters: PERMANENTLY deletes the folder AND '
        'every character inside it (including subfolders).',
      ),
      actions: [
        warmDialogCancel(context),
        warmDialogConfirm(
          context,
          label: 'Delete Folder Only',
          onPressed: () {
            folderService.deleteFolder(folder.id);
            Navigator.pop(context);
            _leaveDeletedFolder(folder.id);
          },
        ),
        if (charCount > 0)
          warmDialogConfirm(
            context,
            label: 'Delete Folder + Characters…',
            destructive: true,
            onPressed: () {
              Navigator.pop(context);
              _deleteFolderWithCharacters(folder, folderService);
            },
          ),
      ],
    );
  }

  /// If the user is standing inside the folder being deleted, step back out.
  void _leaveDeletedFolder(String folderId) {
    if (_activeFolderId != folderId) return;
    applyState(() {
      if (_folderStack.isNotEmpty) {
        _activeFolderId = _folderStack.removeLast();
      } else {
        _activeFolderId = null;
      }
    });
  }

  /// The nuclear option: PERMANENTLY delete a folder, its subfolders, and
  /// every character inside them — gated by the typed-DELETE dialog and run
  /// through the same shared purge pipeline as mass select-delete.
  Future<void> _deleteFolderWithCharacters(
    CharacterFolder folder,
    FolderService folderService,
  ) async {
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
    final subfolders = folderService
        .getSubfolders(folder.id)
        .length;

    await _runMassDelete(
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
        _leaveDeletedFolder(folder.id);
      },
    );
  }

  // ─── Character Actions ──────────────────────────────────────────

  ButtonStyle _buttonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: AppColors.resolve(
        context,
        Colors.white.withValues(alpha: 0.1),
        Colors.black.withValues(alpha: 0.05),
      ),
      foregroundColor: AppColors.textPrimary(context),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: AppColors.resolve(context, Colors.white24, Colors.black26),
        ),
      ),
    );
  }
}
