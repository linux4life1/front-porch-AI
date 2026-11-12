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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/world_store/world_store.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page/edit_character_lorebook_tab.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page/edit_character_worlds_tab.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page/edit_lorebook_actions.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Shown on the Lorebook tab when the stored group lorebook can't be read.
const kEditGroupUnreadableLoreNote =
    "This group's lorebook couldn't be read, so its entries aren't being "
    'used. New entries you add here can replace it; Save asks first.';

/// Lorebook tab of the group editor: the 1:1 Lorebook tab over the group's
/// lorebook, plus "Inherit character & world lorebooks".
class EditGroupLorebookTab extends StatelessWidget {
  const EditGroupLorebookTab({
    super.key,
    required this.actions,
    required this.entries,
    required this.bookUnreadable,
    required this.inheritCharacterLorebooks,
    required this.onInheritChanged,
    required this.onChanged,
  });

  final EditorLorebookActions actions;
  final List<LorebookEntry> entries;
  final bool bookUnreadable;
  final bool inheritCharacterLorebooks;
  final ValueChanged<bool> onInheritChanged;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return EditCharacterLorebookTab(
      entries: entries,
      onImportFile: actions.importFile,
      onExportFile: actions.exportFile,
      onImportFromCharacter: actions.importFromCharacter,
      onAddEntry: actions.add,
      onEditEntry: actions.edit,
      onRemoveEntry: actions.remove,
      onChanged: onChanged,
      header: bookUnreadable
          ? Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                kEditGroupUnreadableLoreNote,
                style: TextStyle(color: AppColors.porchAmberOf(context)),
              ),
            )
          : null,
      footer: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: SwitchListTile(
          key: const Key('group-inherit-lore'),
          title: const Text('Inherit character & world lorebooks'),
          subtitle: const Text(
            'When on, member cards and their attached worlds contribute lore '
            'in addition to the group lorebook above.',
          ),
          value: inheritCharacterLorebooks,
          onChanged: onInheritChanged,
        ),
      ),
    );
  }
}

/// Worlds tab of the group editor: the 1:1 Worlds tab for the whole cast.
class EditGroupWorldsTab extends StatelessWidget {
  const EditGroupWorldsTab({
    super.key,
    required this.value,
    required this.onChanged,
    required this.suggestedBy,
    required this.legacyWorldCount,
  });

  final GroupWorldChoice value;
  final ValueChanged<GroupWorldChoice> onChanged;
  final Map<String, List<String>> suggestedBy;
  final int legacyWorldCount;

  @override
  Widget build(BuildContext context) {
    return EditCharacterWorldsTab(
      value: value,
      onChanged: onChanged,
      characterName: '',
      owner: 'the group',
      suggestedBy: suggestedBy,
      legacyWorldCount: legacyWorldCount,
    );
  }
}

/// Whether Save keeps the stored (unreadable) lorebook text: true keeps it,
/// false writes the entries on screen, null cancels the save. A readable
/// book is always written from the screen; an unreadable one is replaced
/// only when the user, asked here, says so.
Future<bool?> keepUnreadableGroupLorebook(
  BuildContext context, {
  required bool bookUnreadable,
  required bool hasEntries,
}) async {
  if (!bookUnreadable) return false;
  if (!hasEntries) return true;
  final replace = await showWarmDialog<bool>(
    context,
    title: 'Replace the old lorebook?',
    icon: Icons.menu_book,
    content: const WarmDialogText(
      "This group's old lorebook couldn't be read. Saving the entries you "
      'added replaces it for good. Keep it to save your other changes and '
      'leave the old lorebook as it is.',
    ),
    actions: [
      warmDialogCancel(context, label: 'Keep old lorebook', value: false),
      warmDialogConfirm(
        context,
        label: 'Replace it',
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ],
  );
  if (replace == null) return null;
  return !replace;
}
