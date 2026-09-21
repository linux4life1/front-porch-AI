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

/// Delete / mass-delete, edit, and duplicate. Import lives in
/// home_page_dialogs.import.dart (same library).
extension _HomePageDialogs on _HomePageState {
  void _confirmDeleteCharacter(BuildContext context, CharacterCard character) {
    showWarmDialog(
      context,
      title: 'Delete Character',
      icon: Icons.warning_amber_rounded,
      destructive: true,
      content: WarmDialogText(
        'Are you sure you want to delete "${character.name}"?\n\nThis will '
        'permanently remove the character card and its image file. This action '
        'cannot be undone.',
      ),
      actions: [
        warmDialogCancel(context),
        warmDialogConfirm(
          context,
          label: 'Delete',
          destructive: true,
          onPressed: () async {
            Navigator.of(context).pop();
            final repo = Provider.of<CharacterRepository>(
              context,
              listen: false,
            );
            final worldRepo = Provider.of<WorldRepository>(
              context,
              listen: false,
            );
            final storageService = Provider.of<StorageService>(
              context,
              listen: false,
            );
            await repo.deleteCharacter(
              character,
              worldRepo: worldRepo,
              chatsDir: storageService.chatsDir,
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${character.name} has been deleted.')),
              );
            }
          },
        ),
      ],
    );
  }

  /// Mass delete for the select-mode bar: resolve the selection ids (the
  /// imagePath-basename scheme _toggleSelect writes) back to cards, gather any
  /// selected groups, then run the shared severe-confirm purge on both.
  Future<void> _massDeleteSelected(Set<String> ids) async {
    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final groupRepo = Provider.of<GroupChatRepository>(context, listen: false);
    final cards = repo.characters.where((c) {
      final id = c.imagePath != null
          ? path.basenameWithoutExtension(c.imagePath!)
          : c.name.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_');
      return ids.contains(id);
    }).toList();
    final groups = groupRepo.groups
        .where((g) => _selectedGroupIds.contains(g.id))
        .toList();
    if (cards.isEmpty && groups.isEmpty) return;

    final total = cards.length + groups.length;
    final what = groups.isEmpty
        ? 'Character${cards.length == 1 ? '' : 's'}'
        : cards.isEmpty
        ? 'Group${groups.length == 1 ? '' : 's'}'
        : 'Items';
    await _runMassDelete(
      cards,
      groups: groups,
      title: 'Delete $total $what?',
      message:
          'This will PERMANENTLY delete the $total selected '
          'item${total == 1 ? '' : 's'} — character cards, image files, '
          'chat histories, any linked worlds, and group chats (a deleted '
          'group does NOT delete its member characters, but its chats are '
          'gone). There is no undo and no recycle bin.',
      afterDelete: () async => _cancelSelection(),
    );
  }

  /// The ONE severe-delete pipeline shared by mass select and
  /// delete-folder-with-characters: typed-DELETE gate → progress dialog →
  /// CharacterRepository.deleteCharacters (+ GroupChatRepository.delete for
  /// any selected [groups]) → optional follow-up → snackbar.
  Future<void> _runMassDelete(
    List<CharacterCard> cards, {
    List<GroupChat> groups = const [],
    required String title,
    required String message,
    Future<void> Function()? afterDelete,
  }) async {
    final confirmed = await showTypeDeleteDialog(
      context,
      title: title,
      message: message,
    );
    if (!confirmed || !mounted) return;

    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final worldRepo = Provider.of<WorldRepository>(context, listen: false);
    final storage = Provider.of<StorageService>(context, listen: false);
    final groupRepo = Provider.of<GroupChatRepository>(context, listen: false);
    final total = cards.length + groups.length;

    final progress = ValueNotifier<int>(0);
    // Non-dismissible counter while a 100+ card purge grinds through file IO.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(ctx),
        content: ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (ctx, done, _) => Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Deleting… $done of $total',
                  style: TextStyle(color: AppColors.textPrimary(ctx)),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    var deleted = 0;
    try {
      deleted = await repo.deleteCharacters(
        cards,
        worldRepo: worldRepo,
        chatsDir: storage.chatsDir,
        onProgress: (done, _) => progress.value = done,
      );
      var groupsDone = 0;
      for (final g in groups) {
        await groupRepo.delete(g.id);
        groupsDone++;
        deleted++;
        progress.value = cards.length + groupsDone;
      }
      await afterDelete?.call();
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      progress.dispose();
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deleted $deleted item${deleted == 1 ? '' : 's'}.'),
        ),
      );
    }
  }

  Future<void> _editCharacter(
    BuildContext context,
    CharacterCard character,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditCharacterPage(character: character),
      ),
    );
    // No loadCharacters() needed here — updateCharacter() already updates the
    // in-memory list and calls notifyListeners(). Calling loadCharacters() was
    // re-reading outdated in-memory extensions from the cache and overwriting
    // the freshly-saved values.
  }

  Future<void> _duplicateCharacter(
    BuildContext context,
    CharacterCard character,
  ) async {
    try {
      final folders = Provider.of<FolderService>(context, listen: false);
      final copy = await Provider.of<CharacterRepository>(
        context,
        listen: false,
      ).duplicateCharacter(character);
      // The duplicate belongs wherever the original lives — folder
      // membership is filename-keyed, so without this the copy landed on
      // the home screen's top level regardless of the source's folder.
      await folders.inheritFolder(character.imagePath, copy?.imagePath);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Character duplicated successfully.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to duplicate: $e')));
      }
    }
  }
}
