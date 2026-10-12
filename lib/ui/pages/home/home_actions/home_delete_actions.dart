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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

// Single, mass and group deletes from the library grid.

void confirmDeleteHomeCharacter(BuildContext context, CharacterCard character) {
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
          final repo = Provider.of<CharacterRepository>(context, listen: false);
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

void confirmDeleteHomeGroup(BuildContext context, GroupChat group) {
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

/// Mass delete for the select-mode bar: resolve the selection ids (each
/// card's stableGroupId, the key LibrarySelection holds: the image's
/// basename, or a cleaned-up name when there is no image) back to cards,
/// gather any selected groups ([groupIds]), then run the shared
/// severe-confirm purge on both. [hiddenCount] is how many picks the
/// current search or folder hides.
Future<void> massDeleteHomeSelection(
  BuildContext context,
  Set<String> ids, {
  required Set<String> groupIds,
  required int Function() hiddenCount,
  required VoidCallback onDeleted,
}) async {
  final repo = Provider.of<CharacterRepository>(context, listen: false);
  final groupRepo = Provider.of<GroupChatRepository>(context, listen: false);
  final cards = repo.characters.where((c) {
    final id = c.imagePath != null
        ? path.basenameWithoutExtension(c.imagePath!)
        : c.name.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_');
    return ids.contains(id);
  }).toList();
  final groups = groupRepo.groups
      .where((g) => groupIds.contains(g.id))
      .toList();
  if (cards.isEmpty && groups.isEmpty) return;

  final total = cards.length + groups.length;
  final what = groups.isEmpty
      ? 'Character${cards.length == 1 ? '' : 's'}'
      : cards.isEmpty
      ? 'Group${groups.length == 1 ? '' : 's'}'
      : 'Items';
  // Picks a later search or folder change hid are still in the selection
  // (#347), so the warning says how many of them are out of sight.
  final hidden = hiddenCount();
  final hiddenNote = hidden > 0
      ? ' ($hidden of them hidden by your search or folder)'
      : '';
  await runHomeMassDelete(
    context,
    cards,
    groups: groups,
    title: 'Delete $total $what?',
    message:
        'This will PERMANENTLY delete the $total selected '
        'item${total == 1 ? '' : 's'}$hiddenNote — character cards, image files, '
        'chat histories, any linked worlds, and group chats (a deleted '
        'group does NOT delete its member characters, but its chats are '
        'gone). There is no undo and no recycle bin.',
    afterDelete: () async => onDeleted(),
  );
}

/// The ONE severe-delete pipeline shared by mass select and
/// delete-folder-with-characters: typed-DELETE gate → progress dialog →
/// CharacterRepository.deleteCharacters (+ GroupChatRepository.delete for
/// any selected [groups]) → optional follow-up → snackbar.
Future<void> runHomeMassDelete(
  BuildContext context,
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
  if (!confirmed || !context.mounted) return;

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
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    progress.dispose();
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Deleted $deleted item${deleted == 1 ? '' : 's'}.'),
      ),
    );
  }
}
