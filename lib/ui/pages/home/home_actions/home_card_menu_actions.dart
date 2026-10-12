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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_controller.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_dialog.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page.dart';
import 'package:front_porch_ai/ui/pages/edit_group_page.dart';
import 'package:front_porch_ai/ui/pages/home/enhance/enhance_wizard_page.dart';
import 'package:front_porch_ai/ui/pages/home/home_actions/home_chat_opener.dart';
import 'package:front_porch_ai/ui/pages/home/home_actions/home_delete_actions.dart';
import 'package:front_porch_ai/ui/pages/home/home_actions/home_move_dialog.dart';
import 'package:front_porch_ai/ui/pages/home/home_actions/home_transfer_actions.dart';

// The library cards' right-click menus. [activeFolderId] is the folder the
// grid is showing (null at the top level).

void runHomeCharacterMenuAction(
  BuildContext context,
  String action,
  CharacterCard character, {
  required HomeChatOpener chats,
  required String? activeFolderId,
}) {
  switch (action) {
    case 'new_chat':
      chats.startNewChatWith(character: character);
      break;
    case 'chat_history':
      chats.showChatHistory(character: character);
      break;
    case 'edit':
      _editCharacter(context, character);
      break;
    case 'ai_enhance':
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EnhanceWizardPage(character: character),
        ),
      );
      break;
    case 'avatar_gallery':
      // Replace-portrait / star both call repository.updateCharacter, which
      // notifyListeners() → the home grid rebuilds on its own (same as edit).
      showAvatarGallery(
        context: context,
        character: character,
        repository: Provider.of<CharacterRepository>(context, listen: false),
        storage: Provider.of<StorageService>(context, listen: false),
        mode: WardrobeMode.library,
      );
      break;
    case 'duplicate':
      _duplicateCharacter(context, character);
      break;
    case 'export':
      exportHomeCharacterPng(context, character);
      break;
    case 'export_json':
      exportHomeCharacterJson(context, character);
      break;
    case 'move_folder':
      final moveService = Provider.of<FolderService>(context, listen: false);
      showHomeMoveToFolderDialog(
        context,
        moveService,
        title: 'Move "${character.name}" to folder',
        onMove: (folderId) async {
          if (character.imagePath == null) return;
          if (folderId == null) {
            await moveService.removeFromFolder(null, character.imagePath!);
          } else {
            await moveService.addToFolder(folderId, character.imagePath!);
          }
        },
      );
      break;
    case 'remove_folder':
      final folderService = Provider.of<FolderService>(context, listen: false);
      if (activeFolderId != null && character.imagePath != null) {
        folderService.removeFromFolder(activeFolderId, character.imagePath!);
      }
      break;
    case 'delete':
      confirmDeleteHomeCharacter(context, character);
      break;
  }
}

void runHomeGroupMenuAction(
  BuildContext context,
  String action,
  GroupChat group, {
  required HomeChatOpener chats,
  required String? activeFolderId,
}) {
  switch (action) {
    case 'new_chat':
      chats.startNewChatWith(group: group);
      break;
    case 'chat_history':
      chats.showChatHistory(group: group);
      break;
    case 'edit':
      _editGroup(context, group);
      break;
    case 'duplicate':
      _duplicateGroup(context, group);
      break;
    case 'export':
      exportHomeGroupCard(context, group);
      break;
    case 'extract':
      extractHomeGroupCharacters(context, group);
      break;
    case 'move_folder':
      final folderService = Provider.of<FolderService>(context, listen: false);
      showHomeMoveToFolderDialog(
        context,
        folderService,
        title: 'Move "${group.name}" to folder',
        onMove: (folderId) => folderId == null
            ? folderService.removeGroupFromFolder(null, group.id)
            : folderService.addGroupToFolder(folderId, group.id),
      );
      break;
    case 'remove_folder':
      if (activeFolderId != null) {
        Provider.of<FolderService>(
          context,
          listen: false,
        ).removeGroupFromFolder(activeFolderId, group.id);
      }
      break;
    case 'delete':
      confirmDeleteHomeGroup(context, group);
      break;
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

Future<void> _editGroup(BuildContext context, GroupChat group) async {
  await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => EditGroupPage(group: group)),
  );
  // GroupChatRepository.save() already calls notifyListeners(),
  // so the home grid rebuilds automatically after edit.
}

void _duplicateGroup(BuildContext context, GroupChat group) {
  // Placeholder — real implementation will copy the GroupChat definition (new id, "Copy of" name, same seeds/ lore / worlds / prompts).
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Duplicate Group not yet implemented: ${group.name}'),
      ),
    );
  }
}
